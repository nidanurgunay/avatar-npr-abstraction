// App-specific hook implementations for Cel-Avatar-NPR-Sobel.
// These functions are called by Style2MetaAvatarCel.hlsl via forward declarations
// at lines 817-819 / 929 of that file.
//
// Toggle keyword: ENABLE_NPR_EDGES
// Declared here so #include_with_pragmas picks it up into every pass that
// includes this file (same pattern as Unity-UltimateGloveBall).

#pragma multi_compile __ ENABLE_NPR_EDGES

void AppSpecificVertexPostManipulation(AvatarVertexInput i, inout VertexToFragment o) {}

void AppSpecificPreManipulation(inout avatar_FragmentInput i) {}

void AppSpecificFragmentComponentManipulation(
    avatar_FragmentInput i,
    inout float3 punctualSpecular,
    inout float3 punctualDiffuse,
    inout float3 ambientSpecular,
    inout float3 ambientDiffuse) {}

void AppSpecificPostManipulation(avatar_FragmentInput i, inout avatar_FragmentOutput o)
{
    // DIAGNOSTIC A: solid green override proves AppSpecificPostManipulation runs.
    // DIAGNOSTIC B: solid red proves ENABLE_NPR_EDGES keyword is set.
    // Remove both once edge detection is confirmed working.
    o.color.rgb = float3(0, 1, 0);
#if defined(ENABLE_NPR_EDGES)
    o.color.rgb = float3(1, 0, 0);

    float2 uv = i.geometry.texcoord_0;

    float3 baseColor = tex2D(u_BaseColorSampler, uv).rgb;
    float2 normalXY  = tex2D(u_NormalSampler,    uv).xy;

    float3 bcDX = ddx(baseColor);
    float3 bcDY = ddy(baseColor);
    float2 nmDX = ddx(normalXY);
    float2 nmDY = ddy(normalXY);

    float colorEdge  = sqrt(dot(bcDX, bcDX) + dot(bcDY, bcDY));
    float normalEdge = sqrt(dot(nmDX, nmDX) + dot(nmDY, nmDY));

    float edgeMag = _ColorEdgeWeight * colorEdge + (1.0 - _ColorEdgeWeight) * normalEdge;

    float inBand = step(_EdgeThreshold, edgeMag) * step(edgeMag, _EdgeMax);
    o.color.rgb  = lerp(o.color.rgb, _InnerLineColor.rgb, inBand * _InnerLineStrength);
#endif
}
