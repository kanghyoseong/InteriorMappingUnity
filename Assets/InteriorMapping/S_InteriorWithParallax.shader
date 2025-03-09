Shader "InteriorWithParallax"
{
    Properties
    {
        _Cube("Cubemap", Cube) = "" {}
        _UseCubemap("UseCubemap", Range(0,1)) = 1
        _Height("Heightmap", 2D) = "white" {}
        _Diffuse("Diffuse", 2D) = "white" {}
        _Rotation("Rotation", Range(0,360)) = 0
        _Tiling("Tiling", Vector) = (1,1,1)
        _Step("Step", Range(1,1000)) = 1
        _MakeDither("MakeDither", Range(0,1)) = 1
        _DitherStep("DitherStep", Float) = 100
        _HeightScale("HeightScale", Range(0, 1)) = 1
    }

        SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" 
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            #define MAX_STEPS 100
            #define MAX_DIST 100
            #define SURFACE_DIST 1e-3

            struct Input
            {
                float4 position   : POSITION;
                float2 uv : TexCoord0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct Output
            {
                //interior
                float4 positionV  : SV_POSITION; // view space
                float3 positionL  : TexCoord1; // object space
                float3 positionW  : TexCoord4; // object space
                float2 uv : TexCoord0;
                float3 cameraPosL : TEXCOORD2;

                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float3 biTangent : TEXCOORD3;
            };

            samplerCUBE _Cube;
            sampler2D _Height;
            sampler2D _Diffuse;
            int _Rotation;
            float3 _Tiling;
            float _Step;
            float _MakeDither;
            float _UseCubemap;
            float _DitherStep;
            float _HeightScale;

            Output vert(Input IN)
            {
                Output OUT;

                OUT.uv = IN.uv;
                OUT.tangent = IN.tangent;
                OUT.normal = IN.normal; // world space normal
                OUT.positionV = TransformObjectToHClip(IN.position.xyz);
                OUT.positionW = TransformObjectToWorld(IN.position.xyz);
                OUT.positionL = IN.position.xyz;
                
                OUT.cameraPosL = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos, 1));

                OUT.biTangent = normalize(cross(IN.normal, IN.tangent.xyz));
                
                return OUT;
            }

            float3 GetNormal(float2 uv) {
                float2 e = float2(1e-2, 0); // epsilon

                float3 v1 = float3(e.x, tex2D(_Height, uv).r -
                    tex2D(_Height, uv - float2(e.x, e.y)).r, 0);
                float3 v2 = float3(0, tex2D(_Height, uv).r -
                    tex2D(_Height, uv - float2(e.y, e.x)).r, e.x);

                float3 n = cross(v2, v1);

                return normalize(n);
            }

            float random(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453123);
            }
          
            half4 frag(Output IN) : SV_Target
            {
                
                ////////// Interior Mapping ////////////
                float2 uvCentered = frac(IN.uv * _Tiling) * 2.0 - 1.0;

                float3x3 tangentTransform_World = float3x3(IN.tangent.xyz, IN.biTangent, IN.normal);
                float3 viewDir = TransformWorldToTangent(IN.positionL - IN.cameraPosL, tangentTransform_World);

                viewDir = normalize(viewDir) * float3(1, -1, 1);
                float3 division = 1.0 / viewDir;

                float3 abs_division = abs(division);
                float3 combine = abs_division - division * float3(uvCentered.x, uvCentered.y, 1);

                float3 minimum = min(min(combine.x, combine.y), combine.z);
                //When viewing the 'minimum' as a color, it should give the impression of being recessed inward.

                float3 final = viewDir * minimum;
                final += float3(uvCentered.x, uvCentered.y, 1.0);
                final.x *= -1; // Cubemap X invert

                half4 customColor = 0;

                //Rotate CubeMap with Global Y Axis
                float Rotation = radians(_Rotation);
                float s = sin(Rotation);
                float c = cos(Rotation);
                float one_minus_c = 1.0 - c;
                float3 Axis = float3(0, 1, 0);
                float3x3 rot_mat =
                { one_minus_c * Axis.x * Axis.x + c, one_minus_c * Axis.x * Axis.y - Axis.z * s, one_minus_c * Axis.z * Axis.x + Axis.y * s,
                    one_minus_c * Axis.x * Axis.y + Axis.z * s, one_minus_c * Axis.y * Axis.y + c, one_minus_c * Axis.y * Axis.z - Axis.x * s,
                    one_minus_c * Axis.z * Axis.x - Axis.y * s, one_minus_c * Axis.y * Axis.z + Axis.x * s, one_minus_c * Axis.z * Axis.z + c
                };
                final = mul(rot_mat, final);
                if (_UseCubemap) {
                    customColor = texCUBE(_Cube, final);
                }

                ////////// Parallax Mapping ////////////
                float customDepth = -0.0; // To make it fit exactly, use - 4.0.
                
                float heightScale = _HeightScale;

                //const float minLayers = 64.0f;
                //const float maxLayers = 512.0f;
                //Adjusts the number of layers based on the angle between the plane's normal and the camera.
                //IN.normal = TransformWorldToTangent(IN.normal, tangentTransform_World);
                float numLayers = _Step;// lerp(maxLayers, minLayers, abs(dot(IN.normal, viewDir)));
                // 90deg == 0, 0deg == 1 180deg == abs(-1) == 1, but the camera cannot reach it.

                float layerDepth = 1.0f / numLayers;

                viewDir.z *= -1;
                float temp = viewDir.y;
                viewDir.y = viewDir.z;
                viewDir.z = temp;

                //viewDir = float3(0.1, 1, -0.1);
                //viewDir = float3(0, 1, 0);

                viewDir = normalize(viewDir);

                float2 S = viewDir.xz / viewDir.y * heightScale;//Plane direction is +Y
                S *= -1.0;
                float2 deltaUVs = S / numLayers;

                float2 UVs = IN.uv;
                //float currentDepthMapValue_F = 1.0f - tex2D(_Height, UVs).r;
                float2 currentDepthMapValue = tex2D(_Height, UVs).rg;
                float currentLayerDepth = 1.0;

                // Direction: From Interior to player camera: 1.0, Opposite direction: 0.0

                bool isIntersect = false;

                UVs -= deltaUVs;

                //float randomValue = random(IN.uv);
                //randomValue = (randomValue - 0.5) * _DitherStep * 0.001;

                // The core part of interior mapping shader
                [loop] for (int i = 0; i < numLayers; i++) {
                    UVs -= deltaUVs;
                    if (UVs.x > 1 || UVs.y > 1 || UVs.x < 0 || UVs.y < 0) {
                        break;
                    }
                    //float h = (i + lerp(0, random(IN.uv) - 0.5, _DitherStep)) / numLayers;
                    if (_MakeDither) {
                        float h = (i + random(IN.uv) - 0.5) / numLayers / _DitherStep;
                        currentDepthMapValue = tex2D(_Height, UVs + h).rg;
                    }
                    else {
                        currentDepthMapValue = tex2D(_Height, UVs).rg;
                    }
                    currentLayerDepth -= layerDepth;

                    // Parallax mapping with 2 height map
                    // The background in the camera direction (R) should be black, and the background in the opposite direction (G) should be white.
                    if (currentLayerDepth < currentDepthMapValue.r && currentLayerDepth > currentDepthMapValue.g) {
                        customColor.rgb = tex2D(_Diffuse, UVs).rgb;
                        isIntersect = true;
                        break;

                        //Dithering
                        // Used to reduce the number of steps. Refer to Unreal City Sample.
                            /*float2 uv = IN.positionV.xy * _ScreenParams.xy;
                            float DITHER_THRESHOLDS[16] =
                            {
                                1.0 / 17.0,  9.0 / 17.0,  3.0 / 17.0, 11.0 / 17.0,
                                13.0 / 17.0,  5.0 / 17.0, 15.0 / 17.0,  7.0 / 17.0,
                                4.0 / 17.0, 12.0 / 17.0,  2.0 / 17.0, 10.0 / 17.0,
                                16.0 / 17.0,  8.0 / 17.0, 14.0 / 17.0,  6.0 / 17.0
                            };
                            uint index = (uint(uv.x) % 4) * 4 + uint(uv.y) % 4;
                            customColor = customColor - DITHER_THRESHOLDS[index];*/

                    }
                }
                if (!_UseCubemap && !isIntersect) {
                    discard;
                }

                //float3 test = abs(dot(IN.normal, -viewDir));
                //customColor = half4(test, 1);

                //depth = 1;//Always Visible
                //float2 _UV = IN.positionV.xy / _ScaledScreenParams.xy;

                //depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(_UV));
                //depth = SampleSceneDepth(_UV);
                //depth = 1;

                return customColor;
            }

            ENDHLSL
        }

        // The following code is for making the shader visible in URP. It is not important.  
        // Source: https://chulin28ho.tistory.com/897
        Pass // Depth Only Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

          // -------------------------------------
          // Render State Commands
          ZWrite On
          ColorMask R

          HLSLPROGRAM
          #pragma vertex DepthOnlyVertex
          #pragma fragment DepthOnlyFragment

          #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
          struct Attributes
          {
              float4 position     : POSITION;
          };

          struct Varyings
          {
              float4 positionCS   : SV_POSITION;
          };

          Varyings DepthOnlyVertex(Attributes input)
          {
              Varyings output = (Varyings)0;
              output.positionCS = TransformObjectToHClip(input.position.xyz);
              return output;
          }

          half DepthOnlyFragment(Varyings input) : SV_TARGET
          {
              return input.positionCS.z;
          }
          ENDHLSL
        }

        Pass //Depth Normal Pass
        {
              Name "DepthNormalsOnly"
              Tags
              {
                  "LightMode" = "DepthNormalsOnly"
              }

              ZWrite On

              HLSLPROGRAM
              #pragma vertex DepthNormalsVertex
              #pragma fragment DepthNormalsFragment
              #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
              #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

              struct Attributes
              {
                  float3 normal       : NORMAL;
                  float4 positionOS   : POSITION;
              };

              struct Varyings
              {
                  float4 positionCS   : SV_POSITION;
                  float3 normalWS     : TEXCOORD1;
              };

              Varyings DepthNormalsVertex(Attributes input)
              {
                  Varyings output = (Varyings)0;
                  output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                  output.normalWS = NormalizeNormalPerVertex(TransformObjectToWorldNormal(input.normal));
                  return output;
              }

              void DepthNormalsFragment(Varyings input, out half4 outNormalWS : SV_Target0
                  #ifdef _WRITE_RENDERING_LAYERS
                  , out float4 outRenderingLayers : SV_Target1
                  #endif
                  )
              {
                  outNormalWS = half4(NormalizeNormalPerPixel(input.normalWS), 0.0);
                  #ifdef _WRITE_RENDERING_LAYERS
                      uint renderingLayers = GetMeshRenderingLayer();
                      outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
                  #endif
              }

              ENDHLSL
        }
    }
}