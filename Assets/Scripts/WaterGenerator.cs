using UnityEngine;

public class WaterGenerator : MonoBehaviour
{
    public Shader waterShader;

    [Header ("Water Settings")]
    public int mapSize = 255;
    public float scale = 20;
    public float height = 3.4f;
    
    public float initialFrequency = 2;
    public float initialSpeed = 2;
    public float waterDepth = 1;
    public int interationsWaves = 20;
	public int iterationsNormal = 40;
    public float dragMulti = 0.28f;
    public Material waterMaterial; 

    Mesh mesh;
    Vector3[] verts;
    int[] triangles;

    void CreateMaterial() {
        if (waterShader == null) return;
        if (waterMaterial != null) return;
        waterMaterial = new Material(waterShader);
        
        MeshRenderer renderer = GetComponent<MeshRenderer>();
        renderer.material = waterMaterial;
    }

    void Start(){
        mesh = new Mesh();
        GetComponent<MeshFilter>().mesh = mesh;
        CreateMesh();
        CreateMaterial();
    }

    void Update(){
        waterMaterial.SetFloat("_initialFrequency", initialFrequency);
        waterMaterial.SetFloat("_initialSpeed", initialSpeed);
        waterMaterial.SetFloat("_waterDepth", waterDepth);
        waterMaterial.SetInt("_interationsWaves", interationsWaves);
        waterMaterial.SetInt("_iterationsNormal", iterationsNormal);
        waterMaterial.SetFloat("_dragMulti", dragMulti);
    }

    void CreateMesh(){
        verts = new Vector3[mapSize * mapSize];
        triangles = new int[(mapSize - 1) * (mapSize - 1) * 6];

        int t = 0;
        for (int i = 0; i < mapSize * mapSize; i++) {
            int x = i % mapSize;
            int y = i / mapSize;
            int meshMapIndex = y * mapSize + x;

            Vector2 percent = new Vector2 (x / (mapSize - 1f), y / (mapSize - 1f));
            Vector3 pos = new Vector3 (percent.x * 2 - 1, 0, percent.y * 2 - 1) * scale;

            pos += Vector3.up * height;
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

        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.vertices = verts;
        mesh.triangles = triangles;
    }
}
