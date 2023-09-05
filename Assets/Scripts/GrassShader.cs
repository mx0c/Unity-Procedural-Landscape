using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class GrassShader : MonoBehaviour
{
    public Shader grassShader;
    private Material material;

    // Start is called before the first frame update
    void Start()
    {
        MeshRenderer meshRenderer = GetComponent<MeshRenderer> ();
        material = new Material(grassShader);
        meshRenderer.material = material;
    }

    // Update is called once per frame
    void Update()
    {
        
    }
}
