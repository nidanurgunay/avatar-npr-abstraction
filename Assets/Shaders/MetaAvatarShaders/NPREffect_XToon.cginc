#ifndef NPR_EFFECT_XTOON_INCLUDED
#define NPR_EFFECT_XTOON_INCLUDED

// X-Toon Extended Toon Shader — Meta Avatar SDK adaptation
// Based on Barla, Thollot & Markosian "X-Toon: An Extended Toon Shader" (NPAR 2006).
//
// Matches the Jade (NPR/XToon_2DRamp_Jade) and Avaturn (NPR/XToon_2DRamp)
// implementations exactly:
//   - Real world-space depth via _WorldSpaceCameraPos - positionWS
//   - Shadow-attenuated NdotL and specular via GetMainLight(shadowCoord)
//   - LightingStrength blends from textureColor (toon base), not original PBR
//   - Curvature formula: t*(1-bias)+bias (matches Jade/Avaturn)
//   - Normal smoothing (geometric path)
//   - Inner Sobel edges using u_BaseColorSampler

#ifndef UNITY_PIPELINE_URP
    #define _MainLightPosition _WorldSpaceLightPos0
#endif

sampler2D _XToonRamp;

float  _XToonLightSensitivity;
float  _XToonRampSmoothing;
float4 _XToonShadowColor;
float  _XToonShadowStrength;
float  _XToonDetailBias;
float  _XToonDepthNear;
float  _XToonDepthFar;
float  _XToonManualDetail;
float4 _XToonSpecularColor;
float  _XToonSpecularSize;
float  _XToonSpecularSmoothness;
float  _XToonSpecularStrength;
float  _XToonLightingStrength;
float  _XToonEnableRim;
float4 _XToonRimColor;
float  _XToonRimPower;            // declared for UI parity; not used in formula
float  _XToonRimThreshold;
float  _XToonRimStrength;
float  _XToonNormalSmoothing;     // matches Jade/Avaturn _NormalSmoothing
float  _XToonEnableSobel;         // matches Jade/Avaturn _EnableSobel
float4 _XToonSobelEdgeColor;
float  _XToonSobelThreshold;
float  _XToonSobelSampleDist;
float  _XToonSobelStrength;

// Compute the V coordinate (abstraction level) of the 2D ramp.
// Detail axis mode is selected via _DETAILMODE_* keywords (set at runtime by AddKeywordCycleRow in VR UI).
float _XToonComputeDetailAxis(float3 positionWS, float3 normalWS)
{
    #if defined(_DETAILMODE_CURVATURE)
        float3 dNdx = ddx(normalWS);
        float3 dNdy = ddy(normalWS);
        float curvature = length(dNdx) + length(dNdy);
        float t = 1.0 - saturate(curvature * 10.0);
        return t * (1.0 - _XToonDetailBias) + _XToonDetailBias;
    #elif defined(_DETAILMODE_MANUAL)
        return saturate(_XToonManualDetail);
    #else // _DETAILMODE_DEPTH (default)
        float depth = length(_WorldSpaceCameraPos - positionWS);
        float t = saturate((depth - _XToonDepthNear) / max(0.001, _XToonDepthFar - _XToonDepthNear));
        return saturate(t + _XToonDetailBias);
    #endif
}

