# Third-party content

Original shader, script and scene code in this repository is licensed under the MIT Licence (see `LICENSE`).
Third-party material is listed below and remains under its own terms.

---

## Included, under third-party terms

| Content | Location | Source and terms |
| --- | --- | --- |
| Jody character mesh and textures | `Assets/AvatarShaderExperimental/Characters/`, `Assets/AvatarShaderExperimental/Textures/` | [Mixamo](https://www.mixamo.com), Adobe. Free for use in personal and commercial projects under the Mixamo terms of service. |
| Idle and gesture animations | `Assets/Animations/`, `Assets/AvatarShaderExperimental/Animations/` | Mixamo, Adobe. Same terms. |
| Avaturn avatar | `Assets/Avatars/` | Generated with [Avaturn](https://avaturn.me) from a photograph of the author. |
| TextMesh Pro essentials | `Assets/TextMesh Pro/` | Unity Technologies, distributed with Unity. |

---

## Not included, install separately

| Content | Reason | How to obtain |
| --- | --- | --- |
| Meta Avatars SDK 40.0.1 | Redistribution is not permitted under the Oculus SDK Licence Agreement | [Meta Horizon developer downloads](https://developers.meta.com/horizon/downloads/package/meta-avatars-sdk/) |
| Meta Avatars SDK sample scenes and preset avatars | Same | Imported with the SDK package |
| Textures Pack Vol. 1 | Asset Store licence does not permit redistribution | Unity Asset Store |
| Yughues Free Flooring Materials | Same | Unity Asset Store |
| uLipSync | Resolved as a package dependency | [github.com/hecomi/uLipSync](https://github.com/hecomi/uLipSync) |

---

## Excluded for data protection

The following were part of the working project and are deliberately omitted:

- User study video stimuli (`Assets/Recordings/`), which show the author and a real human speaker
- Advisor audio recordings of the author's voice
- ARKit facial capture data (`Assets/FaceData/`), derived from the author's face
- Participant response data, which is reported in aggregate in the thesis only

---

## Algorithms

The techniques implemented here follow published methods. Attribution belongs to the original authors, and the
thesis cites each one at the point where it is introduced.

| Technique | Original work |
| --- | --- |
| Toon shading, real-time bands | Lake et al., 2000 |
| Non-photorealistic lighting model | Gooch et al., 1998 |
| X-Toon 2D ramp abstraction | Barla et al., 2006 |
| Sobel operator, BT.601 luma coefficients | Gonzalez and Woods, 2018 |
| Roberts Cross operator | Roberts, 1963 |
| Gaussian smoothing before differentiation | Marr and Hildreth, 1980; Canny, 1986 |
| Anisotropic Kuwahara filter | Kyprianidis et al., 2009 |
| Silhouette and outline algorithms | Isenberg et al., 2003 |
| Adaptive hierarchical edge detection | Roshaan, 2026 |
