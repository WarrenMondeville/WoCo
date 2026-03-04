Shader "LowPolyWater/WaterShaded" {
Properties { 

	_BaseColor ("Base color", COLOR)  = ( .54, .95, .99, 0.5) 
	_SpecColor ("Specular Material Color", Color) = (1,1,1,1) 
    _Shininess ("Shininess", Float) = 10
	_ShoreTex ("Shore & Foam texture ", 2D) = "black" {} 
	 
	_InvFadeParemeter ("Auto blend parameter (Edge, Shore, Distance scale)", Vector) = (0.2 ,0.39, 0.5, 1.0)

	_BumpTiling ("Foam Tiling", Vector) = (1.0 ,1.0, -2.0, 3.0)
	_BumpDirection ("Foam movement", Vector) = (1.0 ,1.0, -1.0, 1.0) 

	_Foam ("Foam (intensity, cutoff)", Vector) = (0.1, 0.375, 0.0, 0.0) 
	[MaterialToggle] _isInnerAlphaBlendOrColor("Fade inner to color or alpha?", Float) = 0 
}


Subshader
{
	Tags {
		"RenderType"="Transparent"
		"Queue"="Transparent"
		"RenderPipeline"="UniversalPipeline"
	}
	
	Lod 500
	ColorMask RGB
	
	Pass {
		Blend SrcAlpha OneMinusSrcAlpha
		ZTest LEqual
		ZWrite Off
		Cull Off
	
		HLSLPROGRAM
		
		#pragma target 3.0
		
		#pragma vertex vert
		#pragma fragment frag
		
		#pragma multi_compile WATER_EDGEBLEND_ON WATER_EDGEBLEND_OFF 
		
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
		#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
		
		TEXTURE2D(_ShoreTex);
		SAMPLER(sampler_ShoreTex);
		
		CBUFFER_START(UnityPerMaterial)
			float4 _BaseColor;  
			float _Shininess;
			float4 _InvFadeParemeter;
			float4 _BumpTiling;
			float4 _BumpDirection;
			float4 _Foam; 
			float _isInnerAlphaBlendOrColor;
			float4 _SpecColor;
		CBUFFER_END

		struct Attributes
		{
			float4 vertex : POSITION;
			float3 normal : NORMAL;
		};
 
		struct Varyings
		{
			float4 pos : SV_POSITION;
			float4 normalInterpolator : TEXCOORD0;
			float4 viewInterpolator : TEXCOORD1;
			float4 bumpCoords : TEXCOORD2;
			float waterDepth : TEXCOORD3;
			half3 worldRefl : TEXCOORD6;
			float4 posWorld : TEXCOORD7;
			float3 normalDir : TEXCOORD8;
		}; 

		// 将深度缓冲值转换为线性视图空间深度
		real LinearEyeDepthURP(real rawDepth, float4 zBufferParam)
		{
			return 1.0 / (rawDepth * zBufferParam.z + zBufferParam.w);
		}

		inline half4 Foam(TEXTURE2D_PARAM(shoreTex, sampler_shoreTex), half4 coords) 
		{
			half4 foam = (SAMPLE_TEXTURE2D(shoreTex, sampler_shoreTex, coords.xy) * SAMPLE_TEXTURE2D(shoreTex, sampler_shoreTex, coords.zw)) - 0.125;
			return foam;
		}

		half4 CalculateBaseColor(Varyings input)  
		{
			float3 normalDirection = normalize(input.normalDir);
			float3 viewDirection = normalize(_WorldSpaceCameraPos - input.posWorld.xyz);
			
			// URP 光照
			Light mainLight = GetMainLight();
			float3 lightDirection = mainLight.direction;
			float attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
			
			// 环境光 (URP 默认环境色)
			half3 ambientLighting = half3(0.212h, 0.227h, 0.259h) * _BaseColor.rgb;
			
			// 漫反射
			float3 diffuseReflection = attenuation * mainLight.color * _BaseColor.rgb
				* max(0.0, dot(normalDirection, lightDirection));
			
			// 高光
			float3 specularReflection;
			if (dot(normalDirection, lightDirection) < 0.0) 
			{
				specularReflection = float3(0.0, 0.0, 0.0); 
			}
			else  
			{
				specularReflection = attenuation * mainLight.color * _SpecColor.rgb 
					* pow(max(0.0, dot(reflect(-lightDirection, normalDirection), viewDirection)), _Shininess);
			}

			return half4(ambientLighting + diffuseReflection + specularReflection, 1.0);
		}

		Varyings vert(Attributes v)
		{
			Varyings o;
			ZERO_INITIALIZE(Varyings, o);

			VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
			VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal);
			
			half3 worldSpaceVertex = vertexInput.positionWS;

			half3 offsets = half3(0,0,0);
			half3 nrml = half3(0,1,0);
			
			half2 tileableUv = worldSpaceVertex.xz;
			o.bumpCoords.xyzw = (tileableUv.xyxy + _Time.xxxx * _BumpDirection.xyzw) * _BumpTiling.xyzw;

			o.viewInterpolator.xyz = worldSpaceVertex - _WorldSpaceCameraPos;
			o.pos = vertexInput.positionCS;
			o.normalInterpolator.xyz = nrml;
			o.viewInterpolator.w = saturate(offsets.y);
			o.normalInterpolator.w = 1; 
			
			// 水体表面在视图空间的深度 (线性)
			o.waterDepth = -vertexInput.positionVS.z;
			
			o.posWorld = float4(worldSpaceVertex, 1);
			o.normalDir = normalInput.normalWS;
			
			float3 worldViewDir = normalize(_WorldSpaceCameraPos.xyz - worldSpaceVertex); 
			o.worldRefl = reflect(-worldViewDir, normalInput.normalWS);

			return o;
		}

		half4 frag(Varyings i) : SV_Target
		{ 
			half4 edgeBlendFactors = half4(1.0, 0.0, 0.0, 0.0);
			
			#ifdef WATER_EDGEBLEND_ON
				float2 screenUV = i.pos.xy / _ScaledScreenParams.xy;
				real rawDepth = SampleSceneDepth(screenUV);
				real sceneDepth = LinearEyeDepthURP(rawDepth, _ZBufferParams);
				real waterDepth = i.waterDepth;
				edgeBlendFactors = saturate(_InvFadeParemeter * (sceneDepth - waterDepth));
				edgeBlendFactors.y = 1.0 - edgeBlendFactors.y;
			#endif
			
			half4 baseColor = CalculateBaseColor(i);
			
			half4 foam = Foam(TEXTURE2D_ARGS(_ShoreTex, sampler_ShoreTex), i.bumpCoords * 2.0);
			baseColor.rgb += foam.rgb * _Foam.x * (edgeBlendFactors.y + saturate(i.viewInterpolator.w - _Foam.y));
			
			if (_isInnerAlphaBlendOrColor == 0)
				baseColor.rgb += 1.0 - edgeBlendFactors.x;
			if (_isInnerAlphaBlendOrColor == 1.0)
				baseColor.a = edgeBlendFactors.x;
			
			return baseColor;
		}
		
		ENDHLSL
	}
}

Fallback "Universal Render Pipeline/Unlit"
}
