# Avatar Shader Experimental Import

Imported from:

`/Users/nidanurgunay/Avatar_Shader_Experiemntal`

This folder keeps the experimental avatar shader project isolated from the current
Meta/Avaturn thesis project. The original `.meta` files were preserved so copied
scenes can continue resolving their local materials, shaders, textures, FBX
character, and animations by GUID.

Copied scene entry point:

`Assets/Scenes/AvatarShaderExperimental_ProjectScene.unity`

Full imported scenes are also under:

`Assets/AvatarShaderExperimental/Scenes/`

Compatibility notes:

- The source project was Unity 6 / URP 17. This project is Unity 2022 / URP 14.
- Duplicate TextMesh Pro assets were not copied; the existing project TextMesh Pro
  assets have the same GUIDs and satisfy those references.
- XR Interaction Toolkit sample assets were not copied to avoid pulling Unity 6
  sample scripts into this project. Some XR rig/sample references may appear as
  missing in the imported scene, but the avatar shader materials and local assets
  are present.
- `Scripts/NewMonoBehaviourScript.cs` was simplified to remove the XR Interaction
  Toolkit dependency while keeping the same component GUID and class name.
- `Scripts/Rendering/ToonOutlineRendererFeature.cs` keeps its Unity 6 RenderGraph
  path behind `UNITY_6000_0_OR_NEWER` and uses the legacy URP path in Unity 2022.

