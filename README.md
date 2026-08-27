# Abstraction Mechanisms for Virtual Avatars

Unity source code accompanying the master's thesis *Abstraction Mechanisms for Virtual Avatars*.

**Nidanur Günay**
Department of Computer and Information Science, University of Konstanz, 2026
First reviewer: Prof. Dr. Oliver Deussen · Second reviewer: Prof. Dr. Tiare Feuchtner

---

## Overview

This repository contains the non-photorealistic rendering (NPR) implementations described in Chapters 4 and 5
of the thesis. Eight abstraction techniques were developed and ported across three avatar platforms whose
rendering architectures differ substantially:

| Platform | Character | Rendering architecture |
| --- | --- | --- |
| Mixamo | Jody | Standard URP mesh renderer, painted albedo textures |
| Avaturn | Photographic avatar | glTF import through glTFast, photographic albedo textures |
| Meta Avatars SDK | Meta Avatar | Closed SDK pipeline, single fragment hook, no additional passes |

The Mixamo and Avaturn platforms accept ordinary material shaders and URP renderer features. The Meta Avatars
SDK does not. Its shading runs inside the SDK's own uber shader, so every technique had to be injected through
one per-fragment hook that executes after the SDK's physically based lighting. This constraint drives most of
the architectural differences visible in the table below.

---

## Techniques and source files

Technique numbering follows the thesis. On the Meta Avatars SDK, each technique is a `.cginc` selected by a
shader keyword and dispatched from `Style2MetaAvatarCore.hlsl`.

| Thesis | Technique | Mixamo / Avaturn | Meta Avatars SDK | SDK keyword |
| --- | --- | --- | --- | --- |
| V1 | Geometric silhouette outline | [`V1_ToonShading_GeometryOutline.shader`](Assets/Shaders/JadeNPRShaders/V1_ToonShading_GeometryOutline.shader), [`V1_InvertedHullOutline.shader`](Assets/Shaders/CommonNPRShaders/V1_InvertedHullOutline.shader) | `NPROutline` pass in [`Avatar-Meta-UGB.shader`](Assets/Shaders/MetaAvatarShaders/Avatar-Meta-UGB.shader) | `OUTLINE_PASS` |
| V2 | Toon shading | [`V1_ToonShading_GeometryOutline.shader`](Assets/Shaders/JadeNPRShaders/V1_ToonShading_GeometryOutline.shader) | [`NPREffect_Toon.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_Toon.cginc) | `EFFECT_TOON` |
| V2.2 | X-Toon shading | [`XToon_2DRamp.shader`](Assets/Shaders/JadeNPRShaders/XToon_2DRamp.shader) | [`NPREffect_XToon.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_XToon.cginc) | `EFFECT_XTOON` |
| V3 | Screen-space normal edge detection | [`V2_NormalEdgeDetection.shader`](Assets/Shaders/JadeNPRShaders/V2_NormalEdgeDetection.shader) | [`NPREffect_NormalEdge.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_NormalEdge.cginc) | `EFFECT_NORMAL_EDGE` |
| V4 | Sobel edge detection | [`V3_SobelEdgeDetection.shader`](Assets/Shaders/JadeNPRShaders/V3_SobelEdgeDetection.shader) | [`NPREffect_Sobel.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_Sobel.cginc) | `EFFECT_SOBEL` |
| V4.2 | Gaussian prefiltered Sobel | [`V4_GaussianPreFilteredSobel.shader`](Assets/Shaders/JadeNPRShaders/V4_GaussianPreFilteredSobel.shader) | [`NPREffect_GaussianSobel.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_GaussianSobel.cginc) | `EFFECT_GAUSS_SOBEL` |
| V5 | Hierarchical edge detection, multiple cues | [`HierarchicalEdgeDetection.shader`](Assets/Shaders/JadeNPRShaders/HierarchicalEdgeDetection.shader) + [`EdgeDetectionFeature.cs`](Assets/AvatarShaderExperimental/Scripts/Rendering/EdgeDetectionFeature.cs) | [`NPREffect_Hierarchical.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_Hierarchical.cginc) | `EFFECT_HIERARCHICAL` |
| V6 | Kuwahara painterly filter | [`AnisotropicKuwahara.shader`](Assets/Shaders/JadeNPRShaders/AnisotropicKuwahara.shader) + [`AnisotropicKuwaharaFeature.cs`](Assets/AvatarShaderExperimental/Scripts/Rendering/AnisotropicKuwaharaFeature.cs) | [`NPREffect_Kuwahara2.cginc`](Assets/Shaders/MetaAvatarShaders/NPREffect_Kuwahara2.cginc) | `EFFECT_KUWAHARA` |

