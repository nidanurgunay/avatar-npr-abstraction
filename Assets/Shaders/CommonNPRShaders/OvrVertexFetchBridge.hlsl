// Bridge include: adds Meta Avatar SDK GPU/compute-skinning vertex fetch support
// to any URP shader. Include this AFTER URP Core.hlsl.
//
// Shader target 3.5 is required (add "#pragma target 3.5") for SV_VertexID.
//
// Usage in vertex struct:  uint vertexID : SV_VertexID;
// Usage in vertex body (BEFORE GetVertexPositionInputs):
//   OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID);
//   OVR_FETCH_POS(v.vertex.xyz, v.vertexID);   // depth / shadow passes
//
// Both macros handle ALL skinning modes at runtime by reading _OvrVertexFetchMode
// (set per-renderer via MaterialPropertyBlock by the Avatar SDK):
//   0 = Unity / VertexBuffer  -> no-op, mesh already has correct positions
//   1 = Compute Skinning      -> reads from _OvrPositionBuffer / _OvrFrenetBuffer
//   2 = GPU Skinning          -> reads from u_AttributeTexture (3D texture)
//
// When u_IsExternalAttributeSourceValid == 0 (SDK not yet ready) both macros
// are safe no-ops, leaving the bind-pose position in place.

#ifndef OVR_VERTEX_FETCH_BRIDGE_INCLUDED
#define OVR_VERTEX_FETCH_BRIDGE_INCLUDED

// OvrAvatarSupportDefines.hlsl defines OVR_SUPPORT_EXTERNAL_BUFFERS on all
// Quest/Vulkan/GLES3/D3D11/Metal targets when shader target >= 3.5.
#include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarSupportDefines.hlsl"
// OvrAvatarVertexFetch.hlsl declares the buffers (ByteAddressBuffer _OvrPositionBuffer,
// _OvrFrenetBuffer) and texture (sampler3D u_AttributeTexture) plus the helper functions.
#include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarVertexFetch.hlsl"
// OvrAvatarCommonVertexParams.hlsl declares the uniforms read at runtime:
//   int  _OvrVertexFetchMode, _OvrNumOutputEntriesPerAttribute,
//        _OvrAttributeOutputLatestAnimFrameEntryOffset
//   bool _OvrHasTangents, _OvrInterpolateAttributes
//   float _OvrAttributeInterpolationValue
//   int   u_IsExternalAttributeSourceValid
#include "Packages/com.meta.xr.sdk.avatars/Scripts/ShaderUtils/OvrAvatarCommonVertexParams.hlsl"

#if defined(OVR_SUPPORT_EXTERNAL_BUFFERS)

// OVR_FETCH_POS_NORM — overwrites posOS (float3) and normOS (float3) with the
// GPU-skinned object-space position and normal for the given vertex ID.
#define OVR_FETCH_POS_NORM(posOS, normOS, vid)                                                    \
{                                                                                                  \
    if (u_IsExternalAttributeSourceValid != 0) {                                                   \
        if (_OvrVertexFetchMode == OVR_VERTEX_FETCH_MODE_EXTERNAL_BUFFERS) {                       \
            uint _ovrIdx = (uint)(vid) * (uint)_OvrNumOutputEntriesPerAttribute                    \
                         + (uint)_OvrAttributeOutputLatestAnimFrameEntryOffset;                    \
            posOS  = OvrGetPositionEntryFromExternalBuffer(_ovrIdx);                               \
            normOS = OvrGetFrenetEntryFromExternalBuffer(_ovrIdx).xyz;                             \
        } else if (_OvrVertexFetchMode == OVR_VERTEX_FETCH_MODE_EXTERNAL_TEXTURES) {              \
            int _ovrNumAttr = _OvrHasTangents ? 3 : 2;                                            \
            posOS  = OvrGetVertexPositionFromTexture((uint)(vid), _ovrNumAttr, true,               \
                         _OvrAttributeInterpolationValue).xyz;                                     \
            normOS = OvrGetVertexNormalFromTexture((uint)(vid), _ovrNumAttr, true,                 \
                         _OvrAttributeInterpolationValue).xyz;                                     \
        }                                                                                          \
    }                                                                                              \
}

// OVR_FETCH_POS — position-only variant for depth / shadow passes.
#define OVR_FETCH_POS(posOS, vid)                                                                  \
{                                                                                                  \
    if (u_IsExternalAttributeSourceValid != 0) {                                                   \
        if (_OvrVertexFetchMode == OVR_VERTEX_FETCH_MODE_EXTERNAL_BUFFERS) {                       \
            uint _ovrIdx = (uint)(vid) * (uint)_OvrNumOutputEntriesPerAttribute                    \
                         + (uint)_OvrAttributeOutputLatestAnimFrameEntryOffset;                    \
            posOS  = OvrGetPositionEntryFromExternalBuffer(_ovrIdx);                               \
        } else if (_OvrVertexFetchMode == OVR_VERTEX_FETCH_MODE_EXTERNAL_TEXTURES) {              \
            int _ovrNumAttr = _OvrHasTangents ? 3 : 2;                                            \
            posOS  = OvrGetVertexPositionFromTexture((uint)(vid), _ovrNumAttr, true,               \
                         _OvrAttributeInterpolationValue).xyz;                                     \
        }                                                                                          \
    }                                                                                              \
}

#else
    // Platform does not support external buffers (shader target < 3.5 or unsupported API).
    // Both macros become safe no-ops: Unity skinning still works via SkinnedMeshRenderer.
    #define OVR_FETCH_POS_NORM(posOS, normOS, vid)
    #define OVR_FETCH_POS(posOS, vid)
#endif

#endif // OVR_VERTEX_FETCH_BRIDGE_INCLUDED
