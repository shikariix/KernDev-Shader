Shader "Unlit/unlit"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	_NormalMap ("Normal Map", 2D) = "blue" {}
	}
		SubShader
	{
		Tags {
		"RenderType" = "Transparent"
		"Queue" = "Transparent-1"
	}
		LOD 100

		//Various blend modes and how to set them up
		//alpha
		Blend SrcAlpha OneMinusSrcAlpha		//IMPORTANT: render order heavily influences correct results (needs to be back to front)

		//additive
		//Blend One One

		//multiply blend
		//Blend DstColor SrcColor

		//you can influence the type of "depth test", which compares the current pixel depth with previously written pixels
		// default is LEqual, meaning "if depth is less or equal to existing, then this pixel will pass its test and be drawn"
		//ZTest Always	//always means -> always draw, good for UI and overlay graphics (because you'll see them even if they're behind something else)
		

		//This copies the existing destination buffer (what was drawn before) into a global texture called _GrabTexture
		GrabPass {}

		Pass
	{
		CGPROGRAM
#pragma vertex vert
#pragma fragment frag
		// make fog work
#pragma multi_compile_fog

#include "UnityCG.cginc"

		//this struct gets model data (per vertex) from the channels (semantics) you see after :
		struct appdata {
		float4 vertex : POSITION;
		float2 uv : TEXCOORD0;
		float4 color : COLOR;
		float3 normal : NORMAL;
	};

	//Here we use another struct to select channels to send data to the pixel shader
	//All of these values will be rasterized & interpolated to become per-pixel data
	struct v2f {

		float2 uv : TEXCOORD0;
		UNITY_FOG_COORDS (1)
			float4 vertex : SV_POSITION;

		//custom values
		float3 worldPos : TEXCOORD1; 
		float3 worldNormal : TEXCOORD2; 
		float4 screenPos : TEXCOORD3; 
		float3 worldRefl : TEXCOORD4; 

		//need object normal for (my version of) normal mapping
		float3 objectNormal : TEXCOORD5;
	};

	sampler2D _MainTex;
	float4 _MainTex_ST;

	sampler2D _NormalMap;
	uniform half _Alpha;

	uniform float3 _ClipPosition;
	uniform sampler2D _GrabTexture;

	v2f vert (appdata v) {
		//this is what you get by default
		v2f o;
		o.vertex = UnityObjectToClipPos (v.vertex);
		o.uv = TRANSFORM_TEX (v.uv, _MainTex);
		UNITY_TRANSFER_FOG (o,o.vertex);

		//worldPos, mul is a cG function that takes a Matrix and a Position, and outputs a transform Position
		// unity_ObjectToWorld is our matrix here, v.vertex the object-space vertex position
		o.worldPos = mul (unity_ObjectToWorld, v.vertex);

		//worldNormal
		//Again we mul the matrix, but this time with the vertex normal. To remove stretching due to object scale, we normalize the output.
		o.worldNormal = normalize (mul (unity_ObjectToWorld, v.normal));

		//screenPos
		//This function can be found in the UnityCG.cginc, and calculates a screen position (x,y,z,w) containing pixel position on the screen
		o.screenPos = ComputeGrabScreenPos (o.vertex);

		//worldRefl
		//_WorldSpaceCameraPos contains world camera position (duh) of camera currently rendering this object
		float3 viewDir = normalize (_WorldSpaceCameraPos - o.worldPos);
		//reflect is a cG function that reflects a direction across a surface (which is defined by a surface normal)
		o.worldRefl = reflect (-viewDir, o.worldNormal);


		//pass through object normal without changing it (for normal mapping in pixel shader)
		o.objectNormal = v.normal;

		return o;
	}

	fixed4 frag (v2f i) : SV_Target
	{
		// samples the texture using world XY
		//fixed4 col = tex2D(_MainTex, i.worldPos.xy);

		//NORMAL MAPPING//
		//get normal map texture 
		//The UnpackNormal function expects a texture that was imported as a "Normal Map", otherwise you'll get incorrect results
		float3 norm = UnpackNormal (tex2D (_NormalMap, i.uv));
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
		//1 - dot(A,B) means front of object is 0 (directions are opposite), and edge of object is 1
		float fresnel = 1 - dot (viewDir, worldNormal);

		//output a blend of backbground & sky reflection, based on fresnel, then add a more subtle fresnel as rimlight
		//return half4(lerp (grabColor.rgb, skyColor, fresnel), .5) + pow (fresnel, 3);
		return half4(grabColor.rgb, _Alpha + 1) + pow (fresnel, 1);
		//return half4(grabColor.rgb, .5) + pow (fresnel, 2);
	}
		ENDCG
	}
	}
}