#ifndef NPR_EFFECT_SOBEL_INCLUDED
#define NPR_EFFECT_SOBEL_INCLUDED

// Sobel edge detection applied as a post-process on the Meta Avatar shader.
// Requires ENABLE_NPR_EDGES + EFFECT_SOBEL keywords.

float  _EnableSobel;      // runtime toggle (1 = on, 0 = off)
float4 _InnerLineColor;
float  _SobelSampleDist;  // UV-space sample offset (0–10, multiplied by 0.001)
float  _SobelThreshold;   // minimum edge magnitude to draw a line
float  _SobelMax;         // magnitudes above this are seam spikes → suppress
float  _SobelSeamLimit;   // if neighbour luma range > this, pixel is on a UV seam
float  _SobelStrength;    // overall edge opacity

float4 ApplyNPREffect(float4 color, float2 uv, half3 worldNormal, half3 worldViewDir)
{
    if (_EnableSobel < 0.5) return color;

    float  offset = _SobelSampleDist * 0.001;
    float3 L      = float3(0.2126, 0.7152, 0.0722);

    float tl = dot(tex2D(u_BaseColorSampler, uv + float2(-offset,  offset)).rgb, L);
    float t  = dot(tex2D(u_BaseColorSampler, uv + float2( 0,       offset)).rgb, L);
    float tr = dot(tex2D(u_BaseColorSampler, uv + float2( offset,  offset)).rgb, L);
    float l  = dot(tex2D(u_BaseColorSampler, uv + float2(-offset,  0     )).rgb, L);
    float r  = dot(tex2D(u_BaseColorSampler, uv + float2( offset,  0     )).rgb, L);
    float bl = dot(tex2D(u_BaseColorSampler, uv + float2(-offset, -offset)).rgb, L);
    float b  = dot(tex2D(u_BaseColorSampler, uv + float2( 0,      -offset)).rgb, L);
    float br = dot(tex2D(u_BaseColorSampler, uv + float2( offset, -offset)).rgb, L);

    float sobelX  = (tr + 2*r + br) - (tl + 2*l + bl);
    float sobelY  = (tl + 2*t + tr) - (bl + 2*b + br);
    float edgeMag = sqrt(sobelX*sobelX + sobelY*sobelY);

    // Suppress UV-seam spikes: if luma spread across neighbours is extreme, hide edge.
    float lMin     = min(min(min(tl,t),min(tr,l)), min(min(r,bl),min(b,br)));
    float lMax     = max(max(max(tl,t),max(tr,l)), max(max(r,bl),max(b,br)));
    float seamMask = step(lMax - lMin, _SobelSeamLimit);

    float inBand = step(_SobelThreshold, edgeMag) * step(edgeMag, _SobelMax);
    float edge   = inBand * seamMask * _SobelStrength;

    color.rgb = lerp(color.rgb, _InnerLineColor.rgb, edge);
    return color;
}

#endif // NPR_EFFECT_SOBEL_INCLUDED
