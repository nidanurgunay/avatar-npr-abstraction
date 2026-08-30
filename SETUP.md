# Setup

Steps required after cloning, before the scenes render as they do in the thesis.

---

## 1. Unity version

Open the project with **Unity 2022.3.62f3 (LTS)**. Other 2022.3 patch releases will normally work, but the
project was authored and last verified on this version. Unity resolves the packages listed in
`Packages/manifest.json` on first open, which takes several minutes.

---

## 2. Meta Avatars SDK

The SDK is not redistributed here. Install it before opening the `metavatars` scene.

1. Download the Meta Avatars SDK **v40.0.1** from the
   [Meta Horizon developer downloads](https://developers.meta.com/horizon/downloads/package/meta-avatars-sdk/).
2. Add it through the Unity Package Manager as `com.meta.xr.sdk.avatars`, version 40.0.1. The entry is already
   present in `Packages/manifest.json`, so the Package Manager may resolve it automatically once the registry
   or tarball is available.
3. **Import the SDK samples.** In the Package Manager, select the Meta Avatars SDK package, open the *Samples*
   tab and import *Sample Scenes* and *Sample Assets*. This step is mandatory, not optional, and the reason is
   given below.

### The sample import is required by the metavatars scene

`Assets/Scenes/metavatars.unity` references five objects that live in the SDK sample import rather than in
this repository:

| Reference | Role in the scene |
| --- | --- |
| `AvatarSdkManagerStyle2Meta.prefab` | Spawns and manages the avatar |
| `SampleAvatarEntity.cs` | Avatar entity component |
| `SampleSceneLocomotion.cs` | Camera and rig movement |
| `AvatarsSDKUI.prefab` | SDK debug interface |
| `LipSyncInput.prefab` | Audio-driven mouth movement |

Unity resolves these by GUID, and the samples import to a version-pinned path,
`Assets/Samples/Meta Avatars SDK/40.0.1/`. Importing the samples for **exactly version 40.0.1** restores the
same GUIDs and the scene relinks by itself. Installing a different SDK version writes a different folder, and
the scene will open with missing references that have to be reassigned by hand.

One SDK sample script was extended for this project. `AvatarSwitcher.cs` calls `SwitchPreset` on
`SampleAvatarEntity`, a method that the stock sample does not define, and the project does not compile without
it. After importing the samples, apply the patch:

```
patch -p1 < patches/SampleAvatarEntity_SwitchPreset.patch
```

That is the only sample file this project changes, so re-importing overwrites nothing else. The patch contains
only the added method, not Meta's own code.

Until the SDK is present, `Assets/Shaders/MetaAvatarShaders/` will not compile, because
`Style2MetaAvatarCore.hlsl` includes headers from `Packages/com.meta.xr.sdk.avatars/`. A compilation failure in
Unity is project wide rather than confined to one scene, meaning that the Mixamo and Avaturn scenes will not
run either until the SDK, its samples and the patch are all in place.

### Shader integration hook

The NPR techniques enter the SDK pipeline through `AppSpecificPostManipulation`, a per-fragment function that
runs after the SDK's physically based lighting. The three files under
`Assets/Shaders/MetaAvatarShaders/app_specific/` provide it:

| File | Role |
| --- | --- |
| `app_declarations.hlsl` | Forward declarations the SDK core expects |
| `app_functions.hlsl` | Keyword dispatch and the post-manipulation hook itself |
| `app_variants.hlsl` | Shader variant definitions |

These are the only integration point that leaves SDK skinning, LOD handling and material management intact.
If a future SDK version ships its own copies, the ones in this repository take precedence.

### How the shader is applied to an avatar

SDK avatars are built at runtime, so their materials cannot be assigned in the Editor. The SDK reads a shader
configuration asset instead, and this project supplies
`Assets/Shaders/MetaAvatarShaders/MetaNPRShaderConfiguration.asset`, which points at `Avatar-Meta-UGB.shader`.

The `metavatars` scene applies it by overriding two fields on the SDK manager prefab instance,
`DefaultShaderConfigurationInitializer` and `CelShaderConfigurationInitializer`. Both overrides are stored in
the scene file, not in the SDK prefab, so they survive the sample re-import described above.

If avatars load with Meta's standard appearance and no NPR effect, check those two fields on the SDK manager
object in the scene first. They should both reference `MetaNPRShaderConfiguration`.

---

## 3. Avatar assets

The Mixamo character (Jody, `Assets/AvatarShaderExperimental/Characters/Jade.fbx`) and the Avaturn avatar
(`Assets/Avatars/`) are included. The folder is named Jade internally, which is a legacy name; the character is
referred to as Jody throughout the thesis.

**Mixamo animation import.** Any animation re-imported from [Mixamo](https://www.mixamo.com) must use rig
**Feet** with level **-0.5** in the FBX import settings. Without this the character sinks below the ground
plane.

**Avaturn normal maps.** Avatars exported from [Avaturn](https://avaturn.me) arrive as `.glb` and are imported
through glTFast, which bypasses the Unity texture importer. Normal maps must therefore be decoded as
`sample.rgb * 2.0 - 1.0`. Using `UnpackNormalScale` assumes DXT5nm encoding and produces a flat grey surface.

---

## 4. Environment textures

The shared studio environment uses two Asset Store packages that are not redistributed:

- **Textures Pack Vol. 1** (`Assets/AvatarShaderExperimental/TexturesPart01/`), the brick and tile surfaces
- **Yughues Free Flooring Materials** (`Assets/AvatarShaderExperimental/YughuesFreeFlooringMaterials/`)

The three materials the scenes actually reference are included, `brick_03` and `brick_04` for the walls and
`M_YFFlM_05` for the floor, together with their five textures. The rest of both packs is not redistributed.
Nothing further needs to be installed for the scenes to render as shown in the README.

The lighting configuration used for the comparison renders is a single directional light, elevated -30° and
rotated -30° horizontally relative to the avatar forward vector, at 1.0 lux with a neutral white colour. The
Meta Avatars SDK scene carries additional lighting for technique visibility.

---

## 5. Face animation, optional

Facial animation was driven by **Live Link Face** (Epic Games, iOS), which streams 52 ARKit blendshape
coefficients over UDP on the local network.

The captured data used for the study is not included here for data protection reasons. To capture new data,
note that **UDP streaming does not work over eduroam**, which enforces client isolation and prevents the phone
and the workstation from reaching each other. Use a phone hotspot, a dedicated router or a home network
instead. A university VPN does not resolve this, since it does not bridge the eduroam subnet.

---

## 6. Verifying the installation

| Scene | Expected result |
| --- | --- |
| `Assets/AvatarShaderExperimental/Scenes/Project Scene.unity` | Jody renders with the assigned NPR material, no SDK required |
| `Assets/Scenes/Avaturn.unity` | Avaturn avatar renders, normal maps decoded correctly |
| `Assets/Scenes/metavatars.unity` | Requires the SDK and a connected Quest headset or Link |

For V5 and V6 on Mixamo and Avaturn, confirm that the corresponding renderer feature is enabled on the active
URP renderer asset. Both run as post-process passes, so a disabled feature produces no visible effect even
though the material appears correctly assigned.