// 5-parameter signature: positionWS is required for correct depth and shadow.
// app_functions.hlsl passes i.geometry.positionInWorldSpace when EFFECT_XTOON is active.
float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir, float3 positionWS)
{
    float3 normalWS = normalize((float3)worldNormal);
    float3 viewDir  = normalize((float3)worldViewDir);

    // --- Normal smoothing (matches Jade/Avaturn geometric smoothing path) ---
    if (_XToonNormalSmoothing > 0.001)
    {
        float3 smoothN = normalize(
            normalWS + _XToonNormalSmoothing * (normalize(positionWS) - normalWS));
        normalWS = normalize(lerp(normalWS, smoothN, _XToonNormalSmoothing * 0.5));
    }

    // --- Lighting with shadow attenuation (matches Jade/Avaturn NdotL *= shadow) ---
    float shadow = 1.0;
    float3 lightDir;
    #ifdef UNITY_PIPELINE_URP
        #if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
            float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
            Light mainLight    = GetMainLight(shadowCoord);
        #else
            Light mainLight = GetMainLight();
        #endif
        lightDir = normalize(mainLight.direction);
        shadow   = mainLight.shadowAttenuation;
    #else
        lightDir = normalize(_MainLightPosition.xyz);
    #endif

    float NdotL = dot(normalWS, lightDir);
    NdotL = NdotL * shadow;  // shadow-attenuated, matches Jade/Avaturn exactly

    // Lerp toward 0.5 (ramp center) to reduce light sensitivity — matches Jade/Avaturn
    float rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _XToonLightSensitivity);

    // --- V axis: abstraction level (uses real world depth now) ---
    float rampV = saturate(_XToonComputeDetailAxis(positionWS, normalWS));

    // --- Sample 2D toon ramp ---
    float3 rampColor = tex2D(_XToonRamp, float2(rampU, rampV)).rgb;

    // --- Shadow mask + toon color (matches Jade/Avaturn exactly) ---
    float abstractU    = lerp(rampU, 0.5, rampV * 0.6);
    float dynSmoothing = lerp(_XToonRampSmoothing, _XToonRampSmoothing + 0.35, rampV);
    float shadowMask   = smoothstep(0.5 - dynSmoothing, 0.5 + dynSmoothing, abstractU);

    float3 toonColor     = color.rgb * rampColor;
    float3 shadowedColor = lerp(toonColor * _XToonShadowColor.rgb, toonColor, shadowMask);
    float3 finalColor    = lerp(color.rgb, shadowedColor, _XToonShadowStrength);

    // Save textureColor here — matches Jade/Avaturn where LightingStrength blends
    // from the toon base (not the original PBR), so strength=0 shows the shadow-tinted
    // toon result rather than the raw SDK PBR output.
    float3 textureColor = finalColor;

    // --- Stylised specular — shadow-attenuated, matches Jade/Avaturn ---
    float3 halfDir = normalize(lightDir + viewDir);
    float NdotH    = dot(normalWS, halfDir);
    float specular = smoothstep(1.0 - _XToonSpecularSize - _XToonSpecularSmoothness,
                                1.0 - _XToonSpecularSize + _XToonSpecularSmoothness,
                                NdotH) * shadow;
    finalColor = lerp(finalColor, _XToonSpecularColor.rgb, specular * _XToonSpecularStrength);

    // --- Rim light (matches Jade/Avaturn _EnableRimLight block exactly) ---
    if (_XToonEnableRim > 0.5)
    {
        float NdotV = dot(normalWS, viewDir);
        float rim   = 1.0 - saturate(NdotV);
        rim = smoothstep(_XToonRimThreshold - 0.01, _XToonRimThreshold + 0.01,
                         rim * pow(saturate(NdotL + 0.5), 0.2));
        finalColor = lerp(finalColor, _XToonRimColor.rgb, rim * _XToonRimStrength);
    }

    // --- LightingStrength blend from textureColor (matches Jade/Avaturn) ---
    // Jade: lerp(textureColor, finalColor, _LightingStrength)
    finalColor = lerp(textureColor, finalColor, _XToonLightingStrength);

    // --- Inner Sobel edges on base texture (matches Jade/Avaturn _EnableSobel block) ---
    // Uses u_BaseColorSampler (SDK base color, already in scope from Style2MetaAvatarCore.hlsl)
    if (_XToonEnableSobel > 0.5)
    {
        float off = _XToonSobelSampleDist * 0.001;
        float3 lumaCoeff = float3(0.299, 0.587, 0.114);
        float tl = dot(tex2D(u_BaseColorSampler, uv + float2(-off,  off)).rgb, lumaCoeff);
        float t  = dot(tex2D(u_BaseColorSampler, uv + float2(   0,  off)).rgb, lumaCoeff);
        float tr = dot(tex2D(u_BaseColorSampler, uv + float2( off,  off)).rgb, lumaCoeff);
        float l  = dot(tex2D(u_BaseColorSampler, uv + float2(-off,    0)).rgb, lumaCoeff);
        float r  = dot(tex2D(u_BaseColorSampler, uv + float2( off,    0)).rgb, lumaCoeff);
        float bl = dot(tex2D(u_BaseColorSampler, uv + float2(-off, -off)).rgb, lumaCoeff);
        float b  = dot(tex2D(u_BaseColorSampler, uv + float2(   0, -off)).rgb, lumaCoeff);
        float br = dot(tex2D(u_BaseColorSampler, uv + float2( off, -off)).rgb, lumaCoeff);
        float sobelX  = (tr + 2.0*r + br) - (tl + 2.0*l + bl);
        float sobelY  = (tl + 2.0*t + tr) - (bl + 2.0*b + br);
        float edgeMag = sqrt(sobelX*sobelX + sobelY*sobelY);
        float edge    = step(_XToonSobelThreshold, edgeMag) * _XToonSobelStrength;
        finalColor = lerp(finalColor, _XToonSobelEdgeColor.rgb, edge);
    }

    return float4(finalColor, color.a);
}

#endif // NPR_EFFECT_XTOON_INCLUDED
