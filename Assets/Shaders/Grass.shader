Shader "Custom/Grass"
{
     Properties
     {
        _BaseColor("Base Color", Color) = (0.09634682, 0.4716981, 0, 1)
        _TipColor("Tip Color", Color) = (0.02436233, 1, 0, 1)
        _BladeTexture("Blade Texture", 2D) = "white" {}

        _BladeWidthMin("Blade Width (Min)", Range(0, 0.1)) = 0.02
        _BladeWidthMax("Blade Width (Max)", Range(0, 0.1)) = 0.05
        _BladeHeightMin("Blade Height (Min)", Range(0, 2)) = 0.1
        _BladeHeightMax("Blade Height (Max)", Range(0, 2)) = 0.2

        _BladeSegments("Blade Segments", Range(1, 10)) = 3
        _BladeBendDistance("Blade Forward Amount", Float) = 0.38
        _BladeBendCurve("Blade Curvature Amount", Range(1, 4)) = 2

        _BendDelta("Bend Variation", Range(0, 1)) = 0.2

        _TessellationGrassDistance("Tessellation Grass Distance", Range(0.01, 2)) = 0.1

        _GrassMap("Grass Visibility Map", 2D) = "white" {}
        _GrassThreshold("Grass Visibility Threshold", Range(-0.1, 300)) = 0.5
        _GrassFalloff("Grass Visibility Fade-In Falloff", Range(0, 100)) = 0.05

        _WindMap("Wind Offset Map", 2D) = "bump" {}
        _WindVelocity("Wind Velocity", Vector) = (1, 0, 0, 0)
        _WindFrequency("Wind Pulse Frequency", Range(0, 1)) = 0.01
     }
     SubShader
     {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }
        LOD 100
        Cull Off
        Pass
        {
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _SHADOWS_SOFT

            #pragma require tessellation 
            #pragma require geometry
            
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geom
            #pragma vertex geomVert
            #pragma fragment fragment

            #define UNITY_PI 3.14159265359f
            #define UNITY_TWO_PI 6.28318530718f
            #define BLADE_SEGMENTS 3
            
            CBUFFER_START(UnityPerMaterial)
            float4 _BaseColor;
            float4 _TipColor;
            sampler2D _BladeTexture;

            float _BladeWidthMin;
            float _BladeWidthMax;
            float _BladeHeightMin;
            float _BladeHeightMax;

            float _BladeBendDistance;
            float _BladeBendCurve;

            float _BendDelta;

            float _TessellationGrassDistance;
            
            sampler2D _GrassMap;
            float4 _GrassMap_ST;
            float  _GrassThreshold;
            float  _GrassFalloff;

            sampler2D _WindMap;
            float4 _WindMap_ST;
            float4 _WindVelocity;
            float  _WindFrequency;

            float4 _ShadowColor;
            CBUFFER_END

            struct VertexInput
            {
                float4 vertex  : POSITION;
                float3 normal  : NORMAL;
                float4 tangent : TANGENT;
                float2 uv      : TEXCOORD0;
            };

            struct VertexOutput
            {
                float4 vertex  : SV_POSITION;
                float3 normal  : NORMAL;
                float4 tangent : TANGENT;
                float2 uv      : TEXCOORD0;
            };

            struct GeomData
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
            };

            float rand(float3 co)
            {
                return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
            }

            // Construct a rotation matrix that rotates around the provided axis, sourced from:
            // https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
            float3x3 angleAxis3x3(float angle, float3 axis)
            {
                float c, s;
                sincos(angle, s, c);

                float t = 1 - c;
                float x = axis.x;
                float y = axis.y;
                float z = axis.z;

                return float3x3
                (
                    t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                    t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                    t * x * z - s * y, t * y * z + s * x, t * z * z + c
                );
            }

            GeomData TransformGeomToClip(float3 pos, float3 offset, float3x3 transformationMatrix, float2 uv)
            {
                GeomData o;

                o.pos = TransformObjectToHClip(pos + mul(transformationMatrix, offset));
                o.uv = uv;
                o.worldPos = TransformObjectToWorld(pos + mul(transformationMatrix, offset));

                return o;
            }

            float tessellationEdgeFactor(VertexInput vert0, VertexInput vert1)
            {
                float3 v0 = vert0.vertex.xyz;
                float3 v1 = vert1.vertex.xyz;
                float edgeLength = distance(v0, v1);
                return edgeLength / _TessellationGrassDistance;
            }

            VertexOutput geomVert (VertexInput v)
            {
                VertexOutput o; 
                o.vertex = float4(TransformObjectToWorld(v.vertex), 1.0f);
                o.normal = v.normal;
                o.tangent = v.tangent;
                o.uv = TRANSFORM_TEX(v.uv, _GrassMap);
                return o;
            }

            [maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
            void geom(point VertexOutput input[1], inout TriangleStream<GeomData> triStream)
            {
                float3 pos = input[0].vertex.xyz;
                float height = pos.y;
                
                if (height >= _GrassThreshold)
                {
                    float3 normal = input[0].normal;
                    float4 tangent = input[0].tangent;
                    float3 bitangent = cross(normal, tangent.xyz) * tangent.w;

                    float3x3 tangentToLocal = float3x3
                    (
                        tangent.x, bitangent.x, normal.x,
                        tangent.y, bitangent.y, normal.y,
                        tangent.z, bitangent.z, normal.z
                    );

                    // Rotate around the y-axis a random amount.
                    float3x3 randRotMatrix = angleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));

                    // Rotate around the bottom of the blade a random amount.
                    float3x3 randBendMatrix = angleAxis3x3(rand(pos.zzx) * _BendDelta * UNITY_PI * 0.5f, float3(-1.0f, 0, 0));

                    // Transform the grass blades to the correct tangent space.
                    float3x3 baseTransformationMatrix = mul(tangentToLocal, randRotMatrix);
                    float3x3 tipTransformationMatrix = mul(baseTransformationMatrix, randRotMatrix);

                    float falloff = smoothstep(_GrassThreshold, (_GrassThreshold + _GrassFalloff), height);

                    float width  = lerp(_BladeWidthMin, _BladeWidthMax, rand(pos.xzy) * falloff);
                    float height = lerp(_BladeHeightMin, _BladeHeightMax, rand(pos.zyx) * falloff);
                    float forward = rand(pos.yyz) * _BladeBendDistance;
                    
                    // Create blade segments by adding two vertices at once.
                    for (int i = 0; i < BLADE_SEGMENTS; ++i)
                    {
                        float t = i / (float)BLADE_SEGMENTS;
                        float3 offset = float3(width * (1 - t), pow(t, _BladeBendCurve) * forward, height * t);

                        float3x3 transformationMatrix = (i == 0) ? baseTransformationMatrix : tipTransformationMatrix;

                        triStream.Append(TransformGeomToClip(pos, float3( offset.x, offset.y, offset.z), transformationMatrix, float2(0, t)));
                        triStream.Append(TransformGeomToClip(pos, float3(-offset.x, offset.y, offset.z), transformationMatrix, float2(1, t)));
                    }

                    // Add the final vertex at the tip of the grass blade.
                    triStream.Append(TransformGeomToClip(pos, float3(0, forward, height), tipTransformationMatrix, float2(0.5, 1)));                               
                    
                    triStream.RestartStrip();
                }
            }

            float4 fragment (GeomData i) : SV_Target
            {
               float4 color = tex2D(_BladeTexture, i.uv);

                #ifdef _MAIN_LIGHT_SHADOWS
                    VertexPositionInputs vertexInput = (VertexPositionInputs)0;
                    vertexInput.positionWS = i.worldPos;

                    float4 shadowCoord = GetShadowCoord(vertexInput);
                    half shadowAttenuation = saturate(MainLightRealtimeShadow(shadowCoord) + 0.25f);
                    float4 shadowColor = lerp(0.0f, 1.0f, shadowAttenuation);
                    color *= shadowColor;
                #endif

                return color * lerp(_BaseColor, _TipColor, i.uv.y);
            }

            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside  : SV_InsideTessFactor;
            };

            TessellationFactors patchConstantFunc(InputPatch<VertexInput, 3> patch)
			{
				TessellationFactors f;

				f.edge[0] = tessellationEdgeFactor(patch[1], patch[2]);
				f.edge[1] = tessellationEdgeFactor(patch[2], patch[0]);
				f.edge[2] = tessellationEdgeFactor(patch[0], patch[1]);
				f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0f;

				return f;
			}

            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [partitioning("integer")]
            [patchconstantfunc("patchConstantFunc")]
            VertexInput hull(InputPatch<VertexInput, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            VertexOutput tessVert(VertexInput v)
            {
                VertexOutput o;
                o.vertex = v.vertex;
                o.normal = v.normal;
                o.tangent = v.tangent;
                o.uv = v.uv;
                return o;
            }

            [domain("tri")]
            VertexOutput domain(TessellationFactors factors, OutputPatch<VertexInput, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
            {
                VertexInput i;

                // Create interpolation macro.
                #define INTERPOLATE(fieldname) i.fieldname = \
                    patch[0].fieldname * barycentricCoordinates.x + \
                    patch[1].fieldname * barycentricCoordinates.y + \
                    patch[2].fieldname * barycentricCoordinates.z;

                INTERPOLATE(vertex)
                INTERPOLATE(normal)
                INTERPOLATE(tangent)
                INTERPOLATE(uv)

                return tessVert(i);
            }

            ENDHLSL
        }
     }
}