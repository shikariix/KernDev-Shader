Shader "Unlit/unlit"
{
	Properties
	{
		_Color ("Color", Color) = (0.5019608,0.5019608,0.5019608,1)
		_MainTex ("Texture", 2D) = "white" {}
	_NormalMap ("Normal Map", 2D) = "bump" {}
	_NormalMapII ("Normal Map II", 2D) = "bump" {}
	_Transparency ("Transparency", Range (-1, 1)) = 0
	}
		SubShader
	{
		// - vertex and fragment shader

		Tags {
		"RenderType" = "Transparent"
		"Queue" = "Transparent-1"
		"IgnoreProjector" = "True"
	}
		//LOD 100

		
		//alpha
		Blend SrcAlpha OneMinusSrcAlpha

		//This copies the existing destination buffer (what was drawn before) into a global texture called _GrabTexture
		GrabPass {}

		Pass
	{
		Name "FORWARD"
		Tags {
		"LightMode" = "ForwardBase"
	}

		CGPROGRAM
#pragma vertex vert
#pragma fragment frag
#define UNITY_PASS_FORWARDBASE
#define SHOULD_SAMPLE_SH (defined (LIGHTMAP_OFF) && defined (DYNAMICLIGHTMAP_OFF))
#define _GLOSSYENV 1
#pragma multi_compile_fog

#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardBRDF.cginc"

#pragma multi_compile_fwdbase
#pragma multi_compile LIGHTMAP_OFF LIGHTMAP_ON
#pragma multi_compile DIRLIGHTMAP_OFF DIRLIGHTMAP_COMBINED DIRLIGHTMAP_SEPARATE
#pragma multi_compile DYNAMICLIGHTMAP_OFF DYNAMICLIGHTMAP_ON
#pragma multi_compile_fog
#pragma only_renderers d3d9 d3d11 glcore gles n3ds wiiu 
#pragma target 3.0
		uniform sampler2D _GrabTexture;
	uniform float4 _Color;
	uniform sampler2D _BumpMap; uniform float4 _BumpMap_ST;
	uniform sampler2D _snow; uniform float4 _snow_ST;
	uniform sampler2D _NormalMapII; uniform float4 _NormalMapII_ST;
	uniform float _Freezeeffectnormal;
	uniform fixed _LocalGlobal;
	uniform float _Transparency;
	uniform float _Ice_fresnel;


		//input data
		struct VertexInput {
		float4 vertex : POSITION;
		float2 uv : TEXCOORD0;
		float2 texcoord0 : TEXCOORD1;
		float2 texcoord1 : TEXCOORD2;
		float2 texcoord2 : TEXCOORD3;
		float4 color : COLOR;
		float4 tangent : TANGENT;
		float3 normal : NORMAL;
	};

	//output data
	struct VertexOutput {

		float4 vertex : SV_POSITION;
		float2 uv0 : TEXCOORD0;
		float2 uv1 : TEXCOORD1;
		float2 uv2 : TEXCOORD2;
		UNITY_FOG_COORDS (8)

		//custom values
		float3 worldPos : TEXCOORD3; 
		float3 worldNormal : TEXCOORD4; 
		float4 screenPos : TEXCOORD5; 
		float3 worldRefl : TEXCOORD6; 

		float3 objectNormal : TEXCOORD7;
		float3 tangentDir : TEXCOORD8;
		float3 bitangentDir : TEXCOORD9;
		UNITY_FOG_COORDS (8)
	};

	sampler2D _MainTex;
	float4 _MainTex_ST;

	sampler2D _NormalMap;

	uniform float3 _ClipPosition;

	VertexOutput vert (VertexInput v) {
		//this is what you get by default
		VertexOutput o = (VertexOutput)0;
		o.vertex = UnityObjectToClipPos (v.vertex);
		o.uv1 = TRANSFORM_TEX (v.uv, _MainTex);

		//check 
#ifdef LIGHTMAP_ON
		o.ambientOrLightmapUV.xy = v.texcoord1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
		o.ambientOrLightmapUV.zw = 0;
#elif UNITY_SHOULD_SAMPLE_SH
#endif
#ifdef DYNAMICLIGHTMAP_ON
		o.ambientOrLightmapUV.zw = v.texcoord2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif

		UNITY_TRANSFER_FOG (o,o.vertex);

		// unity_ObjectToWorld is our matrix here, v.vertex the object-space vertex position
		o.worldPos = mul (unity_ObjectToWorld, v.vertex);

		//worldNormal
		o.worldNormal = normalize (mul (unity_ObjectToWorld, v.normal));
		o.tangentDir = normalize (mul (unity_ObjectToWorld, float4(v.tangent.xyz, 0.0)).xyz);
		//screenPos
		//This function can be found in the UnityCG.cginc, and calculates a screen position (x,y,z,w) containing pixel position on the screen
		o.screenPos = ComputeGrabScreenPos (o.vertex);

		//worldRefl
		//_WorldSpaceCameraPos contains world camera position (duh) of camera currently rendering this object
		float3 viewDir = normalize (_WorldSpaceCameraPos - o.worldPos);
		//reflect is a cG function that reflects a direction across a surface (which is defined by a surface normal)
		 float3 worldRefl = reflect (-viewDir, o.worldNormal);

		 Unity_GlossyEnvironmentData ugls_en_data;
		 ugls_en_data.reflUVW = worldRefl;

		//pass through object normal without changing it (for normal mapping in pixel shader)
		o.objectNormal = v.normal;

		return o;
	}

	fixed4 frag (VertexOutput i) : SV_Target
	{
		// samples the texture using world XY
		//fixed4 col = tex2D(_MainTex, i.worldPos.xy);

		//NORMAL MAPPING//
		//get normal map texture 
		//The UnpackNormal function expects a texture that was imported as a "Normal Map", otherwise you'll get incorrect results
		float3 norm = UnpackNormal (tex2D (_NormalMap, i.uv1));
		//offset object normal RG with texture RG
		i.objectNormal.rg += norm.rg * .5;
		//translate to world space
		float3 worldNormal = normalize (mul (unity_ObjectToWorld, i.objectNormal));
		//END NORMAL MAPPING//

		//TRIPLANAR MAPPING//
		//get colors for each projection direction (r/g/b)
		fixed4 r = tex2D (_MainTex, i.worldPos.zy);
		fixed4 g = tex2D (_MainTex, i.worldPos.xz);
		fixed4 b = tex2D (_MainTex, i.worldPos.xy);

		//calculate blend amount for each channel
		float3 blend = abs (worldNormal);
		blend *= blend;

		//add them all together based on blend values
		fixed4 col = blend.r * r + blend.g * g + blend.b * b;
		//END TRIPLANAR MAPPING//

		// apply fog
		UNITY_APPLY_FOG (i.fogCoord, col);

		// sample the default reflection cubemap, using the reflection vector
		half4 skyData = UNITY_SAMPLE_TEXCUBE (unity_SpecCube0, i.worldRefl);
		// decode cubemap data into actual color
		half3 skyColor = DecodeHDR (skyData, unity_SpecCube0_HDR);

		//simple example of a "Phong" lighting approximation, comparing world normal with up vector (bottom of object will be unlit, with smooth gradient to top)
		half lightColor = (dot (worldNormal, half3(0,1,0)) + 1) * .5;

		//apply lighting
		col.rgb *= lightColor;
		//add skybox reflection
		col.rgb += skyColor * .5;

		//calculates screenUV from screenPos by removing scaling information (divide by W)
		half2 screenUV = i.screenPos.xy / i.screenPos.w;
		//use screenUV to read pixel behind object from _GrabTexture, we also distort that UV with the normal map RG (offset from default (blue))
		fixed4 grabColor = tex2D (_GrabTexture, screenUV + norm.rg * .01);

		//For fresnel (reflection/translucency) term we need per-pixel view direction, so we calculate it again
		float3 viewDir = normalize (_WorldSpaceCameraPos - i.worldPos);
		float fresnel = 1 - dot (viewDir, worldNormal);

		//output a blend of backbground & sky reflection, based on fresnel, then add a more subtle fresnel as rimlight
		//return half4(lerp (grabColor.rgb, skyColor, fresnel), .5) + pow (fresnel, 3);
		return half4(grabColor.rgb, _Transparency) + pow (fresnel, 1);
	}
		ENDCG
	}
	}
}