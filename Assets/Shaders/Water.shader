Shader "Custom/Water"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BaseColor("Base Color", color) = (0,0.7310064,0.8862745,1)
        _Smoothness("Smoothness", Range(0,1)) = 0.6
        _Opacity("Opacity", Range(0,1)) = 0.98
        _Metallic("Metallic", Range(0,1)) = 1
    }
    SubShader
    {
        Tags { 
            "RenderType"="Opaque" 
            "RenderPipeline" = "UniversalRenderPipeline" 
            "Queue" = "Transparent"
        }
        LOD 100

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"

            #define PI 3.14159265358979323846  

            float _initialFrequency, _initialSpeed, _waterDepth, _dragMulti;
			int _interationsWaves, _iterationsNormal;

			struct VertexData {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
			};

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 viewDir : TEXCOORD3;
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 4);
            };

			float2 Wave(float3 v, float2 d, float frequency, float timeshift) {
				float3 randDir = float3(d.x, d.y, 1.0);
				float x = dot(v, randDir) * frequency + timeshift;
				float wave = exp(sin(x) - 1.0);
				float dx = wave * cos(x);
				return float2(wave, -dx);
			}

			float getWaves(float3 position, int iterations){
				float iter = 0.0;
				float frequency = _initialFrequency;
				float timeMultiplier = _initialSpeed;
				float weight = 1.0;// weight in final sum for the wave, this will change every iteration
				float sumOfValues = 0.0; // will store final sum of values
				float sumOfWeights = 0.0; // will store final sum of weights
				for(int idx = 0; idx < iterations; idx++ ){
						// generate some wave direction that looks kind of random
						float2 randDir = float2(sin(-iter), cos(iter));	

						// calculate wave data
    					float2 res = Wave(position, randDir, frequency, _Time.y * timeMultiplier);
						
						// shift position around according to wave drag and derivative of the wave
						float2 tmpPos = randDir * res.y * weight * _dragMulti;
						position.y += tmpPos.y;
						position.x += tmpPos.x;

						// add the results to sums
						sumOfValues += res.x * weight;
						sumOfWeights += weight;

						// modify next octave parameters -> Fractional Brownian motion 
						weight *= 0.93;
						frequency *= 1.18;
						timeMultiplier *= 1.07;

						// add some kind of random value to make next wave look random too
						iter += 1232.399963;
				}
				// calculate and return
				return sumOfValues / sumOfWeights;
			}

            //This is a replacement for the old 'UnityObjectToClipPos()'
            float4 ObjectToClipPos (float3 pos)
            {
                return mul (UNITY_MATRIX_VP, mul (UNITY_MATRIX_M, float4 (pos,1)));
            }

			float3 normal(float3 pos, float e, float depth) {
				float3 ex = float3(e, 0, 0);
				float H = getWaves(pos, _interationsWaves) * depth;
				float3 a = float3(pos.x, H, pos.y);
				return normalize(
					cross(
						a - float3(pos.x - e, getWaves(pos - ex, _interationsWaves) * depth, pos.y), 
						a - float3(pos.x, getWaves(pos + ex, _interationsWaves) * depth, pos.y + e)
					)
				);
			}

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _BaseColor;
            float _Smoothness, _Metallic, _Opacity;

            v2f vert (VertexData v)
            {
                v2f o;

				o.positionWS = mul(unity_ObjectToWorld, v.vertex);
				
				float h = getWaves(o.positionWS, _interationsWaves) * _waterDepth - _waterDepth;
				o.vertex = ObjectToClipPos(v.vertex + float4(0.0f, h, 0.0f, 0.0f));

				float3 N = normal(o.positionWS, 0.01, _waterDepth);
				o.normalWS = TransformObjectToWorldNormal(float3(-N.x, 1.0f, -N.y));

				return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                InputData inputdata = (InputData)0;
                inputdata.positionWS = i.positionWS;
                inputdata.normalWS = i.normalWS;
                inputdata.viewDirectionWS = i.viewDir;

                SurfaceData surfacedata;
                surfacedata.albedo = _BaseColor;
                surfacedata.specular = 0;
                surfacedata.metallic = _Metallic;
                surfacedata.smoothness = _Smoothness;
                surfacedata.normalTS = 0;
                surfacedata.emission = 0;
                surfacedata.occlusion = 0;
                surfacedata.alpha = _Opacity;
                surfacedata.clearCoatMask = 1;
                surfacedata.clearCoatSmoothness = 1;

                return UniversalFragmentPBR(inputdata, surfacedata);
            }
            ENDHLSL
        }
    }
}