Avaturn uses the same technique set under [`Assets/Shaders/AvaturnNPRShaders/`](Assets/Shaders/AvaturnNPRShaders/).
The two platforms diverge mainly in normal-map decoding and in the head texture preprocessing that V4 requires,
both documented in Chapter 5 of the thesis.

### A note on V5

Two files carry hierarchical edge detection for Mixamo and Avaturn, and only one matches the thesis. The
results reported in the thesis were produced by `HierarchicalEdgeDetection.shader`, a URP renderer feature
running as a full-screen post-process. It applies the Roberts Cross operator to the real scene depth, normal
and colour buffers. The similarly named `V5_HierarchicalGaussian.shader` is a later forward material shader
that approximates the same cues with screen-space derivatives, and it is not the implementation Chapter 5
describes. Both are kept here so the historical record is complete.

The Meta Avatars SDK cannot run a post-process pass, so its V5 reconstructs the cues per fragment inside
`NPREffect_Hierarchical.cginc`, with an adaptive gain following the AHEAD approach.

### Additional shaders

`Assets/Shaders/` also holds exploratory variants that were developed but not carried into the thesis, among
them chromatic edge detection, quantised Sobel, halftone and hatching. They are retained for completeness and
are not part of the reported technique set.

---

## Scenes

| Scene | Purpose |
| --- | --- |
| [`Assets/Scenes/metavatars.unity`](Assets/Scenes/metavatars.unity) | Meta Avatars SDK platform scene, in-VR technique switching |
| [`Assets/Scenes/Avaturn.unity`](Assets/Scenes/Avaturn.unity) | Avaturn platform scene |
| [`Assets/Scenes/MixamoJade.unity`](Assets/Scenes/MixamoJade.unity) | Mixamo (Jody) platform scene |
| [`Assets/Avaturn NPR.unity`](Assets/Avaturn%20NPR.unity) | Avaturn with the NPR pipeline applied |
| [`Assets/Scenes/Video Recording.unity`](Assets/Scenes/Video%20Recording.unity) | Stimulus recording setup for the user study, 20° field of view |
| [`Assets/AvatarShaderExperimental/Scenes/Project Scene.unity`](Assets/AvatarShaderExperimental/Scenes/Project%20Scene.unity) | Main Mixamo development scene |
| [`Assets/AvatarShaderExperimental/Scenes/Kuwahara and hieararchical.unity`](Assets/AvatarShaderExperimental/Scenes/Kuwahara%20and%20hieararchical.unity) | V5 and V6 painterly filter tests |

The three platform scenes share a common studio environment so that comparison renders use an equivalent
viewpoint, as described in Chapter 5. The environment textures are third-party Asset Store packages and are
not redistributed here, so the room geometry loads with placeholder materials. See [SETUP.md](SETUP.md).

---

## Runtime tooling

| Script | Function |
| --- | --- |
| [`ShaderSwapper`](Assets/Scripts/ShaderSwapper.cs) | Replaces SDK materials with the NPR shader after the avatar loads asynchronously, and re-applies them when LOD switching reverts them |
| [`NPREdgeDetectionUI`](Assets/Scripts/NPREdgeDetectionUI.cs) | World-space parameter panel with controller raycasting, for live technique switching inside VR |
| [`AvatarFreezeController`](Assets/Scripts/AvatarFreezeController.cs) | Freezes the avatar pose so comparison renders capture an identical configuration |
| [`ScreenshotController`](Assets/Scripts/ScreenshotController.cs) | Captures the comparison figures used in the thesis |

---

## Requirements

- Unity **2022.3.62f3** (LTS)
- Universal Render Pipeline 14.0.12
- Meta Avatars SDK 40.0.1, installed separately (see [SETUP.md](SETUP.md))
- Meta Quest headset for the VR scenes, though the Mixamo and Avaturn scenes run in the Editor

All Unity packages resolve automatically from `Packages/manifest.json` on first open.

---

## Getting started

Clone the repository, open it in Unity 2022.3.62f3, then follow [SETUP.md](SETUP.md) to install the Meta
Avatars SDK and restore the assets that cannot be redistributed. Opening the project before the SDK is
installed produces compile errors in the Meta Avatar shaders, which is expected.

---

## Licence and third-party content

Original code in this repository is released under the MIT Licence, see [LICENSE](LICENSE). Third-party assets,
including the Meta Avatars SDK, the Mixamo character and animations, and the Asset Store environment textures,
remain under their own licences and are documented in [THIRD_PARTY.md](THIRD_PARTY.md).

User study video stimuli, audio recordings and facial capture data are excluded from this repository for data
protection reasons.
