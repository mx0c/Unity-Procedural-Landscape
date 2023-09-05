Shader "Custom/Water"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BaseColor("Base Color", color) = (0,0.7310064,0.8862745,1)
        _Smoothness("Smoothness", Range(0,1)) = 0.9
        _Metallic("Metallic", Range(0,1)) = 0
        _Opacity("Opacity", Range(0,1)) = 0.65
        _DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)
        _DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)
        _DepthMaxDistance("Depth Maximum Distance", Float) = 5
        _FoamDistance("Foam Distance", Float) = 0.6
    }
    SubShader
    {
        Tags { 
            "LightMode"="UniversalForward"
            "RenderPipeline" = "UniversalRenderPipeline" 
            "Queue" = "Transparent"
        }
        LOD 100
        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            #define PI 3.14159265358979323846  

            float _initialFrequency, _initialSpeed, _waterDepth, _dragMulti;
			int _interationsWaves, _iterationsNormal;
            
            float4 _BaseColor, _EmissionColor;
            float _Smoothness, _Metallic, _Opacity;

            float4 _DepthGradientDeep, _DepthGradientShallow;
            Float _DepthMaxDistance, _FoamDistance;

			struct VertexData {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
			};

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD5;
                float4 screenPos : TEXCOORD3; 
                float4 vertex : SV_POSITION;
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

            half SampleOcclusion(float2 uv) {
                #ifdef _OCCLUSIONMAP
                #if defined(SHADER_API_GLES)
                    return SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
                #else
                    half occ = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
                    return LerpWhiteTo(occ, _OcclusionStrength);
                #endif
                #else
                    return 1.0;
                #endif
            }

            v2f vert (VertexData v)
            {
                v2f o;
				o.positionWS = mul(unity_ObjectToWorld, v.vertex);
				
				float h = getWaves(o.positionWS, _interationsWaves) * _waterDepth - _waterDepth;
				o.vertex = TransformWorldToHClip(v.vertex + float4(0.0f, h, 0.0f, 0.0f));

				float3 N = normal(o.positionWS, 0.01, _waterDepth);
				o.normalWS = TransformObjectToWorldNormal(float3(-N.x, 1.0f, -N.y));

                float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
                o.screenPos = ComputeScreenPos(o.vertex); 

				return o;
            }



            half4 frag (v2f i) : SV_Target
            {
                float existingDepth01 = SampleSceneDepth(i.screenPos.xy / i.screenPos.w);
                float existingDepthLinear = LinearEyeDepth(existingDepth01, _ZBufferParams);

                float depthDifference = existingDepthLinear - i.screenPos.w;
                float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
                float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);

                float foamDepthDifference01 = saturate(depthDifference / _FoamDistance);
                float4 foamColor = lerp(float4(1,1,1,1), float4(0,0,0,0), foamDepthDifference01);

                InputData inputdata = (InputData)0;
                inputdata.positionWS = i.positionWS;
                inputdata.normalWS = NormalizeNormalPerPixel(i.normalWS);
	            inputdata.viewDirectionWS = SafeNormalize(GetWorldSpaceNormalizeViewDir(i.positionWS));
                inputdata.shadowCoord =  TransformWorldToShadowCoord(i.positionWS);
                
                SurfaceData surfacedata = (SurfaceData)0;

                half4 albedoAlpha = SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
	            surfacedata.albedo =  _BaseColor.rgb * 0.5 + waterColor + foamColor;

                surfacedata.normalTS = SampleNormal(i.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap));
                surfacedata.emission = SampleEmission(i.uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap));
                surfacedata.occlusion = SampleOcclusion(i.uv);

                surfacedata.metallic = _Metallic;
                surfacedata.smoothness = _Smoothness;

                surfacedata.alpha = _Opacity;

                return UniversalFragmentPBR(inputdata, surfacedata);
            }
            ENDHLSL
        }
    }
}