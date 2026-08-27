#ifndef NPR_EFFECT_NORMAL_EDGE_INCLUDED
#define NPR_EFFECT_NORMAL_EDGE_INCLUDED

// World-space normal discontinuity + Fresnel silhouette edge detection.
// Uses ddx/ddy on the interpolated world normal — no extra texture samples needed.
// Ported from V2_NormalEdgeDetection.shader (NormalEdge + FresnelEdge sections).
// Requires ENABLE_NPR_EDGES + EFFECT_NORMAL_EDGE keywords.

float4 _InnerLineColor;
float  _NormalEdgeThreshold;   // centre of the smoothstep band for normal edges
float  _NormalEdgeStrength;    // weight of the normal edge contribution
float  _NormalEdgeSmoothness;  // half-width of the smoothstep band
float  _FresnelEdgeThreshold;  // glancing angle at which silhouette edge starts
float  _FresnelEdgeStrength;   // weight of the Fresnel edge contribution

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    // Normal edge: detect where the world normal changes rapidly across screen pixels.
    float3 dNdx = ddx((float3)worldNormal);
    float3 dNdy = ddy((float3)worldNormal);
    float  normalEdge = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));
    float  nMin = _NormalEdgeThreshold - _NormalEdgeSmoothness;
    float  nMax = _NormalEdgeThreshold + _NormalEdgeSmoothness;
    normalEdge = smoothstep(nMin, nMax, normalEdge) * _NormalEdgeStrength;

    // Fresnel silhouette: highlight glancing-angle surfaces.
    float NdotV   = saturate(dot(normalize((float3)worldNormal), normalize((float3)worldViewDir)));
    float fresnel = 1.0 - NdotV;
    fresnel = smoothstep(_FresnelEdgeThreshold - 0.1, _FresnelEdgeThreshold,       fresnel)
            * smoothstep(_FresnelEdgeThreshold + 0.3, _FresnelEdgeThreshold, fresnel);
    fresnel *= _FresnelEdgeStrength;

    float totalEdge = saturate(normalEdge + fresnel);
    color.rgb = lerp(color.rgb, _InnerLineColor.rgb, totalEdge);
    return color;
}

#endif // NPR_EFFECT_NORMAL_EDGE_INCLUDED
