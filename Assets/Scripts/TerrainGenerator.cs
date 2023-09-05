using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

[RequireComponent(typeof(MeshFilter))]
public class MeshGeneratorScript : MonoBehaviour
{
    [Header ("Mesh Settings")]
    public int mapSize = 255;
    public float scale = 20;
    public float elevationScale = 10;
    public int erosionIterations = 10000;
    public bool useErosion = true;
    public bool useGPUHeightMapGen = true;
    public Shader terrainShader;
    public Shader grassShader;
    public Material grassMaterial;
    public Material terrainMaterial;
    public Gradient gradient;

    // Internal
    Mesh mesh;
    Erosion erosion;
    Vector3[] verts;
    int[] triangles;
    float[] heightMap;
    HeightMapGenerator heightMapGenerator;
    MeshRenderer meshRenderer;
    MeshFilter meshFilter;
    Color[] colors;
    float maxHeight, minHeight;

    // Start is called before the first frame update
    void Start()
    {   
        mesh = new Mesh();
        GetComponent<MeshFilter>().mesh = mesh;

        CreateMesh();
        AddMaterials();
        SetMeshCollider();
    }

    void Update(){
        setColorMap();
    }

    void setColorMap(){
        // setting colormap
        for (int i = 0; i < mapSize * mapSize; i++) {
            int x = i % mapSize;
            int y = i / mapSize;
            int meshMapIndex = y * mapSize + x;

            float height = Mathf.InverseLerp(minHeight, maxHeight, heightMap[meshMapIndex]);
            colors[i] = gradient.Evaluate(height);
        }
        mesh.colors = colors;
    }

    void SetMeshCollider(){
        if (mesh != null){
            MeshCollider meshCollider = GameObject.FindAnyObjectByType(typeof(MeshCollider)) as MeshCollider;
            meshCollider.sharedMesh = mesh;
        }
    }

    void CreateMesh(){
        // generate HeightMap
        heightMapGenerator = GameObject.FindAnyObjectByType(typeof(HeightMapGenerator)) as HeightMapGenerator;
        if(this.useGPUHeightMapGen){
            heightMap = heightMapGenerator.GenerateGPU(mapSize);
        }else{
            heightMap = heightMapGenerator.GenerateCPU(mapSize);
        }

        // Erode Heightmap
        if(useErosion){
            erosion = GameObject.FindAnyObjectByType(typeof(Erosion)) as Erosion;
            heightMap = erosion.Erode(heightMap, mapSize, erosionIterations);
        }

        verts = new Vector3[mapSize * mapSize];
        triangles = new int[(mapSize - 1) * (mapSize - 1) * 6];
        colors = new Color[mapSize * mapSize];

        int t = 0;
        for (int i = 0; i < mapSize * mapSize; i++) {
            int x = i % mapSize;
            int y = i / mapSize;
            int meshMapIndex = y * mapSize + x;

            Vector2 percent = new Vector2 (x / (mapSize - 1f), y / (mapSize - 1f));
            Vector3 pos = new Vector3 (percent.x * 2 - 1, 0, percent.y * 2 - 1) * scale;

            float normalizedHeight = heightMap[meshMapIndex];
            if(minHeight > normalizedHeight)
                minHeight = normalizedHeight;
            if(maxHeight < normalizedHeight)
                maxHeight = normalizedHeight;

            pos += Vector3.up * normalizedHeight * elevationScale;
            verts[meshMapIndex] = pos;
            

            // Construct triangles
            if (x != mapSize - 1 && y != mapSize - 1) {
                t = (y * (mapSize - 1) + x) * 3 * 2;

                triangles[t + 0] = meshMapIndex + mapSize;
                triangles[t + 1] = meshMapIndex + mapSize + 1;
                triangles[t + 2] = meshMapIndex;

                triangles[t + 3] = meshMapIndex + mapSize + 1;
                triangles[t + 4] = meshMapIndex + 1;
                triangles[t + 5] = meshMapIndex;
                t += 6;
            }
        }
        
        // Find/creator mesh holder object in children
        string meshHolderName = "Mesh Holder";
        Transform meshHolder = transform.Find (meshHolderName);
        if (meshHolder == null) {
            meshHolder = new GameObject (meshHolderName).transform;
            meshHolder.transform.parent = transform;
            meshHolder.transform.SetLocalPositionAndRotation(Vector3.zero, Quaternion.identity);
        }

        // Ensure mesh renderer and filter components are assigned
        if (!meshHolder.gameObject.GetComponent<MeshFilter> ()) {
            meshHolder.gameObject.AddComponent<MeshFilter> ();
        }
        if (!meshHolder.GetComponent<MeshRenderer> ()) {
            meshHolder.gameObject.AddComponent<MeshRenderer> ();
        }

        meshRenderer = meshHolder.GetComponent<MeshRenderer> ();
        meshFilter = meshHolder.GetComponent<MeshFilter> ();
        
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.vertices = verts;
        mesh.triangles = triangles;
        mesh.colors = colors;
        mesh.RecalculateNormals();
        mesh.RecalculateTangents();
        meshFilter.sharedMesh = mesh;
    }

    public void AddMaterials() {
        if(terrainShader != null){
            this.terrainMaterial = new Material(terrainShader);
            meshRenderer.sharedMaterials = AddMaterial(meshRenderer.sharedMaterials, this.terrainMaterial);
        }
        if(grassShader != null){
            this.grassMaterial = new Material(grassShader);
            meshRenderer.sharedMaterials = AddMaterial(meshRenderer.sharedMaterials, this.grassMaterial);
        }
    }

    public Material[] AddMaterial(Material[] target, Material item)
    {
        if (target == null)
            return null;
        Material[] result = new Material[target.Length + 1];
        target.CopyTo(result, 0);
        result[target.Length] = item;
        return result;
    }
}