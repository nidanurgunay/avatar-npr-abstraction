#ifndef AVATAR_NPR_EDGE_EFFECT_INCLUDED
#define AVATAR_NPR_EDGE_EFFECT_INCLUDED

// Screen-space derivative inner-edge detection + toon posterization for Meta Avatars.
// Color and normal channels are fully independent — each has its own threshold, max, and strength.
// Toon posterization quantizes the already-lit color into discrete luminance bands before
// drawing edges, giving a cel-shaded appearance without access to raw lighting components.
// UnityCG.cginc is already included via Style2MetaAvatarCore.hlsl.

float4 _InnerLineColor;
float  _ColorThreshold;
float  _ColorEdgeMax;
float  _ColorStrength;
float  _NormalThreshold;
float  _NormalEdgeMax;
float  _NormalStrength;
float  _ToonBands;    // number of discrete luminance steps (2–8)
float  _ToonStrength; // blend between original PBR and posterized (0=off, 1=full toon)

float4 ApplyNPREdgeEffect(float4 color, float2 uv)
{
    // ── Toon posterization ────────────────────────────────────────────────────
    float lum    = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    float banded = floor(lum * _ToonBands + 0.5) / _ToonBands;
    float scale  = lum > 0.001 ? banded / lum : 1.0;
    color.rgb    = lerp(color.rgb, color.rgb * scale, _ToonStrength);

    // ── Derivative edge detection ─────────────────────────────────────────────
    float3 baseColor = tex2D(u_BaseColorSampler, uv).rgb;
    float2 normalXY  = tex2D(u_NormalSampler,    uv).xy;

    float3 bcDX = ddx(baseColor);
    float3 bcDY = ddy(baseColor);
    float2 nmDX = ddx(normalXY);
    float2 nmDY = ddy(normalXY);

    float colorEdge  = sqrt(dot(bcDX, bcDX) + dot(bcDY, bcDY));
    float normalEdge = sqrt(dot(nmDX, nmDX) + dot(nmDY, nmDY));

    float colorHit  = step(_ColorThreshold,  colorEdge)  * step(colorEdge,  _ColorEdgeMax)  * _ColorStrength;
    float normalHit = step(_NormalThreshold, normalEdge) * step(normalEdge, _NormalEdgeMax) * _NormalStrength;

    float edge = saturate(colorHit + normalHit);
    color.rgb  = lerp(color.rgb, _InnerLineColor.rgb, edge);

    return color;
}

#endif // AVATAR_NPR_EDGE_EFFECT_INCLUDED
