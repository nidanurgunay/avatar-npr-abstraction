# Meta Avatar NPR Study — Project Documentation
**Thesis project · Quest 3 · Unity 2022 LTS / URP**

---

## What This Project Is

A VR study application running on Meta Quest 3. Participants stand in front of a Meta Avatar and assess thirteen different **Non-Photorealistic Rendering (NPR)** styles — cartoon outlines, painterly effects, halftone, hatching, and edge-detection techniques — directly inside the headset without removing it.

The app lets a researcher cycle through six different avatar presets (different faces/body types) while a participant adjusts every shader parameter live through a floating UI panel, then cycles through three display modes (NPR ON / DEFAULT / REALISTIC) with a single button press.

---

## How the App Works

### Scene structure

The scene (`Assets/Scenes/metavatars.unity`) contains one `SampleAvatarEntity` (Meta SDK component) which loads and renders the participant's Meta Avatar. An `OvrAvatarManager` handles the SDK lifecycle. The camera is attached to the Quest headset via the standard OVR rig.

#### Environment

The scene uses the same room geometry as the **Avaturn** and **MixamoJade** scenes for visual consistency across thesis screenshots:

| Object | Transform | Material |
|--------|-----------|----------|
| **Room** (parent) | pos (0,0,0), scale (1,1,1) | — |
| **Floor** | scale (2,2,2) | `M_YFFlM_05` — wooden floor (GUID `c74fd1bcdfc3dc548aa878748c2c73e3`) |
| **Plane (1)** — back wall | pos (0,5,−10), rot (90°,0°,0°), scale (2,0.1,1) | `blueWalll` (GUID `f0fb2b67659d745d9bc72e1912950535`) |
| **Plane (2)** — front wall | pos (0,5,10), rot (90°,180°,0°), scale (2,1,1) | `brick_03` (GUID `80571da6ac21c664a810bb99daf9585f`) |
| **Plane (3)** — left wall | pos (−10,5,0), rot (90°,90°,0°), scale (2,1,1) | `blueWalll` |
| **Plane (4)** — right wall | pos (10,5,0), rot (90°,270°,0°), scale (2,1,1) | `brick_03` |

The room is 20 × 20 m (walls at ±10 in X and Z) with 10 m height. The Meta Avatar (`AvatarEntity1`) stands at position (0, 0, 1.5) — centre of the room, slightly in front of the player.

On top of this there are two custom scripts:

| Script | Responsibility |
|--------|---------------|
| `AvatarSwitcher.cs` | Cycles avatar presets with the left thumbstick (Y button enters/exits selection mode). Shows a floating HUD. |
| `NPREdgeDetectionUI.cs` | World-space panel opened with B button. All NPR parameters are tunable here with the right controller. |

### Controller layout

| Button | Action |
|--------|--------|
| **Y** (left top) | Toggle avatar selection mode on/off |
| **Left thumbstick** ← / → | Previous / next avatar preset (while selection mode is on) |
| **B** (right top) | Open / close the NPR parameter panel |
| **Right trigger** (drag) | Drag a slider in the NPR panel |
| **Right grip** | Decrement the selected float row |
| **Left grip** | Increment the selected float row |
| **A** (right bottom) | Freeze / unfreeze avatar pose |
| **X** (left bottom) | Freeze / unfreeze avatar pose |

### Avatar preset switching

Pressing Y enters avatar-selection mode and shows a floating HUD. Moving the left thumbstick steps through presets 0–5. Because the avatar loads asynchronously from a bundled zip file (~2–5 seconds on Quest 3), the HUD shows **"Loading preset X… Please wait"** in amber while the switch is in progress and returns to normal blue text when the new avatar is ready. Stick input is blocked during loading to prevent stacking requests.

### NPR parameter panel

Opening the panel (B button) spawns a world-space canvas 2 m in front of the player. The right controller ray-casts against the panel:
- **Trigger** — selects a row and drags its value
- **Right grip** — decrements the selected float row
- **Left grip** — increments the selected float row
- Rows are organised by technique; irrelevant rows are hidden (e.g. Blur Radius is only visible when Gauss Blur is ON)

At the very top of the panel is a **Mode [cycle]** button. Each press toggles between two display states:
1. **NPR ON** — `ENABLE_NPR_EDGES` enabled, outline pass enabled, current technique active
2. **DEFAULT** — `ENABLE_NPR_EDGES` disabled, outline disabled; Meta's full `STYLE_2_STANDARD` PBR (rim light, SSS, hair)

---

## NPR Shader Architecture

### Integration point

Meta's avatar shader exposes `AppSpecificPostManipulation` — a hook called at the end of the fragment shader after all PBR lighting and cel-shading are composited. All NPR effects write into `o.color` here. They never touch the lighting pipeline.

### Technique selection

Two `multi_compile` shader keyword sets control what runs:

```
ENABLE_NPR_EDGES              — master on/off (all effects gated here)

EFFECT_SOBEL | EFFECT_NORMAL_EDGE | EFFECT_GAUSS_SOBEL |
EFFECT_HIERARCHICAL | EFFECT_KUWAHARA | EFFECT_KUWAHARA_SOBEL |
EFFECT_KUW_GAUSS_HIER | EFFECT_TOON | EFFECT_TOON_SOBEL |
EFFECT_TOON_HIER              — mutually exclusive technique
```

Each combination is a separate compiled shader variant — zero runtime branching cost. The UI toggles these via `Material.EnableKeyword` / `DisableKeyword`.

When `ENABLE_NPR_EDGES` is on but no technique keyword is set, the default **Derivative** technique runs.

### Inverted-hull outline (always available, separate toggle)

A second render pass (`OUTLINE_PASS`) draws the avatar again with reversed face culling. Each vertex is displaced outward along its world-space normal by `_OutlineWidth` world units. The pass outputs a flat `_OutlineColor` with no lighting — clean silhouette, no interaction with the edge techniques.

The outline pass runs inside the existing `Avatar/MetaNPR` shader via the `AppSpecificVertexPostManipulation` / `AppSpecificPostManipulation` hooks in `app_functions.hlsl`. No separate material is needed.

| Property | Default | Description |
|----------|---------|-------------|
| `_OutlineEnabled` | 1 | `[Toggle]` — 0 = off (outline fragments discarded), 1 = on |
| `_OutlineWidth` | 0.003 | Extrusion in world units (same scale as Avaturn/Jade outline shaders) |
| `_OutlineColor` | (0,0,0,1) | Flat outline colour |

All three properties are exposed in the **Inverted Hull Outline** section of the NPR panel (B button), which is **always visible regardless of technique**. The outline can be layered on top of any NPR technique (Sobel + outline, Toon + outline, XToon + outline, etc.). Switching to DEFAULT mode forces the outline off; switching back to NPR ON restores the toggle's last state. Selecting the **Inverted Hull** technique forces the outline ON (it is the sole visual in that mode) and updates the toggle to reflect this.

**Note on alpha test:** Avaturn and Jade avatars use explicit alpha-test cutout on their outline pass to handle transparent hair and eyelash sprites (`_EnableAlphaTest` / `_AlphaCutoff` on the `V1_InvertedHullOutline` shader). The Meta Avatar SDK manages hair and eyelash transparency internally — the SDK shader clips these fragments before the outline pass runs, so no equivalent alpha-test property is needed on the Meta avatar outline.

---

## Shader Techniques

### Technique 1 — Derivative (default)
**File:** `AvatarNPREdgeEffect.cginc`

Uses the GPU's hardware `ddx` / `ddy` instructions on base colour and normal map XY channels. These are computed for free by the quad rasteriser — no extra texture samples. The two channels are **fully independent**: each has its own threshold, max, and strength. Either channel can be disabled by setting its strength to 0.

**Toon posterization:** Before edge detection runs, the fully-composited lit colour is optionally quantized into discrete luminance bands, giving a cel-shaded stepped-lighting appearance. Because `AppSpecificPostManipulation` receives the final PBR+cel colour (raw NdotL is no longer accessible), posterization works by scaling the RGB vector so its luminance lands on the nearest band boundary — the hue and saturation are preserved, only brightness is stepped. `_ToonBands` (2–8) sets how many steps; `_ToonStrength` blends between original PBR and fully posterized. Default strength is 0 (off).

```
colorEdge  = |∇baseColor|       → draw if ColorThreshold ≤ colorEdge ≤ ColorEdgeMax
normalEdge = |∇normalXY|        → draw if NormalThreshold ≤ normalEdge ≤ NormalEdgeMax

edge = saturate(colorHit × ColorStrength + normalHit × NormalStrength)
```

| UI Slider | What it does |
|-----------|-------------|
| Color Thresh | Minimum colour gradient to count as an edge |
| Color Max | Suppresses UV-seam spikes above this value |
| Color Str | Opacity of the colour-derived edge |
| Normal Thresh | Minimum normal gradient to count as an edge |
| Normal Max | Suppresses seam spikes on the normal channel |
| Normal Str | Opacity of the normal-derived edge |

**Characteristics:** Zero extra samples. Setting Color Str = 0 gives a pure geometry/crease line from the normal map; setting Normal Str = 0 gives a pure texture/colour edge. Both channels can be active simultaneously and are max-blended via `saturate`.

---

### Technique 2 — Sobel
**File:** `NPREffect_Sobel.cginc`

3×3 Sobel operator on base colour luminance. Samples 8 neighbours in UV space and computes:

```
Gx = (tr + 2r + br) − (tl + 2l + bl)
Gy = (tl + 2t + tr) − (bl + 2b + br)
edgeMag = √(Gx² + Gy²)
```

**Runtime toggle:** `_EnableSobel` (Float, default 1). Set to 0 to bypass all Sobel work without changing the shader keyword. The VR panel exposes this as a **Sobel On** toggle row; all dependent parameter rows are hidden when the toggle is OFF.

**Single threshold:** A single `_SobelThreshold` controls the minimum edge magnitude. Edges below the threshold are ignored; edges above (up to `_SobelMax`) are drawn. Raising the threshold suppresses weak/noisy edges; lowering it reveals fine detail.

**Seam suppression:** If luminance range across all 8 neighbours exceeds `SeamLimit`, the pixel is on a UV seam and the edge is suppressed.

**Characteristics:** Directionally accurate. Skin-adaptive threshold reduces false edges. Still operates on unsmoothed samples, so high-frequency textures can produce noisy edges.

---

### Technique 3 — Normal + Fresnel
**File:** `NPREffect_NormalEdge.cginc`

Two signals derived from the world-space normal — one extra texture sample when the normal map is enabled:

**Normal discontinuity:** `ddx/ddy` on the world-space normal detects geometric creases and silhouettes. On Jody (Mixamo) and Avaturn, the normal is first decoded from the PBR normal map via TBN (`_BumpMap` / `_BumpScale` / `_UseNormalMap` toggle) before the derivatives are computed, giving the edge detector access to baked surface microdetail. Falls back to the interpolated geometry normal when the toggle is off.

```
normEdge = smoothstep(Threshold ± Smoothness, |∇worldNormal|) × NormStrength
```

**Fresnel silhouette:** `N·V` approaches zero at grazing angles. A double-smoothstep band isolates that zone:

```
fresnel = 1 − saturate(N·V)
fresnelEdge = smoothstep(band around FresnelThreshold) × FresnelStrength
```

**Characteristics:** Responds to both geometry curvature and normal-map-encoded surface detail when `_UseNormalMap` is enabled; falls back to geometry-only when disabled. Clean contour lines on smooth surfaces. Cannot detect colour-based detail edges.

---

### Technique 4 — Gaussian Sobel
**File:** `NPREffect_GaussianSobel.cginc`

Same 3×3 Sobel as Technique 2, but each of the 8 sample positions is replaced by a **9-tap Gaussian-weighted neighbourhood** before the gradient is computed. This pre-blurs the luminance signal, suppressing high-frequency texture noise before edge detection.

Gaussian weights (configurable, normalised):
```
  diagW  cardW  diagW
  cardW  ctrW   cardW
  diagW  cardW  diagW
  (ctrW + 4×cardW + 4×diagW = 1.0)
```

A threshold band, four progressive smoothstep passes (controlled by a single Tightness parameter), and a power curve give precise control over edge crispness. Tightness = 0 produces soft halo lines; Tightness = 1 produces sharp binary edges.

**Characteristics:** Best-quality colour edge detector. Up to 72 texture samples (8 Sobel positions × 9 Gaussian taps).

---

### Technique 5 — Hierarchical
**File:** `NPREffect_Hierarchical.cginc`

Inspired by the AHEAD (Adaptive Hierarchical Edge Detection) framework. Fuses three independent edge signals — one per physical property of the avatar surface.

**Layer 1 — Depth proxy:**
`length(worldViewDir)` equals camera-to-surface distance. `ddx/ddy` on this scalar detects depth discontinuities at silhouette edges.

**Layer 2 — Normal discontinuity:**
`ddx/ddy` on world normal — same as Technique 3's normal component. Catches geometric creases.

**Layer 3 — Colour (Roberts Cross, optionally Gaussian pre-blurred):**
```
colGrad = |lum(TL) − lum(BR)| + |lum(TR) − lum(BL)|
```
An optional `_HEnableGaussBlur` toggle replaces each of the four sample points with a 9-tap Gaussian neighbourhood before the cross operator runs, smoothing texture noise while preserving structural edges. Weights are user-configurable: `_HCenterWeight`, `_HCardinalWeight`, `_HDiagonalWeight` (normalised at runtime so the kernel always sums to 1). Exposed in the UI as Center W / Cardinal W / Diagonal W, visible only when Gauss Blur is ON.

**Fusion:**
```
edge = max(depthLayer × DepthWeight,
       max(normalLayer × NormalWeight,
           colorLayer  × ColorWeight))
edge = smoothstep(0.20, 0.55, edge)
```

An adaptive sensitivity term scales all layers down in dark areas, avoiding over-edging in shadows.

**Skin colour discard (optional):** When `_HEnableSkinDiscard` is on, the colour-layer edge `colLine` is zeroed for any pixel whose centre sample falls within the configured skin HSV range (`_HSkinHueMin`–`_HSkinHueMax`, saturation ≥ `_HSkinSatMin`). This suppresses false colour edges on smooth face/neck skin while leaving hair, clothing, and eye edges intact.

**Characteristics:** Only technique that simultaneously detects silhouettes (depth), creases (normal), and texture detail (colour) with independent per-layer weights. The Gaussian pre-blur on the colour layer is the most effective addition for noisy avatar textures.

---

### Technique 6 — Kuwahara
**File:** `NPREffect_Kuwahara2.cginc` (anisotropic — replaces former isotropic version)

Single-scale anisotropic Kuwahara filter based on Kyprianidis (NPAR 2011 §3.3). The former isotropic 4-quadrant design was removed in favour of this structure-tensor-guided 8-sector elliptical filter which produces visually superior direction-aware brushstrokes with no perceptible difference in Quest 3 performance.

**Patch — BT.709 luma weights (2026-08-09):** `lum = dot(color.rgb, float3(0.299, 0.587, 0.114))` was replaced with `dot(color.rgb, float3(0.2126, 0.7152, 0.0722))`. The old weights were the BT.601/Rec.601 luma coefficients, a leftover from before the project-wide BT.601→BT.709 migration (see V4 Sobel, which already used BT.709). This was the only remaining spot using BT.601-style weights: Avaturn's and Mixamo/Jade's `AnisotropicKuwahara.shader` structure-tensor luminance already used BT.709 correctly, so the Meta SDK path was the sole outlier. No visible artefact was reported; this brings the structure-tensor orientation estimate onto the same luma definition as every other technique in the pipeline. Thesis `05_implementation.tex` §V6 Meta Avatars SDK listing updated to match.

**Step 1 — Structure tensor:** Hardware `ddx`/`ddy` of the shaded luminance gives `gx`, `gy`. The 2×2 structure tensor `J = [[E,F],[F,G]]` = `[[gx²,gx·gy],[gx·gy,gy²]]` encodes local gradient structure. Eigenanalysis yields:
- `φ` — dominant orientation angle (direction of minimum change, i.e. along the feature): `φ = ½ arctan(2F / (E−G)) + π/2`
- `A` — anisotropy `(λ₁−λ₂)/(λ₁+λ₂)`, range 0–1

**Step 2 — Ellipse axes (paper §3.3.1):**
```
a = (α + A)/α · r    (major axis, along feature direction)
b =  α/(α + A) · r   (minor axis, across feature)
```
`α` is a user-tunable eccentricity parameter (default 1). A=0 gives a circle; A=1 gives 2:1 elongation.

**Step 3 — 8 sectors over the rotated ellipse:** The transform `R_{−φ} · diag(a,b)` maps unit-disc points to UV offsets. For each of 8 sector centre directions (at 0°, 45°, 90°, …, 315° in the unit disc), 3 samples are taken at radii 0.45, 0.75, 1.0, plus the shared centre. Gaussian-inspired weights (0.40, 0.28, 0.20, 0.12) compute the weighted mean `m_i` and std deviation `σ_i` per sector.

**Step 4 — Soft weighted blend (paper §3.3.1 eq.):**
```
ω_i = max(τ, σ_i)^{-q}
result = Σ(ω_i · m_i) / Σ(ω_i)
```
`τ` (default 0.02) prevents divide-by-zero in flat regions. `q` (default 8) controls sharpness — high q means only the most homogeneous sector(s) contribute.

> **Note:** The multi-scale pyramid from the 2011 paper (coarse-to-fine across Lanczos3 levels) requires multiple render passes and cannot be implemented in `AppSpecificPostManipulation`.

| UI Slider | What it does |
|-----------|-------------|
| Radius | Filter ellipse radius (major axis) |
| Strength | Blend with original lit colour |
| Alpha | Eccentricity α — 1 = standard, >1 = more elongated brushstrokes |
| Q Sharp | Sector weight sharpness — higher = harder region boundaries |
| Tau Floor | Variance floor τ — prevents instability in uniform flat areas |

**Characteristics:** Brushstrokes follow surface feature directions. Smooth areas with A≈0 behave like an enhanced isotropic Kuwahara. Strong gradients (A≈1) produce elongated strokes aligned with edges. 25 texture samples (1 centre + 8 sectors × 3).

---

### Technique 7 — Kuwahara + Sobel
**File:** `NPREffect_Kuwahara2Sobel.cginc`

Two stages in one pass:

1. **Kuwahara** (anisotropic, same as Technique 6) — structure-tensor-guided 8-sector painterly stylisation.
2. **Gaussian Sobel (full pipeline)** — applied to the **original** base colour texture. Edge lines composited over the Kuwahara-stylised colour.

Optional 9-tap Gaussian pre-blur per Sobel position, threshold band, 4× progressive smoothstep, power curve.

**Characteristics:** Direction-aware painterly base with sharp Sobel edge lines. The anisotropic Kuwahara step produces more coherent flat regions, reducing false interior edges in the Sobel detector.

---

### Technique 8 — Kuwahara + Hierarchical
**File:** `NPREffect_Kuwahara2GaussHier.cginc`

Two stages in one pass:

1. **Kuwahara** (anisotropic, same as Technique 6) — structure-tensor-guided 8-sector stylisation.
2. **Hierarchical** — depth + normal + Roberts Cross colour layers with adaptive sensitivity. Optional Gaussian pre-blur on the colour layer (`Color Blur` toggle).

**Line width control:** `Hier Tight` — at 0 the final smoothstep is `smoothstep(0.20, 0.55, edge)` (wide soft halos); at 1 it tightens to `smoothstep(0.35, 0.40, edge)` (crisp thin lines).

**Characteristics:** Direction-aware painterly base combined with geometry-aware edge detection (silhouettes via depth, creases via normals, texture detail via Roberts Cross colour). The anisotropic Kuwahara step produces more coherent flat regions, reducing false interior edges in the colour layer.

---

### Technique 9 — Toon / Cel Shader
**File:** `NPREffect_Toon.cginc`
**Keyword:** `EFFECT_TOON`

Pure posterisation-based cel shading — **no edge detection**. Use the inverted-hull outline pass for silhouette lines, and Technique 10 or 11 for image-space edge lines on top.

**Colour posterisation:**
```
posterized = floor(color × bands + 0.5) / bands   // round-to-nearest quantization
color.rgb  = lerp(original, posterized, PosterizeStrength)
```
This gives the stepped flat-colour look of hand-drawn cel animation. Posterization runs **first**, then saturation is scaled independently:
```
lum       = dot(color.rgb, float3(0.2126, 0.7152, 0.0722))
color.rgb = lerp(float3(lum,lum,lum), color.rgb, Saturation)
```
Ordering matters: saturating after posterization avoids driving low channels negative (which would cause darkening when clamped to 0). Default saturation is 1.0 (unchanged); values above 1.0 boost cartoon vibrancy.

| UI Slider | What it does |
|-----------|-------------|
| Color Bands | Discrete posterization steps (2 = two-tone, 4 = four-tone, 8 = subtle) |
| Posterize Str | Blend between original PBR and fully posterized colour |
| Saturation | Colour saturation scale (1 = unchanged, 1.5 = boosted cartoon look) |

**Characteristics:** Zero texture samples. Fast. Combine with the inverted-hull outline for maximum cartoon effect with no extra pass cost. The `AppSpecificPostManipulation` hook receives the final composited PBR colour (raw NdotL is inaccessible), so band quantization works on perceived brightness rather than raw light contribution.

---

### Technique 10 — Toon + Sobel
**File:** `NPREffect_ToonSobel.cginc`
**Keyword:** `EFFECT_TOON_SOBEL`

Two phases in one pass:

**Phase 1 — Toon posterisation:** Identical to Technique 9 using `_TS*`-prefixed uniforms (`_TSColorBands`, `_TSPosterizeStrength`, `_TSSaturation`). Posterize first, then saturate.

**Phase 2 — Gaussian Sobel edge detection:** Identical pipeline to the Sobel stage in Technique 7 (Kuwahara + Sobel), applied to the **original** base colour texture:
- Optional 9-tap Gaussian pre-blur per Sobel sample position (toggle `_TSEnableGaussBlur`)
- Configurable Gaussian weights: `_TSCenterWeight`, `_TSCardinalWeight`, `_TSDiagonalWeight`
- 3×3 Sobel gradient computation
- Threshold band (`_TSThreshold × _TSThreshMin` → `_TSThreshold × _TSThreshMax`)
- 4× progressive smoothstep passes controlled by a single `_TSTightness` parameter
- Power curve (`_TSPowerCurve`) for edge opacity falloff
- Edge colour taken from the shared `_InnerLineColor` uniform

| UI Row | What it does |
|--------|-------------|
| Color Bands | Toon posterization steps |
| Posterize Str | Toon posterization blend |
| Saturation | Toon saturation scale |
| Gauss Blur | Toggle 9-tap Gaussian pre-blur on Sobel samples |
| Sobel Dist | Sobel kernel UV offset |
| Blur Radius | Per-sample Gaussian radius (visible when Gauss Blur ON) |
| Center W / Cardinal W / Diagonal W | Gaussian kernel weights (visible when Gauss Blur ON) |
| Threshold | Sobel edge magnitude threshold |
| Thresh Min / Max | Threshold band multipliers |
| Tightness | Edge crispness (0 = wide soft halos, 1 = crisp thin lines) |
| Power Curve | Post-pass power curve on edge opacity |
| Sobel Strength | Overall edge opacity |

**Characteristics:** Cel-shaded posterized colour with Sobel edge lines. Up to 72 texture samples for the Sobel stage (8 positions × 9 Gaussian taps). Toon posterization produces large flat regions that the Sobel detector reads cleanly, reducing noisy interior edges compared to running Sobel on the original PBR colour.

---

### Technique 11 — Toon + Hierarchical
**File:** `NPREffect_ToonGaussHier.cginc`
**Keyword:** `EFFECT_TOON_HIER`

Two phases in one pass:

**Phase 1 — Toon posterisation:** Identical to Technique 9 using `_TH*`-prefixed uniforms (`_THColorBands`, `_THPosterizeStrength`, `_THSaturation`). Posterize first, then saturate.

**Phase 2 — Hierarchical edge detection:** Identical pipeline to Technique 5 (Hierarchical) and the hierarchical stage in Technique 8 (Kuwahara + Hierarchical):

- **Depth layer:** `ddx/ddy` on `length(worldViewDir)` → silhouette edges
- **Normal layer:** `ddx/ddy` on world normal → geometric crease edges
- **Colour layer (Roberts Cross):** diagonal luminance differences `|lum(TL)−lum(BR)| + |lum(TR)−lum(BL)|` using `_TH*`-prefixed Gaussian weights; optional 9-tap Gaussian pre-blur per sample point (`_THEnableGaussBlur`)
- **Adaptive suppression:** scales all layers down in dark areas by `_THAdaptiveStrength`
- **Fusion:** `max(depthLayer × DepthWeight, max(normalLayer × NormalWeight, colorLayer × ColorWeight))`
- **Line width:** `_THHierTightness` controls the final smoothstep band (0 = wide halos, 1 = crisp thin lines)
- **Edge colour:** `_THEdgeColor` (technique-specific, unlike Toon+Sobel which reuses `_InnerLineColor`)

| UI Row | What it does |
|--------|-------------|
| Color Bands | Toon posterization steps |
| Posterize Str | Toon posterization blend |
| Saturation | Toon saturation scale |
| Depth Thresh / Normal Thresh / Color Thresh | Per-layer detection thresholds |
| Depth W / Normal W / Color W | Per-layer blend weights |
| Edge Width | Roberts Cross UV offset |
| Adaptive Str | Dark-area edge suppression strength |
| Hier Tight | Edge crispness (0 = soft, 1 = crisp) |
| Hier Strength | Overall hierarchical edge opacity |
| Color Blur | Toggle 9-tap Gaussian pre-blur on colour samples |
| Blur Radius / Center W / Cardinal W / Diagonal W | Gaussian kernel params (visible when Color Blur ON) |
| Edge Color | Ink colour for hierarchical edges |

**Characteristics:** Cel-shaded posterized colour with geometry-aware edge detection (silhouettes, creases, colour detail) and per-layer weight control. Most flexible of the three Toon variants. 4–36 texture samples for the colour layer depending on Gaussian blur state.

---

### Technique 12 — Halftone
**File:** `NPREffect_Halftone.cginc`
**Keyword:** `EFFECT_HALFTONE`
**Source:** Adapted from `Assets/Shaders/CommonNPRShaders/HalftoneHatching.shader` (`HalftonePattern` function).

Circular dot grid in UV space. Tone is derived from the luminance of the incoming PBR colour, normalised by `_HTToneWhitePoint` so the expected peak luminance maps to `tone = 1.0` (pure paper). Darker areas produce larger dots; fully-lit highlights produce none.

```
lum      = dot(PBRcolor, float3(0.299, 0.587, 0.114))
tone     = saturate(lum / HTToneWhitePoint + HTToneBias)   // white-point normalisation
rotated  = Rotate2D(uv, HTAngle)
gridPos  = frac(rotated × HTScale) − 0.5
dist     = length(gridPos)
dotRadius = sqrt(max(0, 1 − tone)) × 0.5          // area ∝ darkness (halftone screen model)
sharpInv  = 0.5 / max(HTSharpness, 0.001)
visibility = smoothstep(0, 2×sharpInv, dotRadius)  // suppress near-zero-radius artifact
pattern  = (1 − smoothstep(dotRadius − sharpInv, dotRadius + sharpInv, dist)) × visibility
```

**Visibility suppression:** when `tone = 1.0` and `dotRadius = 0`, `smoothstep(−ε, +ε, 0) = 0.5` would leak faint ink at every grid centre. The `visibility` ramp drives the pattern to zero before `dotRadius` enters that degenerate range.

**Colour model (identical to HalftoneHatching source):**
```
paperCol     = lerp(HTPaperColor,  PBRcolor,              TextureInfluence)
inkCol       = lerp(HTInkColor,    PBRcolor × HTInkColor, TextureInfluence)
patternColor = lerp(paperCol, inkCol, pattern)
finalColor   = lerp(PBRcolor, patternColor, HTStrength)
```
`TextureInfluence = 0` gives a flat ink-on-paper look; `= 1` tints the ink and paper with the original PBR colour, preserving avatar texture detail.

| UI Row | What it does |
|--------|-------------|
| Dot Scale | Grid frequency — higher = more, smaller dots |
| Sharpness | Dot edge softness (1 = very soft, 50 = crisp) |
| Grid Angle | Rotation of the dot grid (0–90°) |
| Tone Bias | Shifts tone darker/lighter (-0.5–0.5) |
| Tone White Point | Peak luminance mapped to tone=1.0 (pure paper); set to match material's max lit brightness (0.1–1.0, default 0.75) |
| Ink Color | Dot fill colour |
| Paper Color | Background colour |
| Tex Influence | Blend between flat and PBR-tinted ink/paper |
| Strength | Overall blend of halftone over original PBR |

**Characteristics:** Zero extra texture samples (fully procedural). UV-space grid follows the avatar's UV layout rather than screen pixels — patterns appear stable when the head turns. Combine with the inverted-hull outline for a classic comic-print look.

---

### Technique 13 — Hatching
**File:** `NPREffect_Hatching.cginc`
**Keyword:** `EFFECT_HATCHING`
**Source:** Adapted from `Assets/Shaders/CommonNPRShaders/HalftoneHatching.shader` (`HatchingPattern` function, Tonal Art Map approach).

Line layers activate progressively as tone darkens, following Praun et al. "Real-Time Hatching" (SIGGRAPH 2001). Tone is derived from the luminance of the incoming PBR colour, normalised by `_HatToneWhitePoint` so peak-lit pixels reach `tone = 1.0` (pure paper). Layer thresholds are driven by `_HatToneLevels` (default 6), matching Praun's TAM column spacing.

```
lum  = dot(PBRcolor, float3(0.299, 0.587, 0.114))
tone = saturate(lum / HatToneWhitePoint + HatToneBias)   // white-point normalisation
t    = 1 − tone                                           // darkness (0=lit, 1=dark)
step = 1.0 / HatToneLevels

Layer 1 (t > step):      primary direction  × smoothstep(step,   2×step, t)
Layer 2 (t > 2×step):    cross direction    × smoothstep(2×step, 3×step, t)   [if N≥3]
Layer 3 (t > 3×step):    dense diagonal     × smoothstep(3×step, 4×step, t)   [if N≥4, thickness×1.5]
Fill    (t > (N-1)×step): solid ink         = smoothstep((N-1)×step, 1.0, t)

pattern = max across active layers
```

Each layer uses a rotated line grid:
```
rotated = Rotate2D(uv, angleDeg)
linePos = frac(rotated.x × HatScale)
line    = 1 − smoothstep(thickness, thickness+0.02, |linePos − 0.5|)
```

Same ink/paper colour model as Halftone (above) using `_Hat*` uniforms.

| UI Row | What it does |
|--------|-------------|
| Hatch Scale | Line grid frequency |
| Primary Angle | Direction of Layer 1 lines (0–180°) |
| Cross Angle | Direction of Layer 2 lines (0–180°) |
| Thickness | Line width (0.01 = hairline, 0.5 = thick) |
| Tone Bias | Shifts tone darker/lighter |
| Tone White Point | Peak luminance mapped to tone=1.0 (pure paper); set to match material's max lit brightness (0.1–1.0, default 0.75) |
| Tone Levels | TAM column count — layer thresholds at k/N (2–8, default 6) |
| Ink Color | Line colour |
| Paper Color | Background between lines |
| Tex Influence | Blend between flat and PBR-tinted ink/paper |
| Strength | Overall blend of hatching over original PBR |

**Characteristics:** Zero extra texture samples (fully procedural). Three independent line directions emerge naturally as the avatar's shaded tone darkens. Combine with the inverted-hull outline for a pen-and-ink illustration look.

---

## Technique Summary

| # | Name | File | Signal source | Stylises colour | Extra samples |
|---|------|------|--------------|-----------------|---------------|
| 1 | Derivative | `AvatarNPREdgeEffect.cginc` | ddx/ddy colour + normal | No | 0 |
| 2 | Sobel | `NPREffect_Sobel.cginc` | 3×3 luminance kernel | No | 8 |
| 3 | Normal + Fresnel | `NPREffect_NormalEdge.cginc` | World normal + N·V | No | 0 |
| 4 | Gaussian Sobel | `NPREffect_GaussianSobel.cginc` | 9-tap Gaussian × 8 Sobel positions | No | up to 72 |
| 5 | Hierarchical | `NPREffect_Hierarchical.cginc` | Depth + normal + Roberts Cross (+ optional Gaussian) | No | 4–36 |
| 6 | Kuwahara | `NPREffect_Kuwahara2.cginc` | Anisotropic 8-sector ellipse (structure tensor φ+A) | **Yes** | 25 |
| 7 | Kuwahara + Sobel | `NPREffect_Kuwahara2Sobel.cginc` | Kuwahara + full Gaussian Sobel pipeline | **Yes** | 25 + up to 72 |
| 8 | Kuwahara + Hierarchical | `NPREffect_Kuwahara2GaussHier.cginc` | Kuwahara + depth/normal/colour layers (+ optional Gaussian) | **Yes** | 25 + 4–36 |
| 9 | Toon / Cel Shader | `NPREffect_Toon.cginc` | Posterize bands + saturation (no edges) | **Yes** | 0 |
| 10 | Toon + Sobel | `NPREffect_ToonSobel.cginc` | Toon posterize + full Gaussian Sobel pipeline | **Yes** | up to 72 |
| 11 | Toon + Hierarchical | `NPREffect_ToonGaussHier.cginc` | Toon posterize + depth/normal/colour layers (+ optional Gaussian) | **Yes** | 4–36 |
| 12 | Halftone | `NPREffect_Halftone.cginc` | Procedural UV-space dot grid, tone from luminance | **Yes** | 0 |
| 13 | Hatching | `NPREffect_Hatching.cginc` | TAM 4-layer UV-space line grid, tone from luminance | **Yes** | 0 |

---

## V1 & V1.2 Cross-Avatar Analysis

This section documents the two thesis-framed technique generations — **V1 (Toon Shading + Inverted Hull Outline)** as the baseline and **V1.2 (XToon 2D Ramp)** as the advanced technique — and compares their implementation across all three avatar types in the project.

---

### V1 — Toon Shading with Inverted Hull Outline

**Concept:** Classic cel-shading using NdotL quantisation (discrete light bands) combined with an inverted-hull geometry pass for outer silhouette lines. This is the foundation of real-time NPR; virtually every cartoon game uses a variant of it.

#### Mixamo / Jade Avatar

**Shader:** `Assets/Shaders/JadeNPRShaders/V1_ToonShading_GeometryOutline.shader`
**Shader name in Unity:** `Custom/V1_ToonShading_GeometryOutline`
**Pipeline target:** URP, `#pragma target 3.0`
**Materials:** `Assets/AvatarShaderExperimental/Materials/CToon V1 Toon only/`

**Outline pass (Pass 0 — inverted hull):**
- `Cull Front` renders back-faces only; `ZWrite On`, `ZTest Less`
- Each vertex is displaced along its world-space normal by `_OuterOutlineWidth` (world units)
- Fragment returns a flat `_OuterOutlineColor`; alpha-test clip applied if `_EnableAlphaTest` is on (eyelash support)
- Optional `_OutlineDepthBias` pushes clip-space Z toward the camera to prevent z-fighting

**Toon pass (Pass 1 — ForwardLit):**
```hlsl
float smooth = smoothstep(Threshold - Smoothness, Threshold + Smoothness, NdotL);
float toon   = floor(smooth * steps) / steps;
toon = lerp(1.0, toon, ShadowStrength);
```
- Single smooth threshold collapses NdotL into one lit/unlit region; `floor × steps` then quantises into bands
- Ambient `_AmbientColor` added additively; rim light `pow(1 - N·V, _RimPower) * _RimColor` overlaid on top; controlled by `_EnableRim` toggle (default ON)

**Toon quantisation algorithm:** Unified with the Avaturn version — per-step `smoothstep` at every band boundary (see Avaturn section below for the formula). The previous single-threshold `smoothstep → floor` approach was replaced; `_ToonThreshold` property was removed.

**Key difference from Avaturn:** No `OVR_FETCH_POS_NORM` — vertex positions and normals come directly from the mesh, without compute-skinning support. Works fine for standard SkinnedMeshRenderer avatars.

**VHull / JadeHull materials — standalone comparison shader:**
`Assets/Shaders/CommonNPRShaders/V1_InvertedHullOutline.shader` (`Custom/V1_InvertedHullOutline`) is a shared two-pass shader used for both the Avaturn (VHull_*) and Jade (JadeHull_*) inverted-hull comparison materials. Unlike the toon shader above, it renders the surface with **full URP PBR** (`UniversalFragmentPBR`) so the avatar looks identical to its default appearance but with an added outline. Use it in the thesis scene as a side-by-side comparison: same avatar, same lighting, outline added, everything else unchanged.

**Two-pass structure:**
- **Pass 0 (Outline)** — `Cull Front`; displaces back-face vertices along world-space normals by `_OutlineWidth`; outputs flat `_OutlineColor`
- **Pass 1 (ForwardLit)** — `Cull Back`; full PBR via `UniversalFragmentPBR` with albedo (`_MainTex`), normal map (`_BumpMap`), metallic-roughness (`_MetallicGlossMap`), and occlusion (`_OcclusionMap`)

**Channel convention (GLTFast/glTF format, not URP Lit):**
```hlsl
half4 ms         = SAMPLE_TEXTURE2D(_MetallicGlossMap, ...);
half  metallic   = ms.b * _Metallic;           // B = metallic  (GLTFast)
half  smoothness = (1.0h - ms.g) * _Smoothness; // G = roughness → inverted
```
The `_Metallic` and `_Smoothness` properties act as **strength multipliers** (0 = ignore map, 1 = full map value), not raw values. The `VHullTextureAssigner` tool sets them to 1 when a map is present.

**Texture assignment tool:** `Tools > Assign All Textures to VHull Materials` (runs `Assets/Editor/VHullTextureAssigner.cs`). Assigns albedo, normal, metallic-roughness, and occlusion from the Avaturn GLB sub-assets to all six VHull materials in one click.

**Normal map import:** After running the tool, select each normal map sub-asset in the Project window (image_2, image_8, image_12, image_18, image_25 inside `Assets/Avatars/Avaturn.glb`) → Inspector → **Texture Type → Normal Map → Apply**. Without this, `UnpackNormalScale` reads incorrect data and clothing creases remain invisible.

**SRP Batcher requirement:** Both passes must declare an identical `CBUFFER_START(UnityPerMaterial)` block including all properties used by either pass. The outline pass includes `_BumpScale`, `_Metallic`, `_Smoothness`, `_OcclusionStrength` even though it doesn't use them — this is required for SRP Batcher compatibility.

---

#### Avaturn Avatar

**Shader:** `Assets/Shaders/AvaturnNPRShaders/V1_ToonShading_GeometryOutline.shader`
**Shader name in Unity:** `Custom/V1_ToonShading_GeometryOutline`
**Pipeline target:** URP, `#pragma target 3.5`
**Materials:** `Assets/Materials/NPR Avaturn Materials/V1 ToonShading/` (5 materials: body, head, hair, eyelash, look)

**Outline pass:** Identical intent to Mixamo but includes `OVR_FETCH_POS_NORM(v.vertex.xyz, v.normal, v.vertexID)` before computing world positions. This fetch bridge allows the same shader to work with both standard skinning and Meta SDK compute skinning (external vertex buffers). Without it, the Meta SDK's GPU-skinned vertices would not be visible to the outline pass.

**Toon pass — refined quantisation algorithm:**
```hlsl
float steps  = max(1.0, _ToonSteps);
float scaled = NdotL * steps;
float band   = floor(scaled);
float frac   = scaled - band;
float blend  = smoothstep(1.0 - _ToonSmoothness, 1.0, frac);
float toon   = saturate((band + blend) / steps);
toon = lerp(1.0 - _ShadowStrength, 1.0, toon);
```
- Per-step blending: each individual band boundary gets a narrow smooth transition of width `_ToonSmoothness`, preventing normal jitter near any seam from flipping a whole patch between steps
- This replaces the Mixamo version's single global threshold with a more robust per-band approach

**Additional passes:** None beyond outline + ForwardLit; depth/normals written by the standard URP mechanism.

---

#### Meta Avatar SDK

**Shader:** `Assets/Shaders/MetaAvatarShaders/Avatar-Meta-UGB.shader`
**Keyword:** `EFFECT_TOON` (activated with `ENABLE_NPR_EDGES`)
**Technique file:** `Assets/Shaders/MetaAvatarShaders/NPREffect_Toon.cginc`
**Pipeline target:** URP target 5.0 (primary) + 3.5 compatibility fallback + Built-in RP fallback

**Toon (posterisation) implementation:**
```hlsl
// NPREffect_Toon.cginc
float  bands      = max(2.0, _ToonColorBands);
float3 posterized = floor(color.rgb * bands + 0.5) / bands;
color.rgb = lerp(color.rgb, posterized, _ToonPosterizeStrength);

float lum  = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
color.rgb  = lerp(float3(lum, lum, lum), color.rgb, _ToonSaturation);
```
- Operates in `AppSpecificPostManipulation` — receives the **fully composited PBR colour** (NdotL + shadows + SSS + rim light already baked in)
- Quantisation works on RGB directly (round-to-nearest), which preserves hue and saturation while stepping luminance
- Saturation runs **after** posterisation to avoid clamping artefacts

**Outline (inverted hull) implementation:**
- A dedicated `NPROutline` pass (`Cull Front`, `ZWrite Off`, `ZTest LEqual`) reuses the same vertex shader; `#define OUTLINE_PASS 1` routes `AppSpecificVertexPostManipulation` to push each skinned vertex outward along its world normal:
  ```hlsl
  float3 worldPos = o.v_WorldPos + normalize(o.v_Normal) * _OutlineWidth * 0.001;
  ```
- The outline pass is toggled via `_OutlineEnabled`; discards if `< 0.5`

**Critical architectural difference:** The Meta implementation is a **post-process hook inside the existing PBR pipeline**, not a standalone shader. The toon effect stylises the output of Meta's full STYLE_2_STANDARD renderer (which includes subsurface scattering, anisotropic hair, eye glints, IBL). This means the cel-shaded colour still reflects the physical material quality underneath.

| Property | Mixamo V1 | Avaturn V1 | Meta V1 |
|----------|-----------|-----------|---------|
| Quantisation method | Per-step `smoothstep` + `(band + blend) / steps` (unified) | Per-step `smoothstep` + `(band + blend) / steps` | `floor(rgb × bands + 0.5) / bands` |
| Input to quantiser | Raw NdotL | Raw NdotL | Composited PBR RGB |
| Rim light | Yes (`_EnableRim` toggle, default ON, additive) | Yes (`_EnableRim` toggle, default ON, additive) | Via Meta PBR (pre-composited) |
| Compute-skinning bridge | No | Yes (`OVR_FETCH_POS_NORM`) | Yes (SDK native) |
| Outline technique | Inverted hull (world-space normal offset) | Inverted hull (world-space normal offset) | Inverted hull (world-space normal offset, separate pass) |
| Outline toggleable | No (always on if pass enabled) | No (always on if pass enabled) | Yes (`_OutlineEnabled`) |
| Shadow support | Yes (URP `GetMainLight`) | Yes (URP `GetMainLight` + cascades) | Yes (Meta PBR shadow attenuation) |

---

### V1.2 — XToon: Extended Toon Shader with 2D Ramp

**Concept:** Barla et al. NPAR 2006. Replaces the 1D NdotL lookup with a **2D texture lookup** whose axes are independently configurable:
- **U axis** — lighting intensity (NdotL or luminance proxy)
- **V axis** — abstraction/detail level (depth, curvature, or manual)

This decouples "how lit is this pixel" from "how much stylistic detail should this pixel show", enabling effects like distant objects appearing more simplified and close objects retaining brush-detail — matching how illustrators vary linework by distance or focal importance.

---

#### Mixamo / Jade Avatar

**Shader:** `Assets/Shaders/JadeNPRShaders/XToon_2DRamp.shader`
**Shader name in Unity:** `NPR/XToon_2DRamp_Jade`
**Pipeline target:** URP, `#pragma target 3.5`
**Materials:** `Assets/AvatarShaderExperimental/Materials/Xtoon/` (4 materials: Body, Clothing, Hair, Eyelash)

**Main pass (XToonForward):**
```hlsl
// U axis: NdotL with shadow attenuation
float NdotL = dot(normalWS, lightDir) * shadow;
float rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);

// V axis (selectable via shader_feature keyword)
// Depth:     saturate((dist - DepthNear) / (DepthFar - DepthNear)) + DetailBias
// Curvature: 1.0 - saturate((|ddx(N)| + |ddy(N)|) × 10)
// Manual:    _ManualDetail

float3 rampColor = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp, float2(rampU, rampV)).rgb;
```

**Abstraction compression (same in all three avatar implementations):**
```hlsl
float abstractU    = lerp(rampU, 0.5, rampV * 0.6);
float dynSmoothing = lerp(RampSmoothing, RampSmoothing + 0.35, rampV);
float shadowMask   = smoothstep(0.5 - dynSmoothing, 0.5 + dynSmoothing, abstractU);
float3 toonAlbedo  = albedo * rampColor;
float3 shadowed    = lerp(toonAlbedo * ShadowColor, toonAlbedo, shadowMask);
```
As `rampV` rises (more abstraction), both the U range and the ramp smoothing widen — lighting bands dissolve into a single mid-tone, which is the defining visual of XToon abstraction.

**Normal Field Abstraction:** `_UseAbstractNormals` (Float, default **1** — on by default). When enabled, a `_AbstractNormalMap` is sampled, transformed from tangent space via TBN, and lerped with the vertex normal using `_NormalSmoothing`. When the slot is empty the "bump" default texture produces (0,0,1) tangent-normal which is identity — effectively the same as the vertex normal, so enabling the toggle with no texture assigned has no visible cost. When the toggle is OFF, a positional smoothing approximation is applied instead:
```hlsl
float3 smoothN = normalize(normalWS + NormalSmoothing * (normalize(posWS) - normalWS));
```

**Specular:** Stylised Blinn-Phong `smoothstep` on NdotH (raw access to light direction is available here).

**Inline Sobel (optional):** `_EnableSobel` runs a 3×3 luminance Sobel on `_BaseMap` in UV space and composites edge lines over the toon result.

**Outline pass (Pass 1 — Outline):** `Cull Front`, `SRPDefaultUnlit`. Vertex displaced by `normalWS * _OutlineWidth` in world space. Outputs flat `_OutlineColor`.

**Difference from Avaturn:** No `OVR_FETCH_POS_NORM` — standard mesh vertex input only.

---

#### Avaturn Avatar

**Shader:** `Assets/Shaders/AvaturnNPRShaders/XToon_2DRamp.shader`
**Shader name in Unity:** `NPR/XToon_2DRamp`
**Pipeline target:** URP, `#pragma target 3.5`
**Materials:** `Assets/Materials/NPR Avaturn Materials/VXT XToon/` (5 materials: body, head, hair, eyelash, look)

This is the production-quality version of the shader. It is functionally identical to the Mixamo/Jade version in all NPR logic. The Avaturn avatar is a `.glb` loaded via GLTFast and uses a standard `SkinnedMeshRenderer` — the same skinning path as the Jade FBX. There is no Meta SDK compute-skinning external vertex buffer, so `OVR_FETCH_POS_NORM` was never needed. The shader is now identical to Jade in vertex fetch, property order, and CBUFFER layout.

Avaturn's extra passes over Jade:

1. **Shadow Caster pass (Pass 2):** A self-contained `ShadowCaster` pass with `ApplyShadowBias` — the Jade/Mixamo version relies on the FallBack. Avoids shadow bias artefacts on the GLB model.
2. **Depth Only pass (Pass 3):** A self-contained `DepthOnly` pass with `ColorMask R`, feeding the URP depth prepass that post-process effects depend on.
3. **Alpha blend support (`_ALPHA_BLEND` keyword):** `_SrcBlend`/`_DstBlend`/`_ZWrite` exposed as hidden properties — used for the eyelash material without needing a separate shader.

**Material notes:**
- `VXT_eyelash.mat` — `_SrcBlend=5` (SrcAlpha), `_DstBlend=10` (OneMinusSrcAlpha), `_ZWrite=0`, Sobel off, no outline
- `VXT_body/head/hair` — Sobel on, outline on, `_ToonRamp` slot left empty (must assign a 2D ramp texture in Unity)

---

#### Meta Avatar SDK (newly implemented)

**Shader:** `Assets/Shaders/MetaAvatarShaders/Avatar-Meta-UGB.shader`
**Keyword:** `EFFECT_XTOON` (activated with `ENABLE_NPR_EDGES`)
**Technique file:** `Assets/Shaders/MetaAvatarShaders/NPREffect_XToon.cginc`

**Implementation:** `AppSpecificPostManipulation` receives `i.geometry.positionInWorldSpace` and the world normal, allowing the Meta XToon to match Jade/Avaturn exactly:
- **U axis** — shadow-attenuated `NdotL` (same as Jade/Avaturn). `GetMainLight(shadowCoord)` is called with `TransformWorldToShadowCoord(positionWS)` to fetch both the light direction and shadow attenuation. `NdotL *= shadow`, then `rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _XToonLightSensitivity)`.
- **V axis** — real world-space depth via `length(_WorldSpaceCameraPos - positionWS)`, identical formula to Jade/Avaturn.
- **Normal smoothing** — geometric path: `normalWS = lerp(normalWS, smoothed, _XToonNormalSmoothing * 0.5)`.
- **LightingStrength blend** — `lerp(textureColor, finalColor, _XToonLightingStrength)` where `textureColor` is the shadow-tinted toon result (not the raw PBR input), matching Jade/Avaturn.

**Core implementation:**
```hlsl
// U: shadow-attenuated NdotL (matches Jade/Avaturn)
float NdotL = dot(normalWS, lightDir) * shadow;
float rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _XToonLightSensitivity);

// V: abstraction level (real world-space depth)
float rampV = _XToonComputeDetailAxis(positionWS, normalWS);

// 2D ramp sample
float3 rampColor = tex2D(_XToonRamp, float2(rampU, rampV)).rgb;

// Abstraction compression (identical formula to Jade/Avaturn)
float abstractU    = lerp(rampU, 0.5, rampV * 0.6);
float dynSmoothing = lerp(_XToonRampSmoothing, _XToonRampSmoothing + 0.35, rampV);
float shadowMask   = smoothstep(0.5 - dynSmoothing, 0.5 + dynSmoothing, abstractU);
float3 toonColor     = color.rgb * rampColor;
float3 shadowedColor = lerp(toonColor * _XToonShadowColor.rgb, toonColor, shadowMask);
float3 textureColor  = lerp(color.rgb, shadowedColor, _XToonShadowStrength);  // toon base
// ... specular, rim → finalColor
finalColor = lerp(textureColor, finalColor, _XToonLightingStrength);
```

**Specular:** Shadow-attenuated Blinn-Phong (`NdotH × shadow`), identical to Jade/Avaturn. `_MainLightPosition.xyz` is a URP per-frame global; `NPREffect_XToon.cginc` remaps it to `_WorldSpaceLightPos0` via `#ifndef UNITY_PIPELINE_URP` for the legacy CG subshader.

**`_XToonLightingStrength`** blends between `textureColor` (toon base with shadow tinting) and the fully stylised result (with specular, rim). Setting to 0 shows the shadow-tinted toon without specular/rim; setting to 1 shows the full effect.

**Inverted hull outline:** Reuses the existing `NPROutline` pass with `_OutlineEnabled`, `_OutlineWidth`, `_OutlineColor` — identical to all other Meta techniques.

**Shader variants added:**
- `EFFECT_XTOON` added to the `multi_compile` list in `app_functions.hlsl`
- Include dispatch and `AppSpecificPostManipulation` condition updated

| Property | Mixamo V1.2 | Avaturn V1.2 | Meta V1.2 |
|----------|-----------|-----------|---------|
| U axis source | Raw NdotL × shadow | Raw NdotL × shadow | Raw NdotL × shadow (matches Jade/Avaturn) |
| U axis access | Direct (vertex → fragment NdotL) | Direct (vertex → fragment NdotL) | `GetMainLight(shadowCoord)` in fragment; `positionWS` passed as 5th arg to `ApplyNPREffect` |
| Light direction in specular | Yes (Blinn-Phong NdotH) | Yes (Blinn-Phong NdotH) | Yes (Blinn-Phong NdotH × shadow; `_MainLightPosition.xyz`, remapped to `_WorldSpaceLightPos0` for legacy CG) |
| V axis (depth) | `length(camPos - posWS)` | `length(camPos - posWS)` | `length(_WorldSpaceCameraPos - positionWS)` (identical formula) |
| V axis (curvature) | `ddx/ddy(normalWS)` | `ddx/ddy(normalWS)` | `ddx/ddy(normalWS)` |
| Normal Field Abstraction | Yes (`_UseAbstractNormals`, default **1**) | Yes (`_UseAbstractNormals`, default **1**) | No (normals received post-interpolation) |
| Rim Light | Yes (`_EnableRimLight` toggle) | Yes (`_EnableRimLight` toggle) | Yes (`_XToonEnableRim` ShaderToggle; child rows hidden when OFF) |
| Inline Sobel | Yes (`_EnableSobel` toggle) | Yes (`_EnableSobel` toggle) | Yes (`_XToonEnableSobel` ShaderToggle in `NPREffect_XToon.cginc`; child rows hidden when OFF) |
| Compute-skinning bridge | No (SkinnedMeshRenderer) | No (GLTFast SkinnedMeshRenderer, same as Jade) | Yes (SDK native) |
| Outline | Inverted hull (world-space) | Inverted hull (world-space) | Inverted hull (NPROutline pass, `_OutlineEnabled`) |
| Shadow Caster pass | No (fallback) | Yes (self-contained) | Yes (Meta SDK handles shadows) |
| Alpha blend for eyelash | Via `_ALPHA_BLEND` keyword | Via `_ALPHA_BLEND` keyword | Via Meta SDK material system |

---

### V1 vs V1.2 — Conceptual Differences

| Dimension | V1: Toon + Inverted Hull | V1.2: XToon 2D Ramp |
|-----------|--------------------------|-------------------|
| **Ramp dimensionality** | 1D (NdotL only) | 2D (NdotL × abstraction) |
| **Abstraction control** | None — same detail at every distance | Depth / curvature / manual V axis |
| **Band behaviour** | Fixed number of discrete bands | Bands widen and soften as V increases |
| **Normal handling** | Vertex normals only | Optional Normal Field Abstraction (abstract normal map) |
| **Artist control** | Steps, threshold, smoothness, shadow strength | Full 2D ramp texture + per-axis parameters |
| **Reference** | Standard real-time cel-shading (no specific paper) | Barla, Thollot & Markosian, NPAR 2006 |
| **Computational cost** | ~1 texture sample (albedo) | 1 ramp texture sample + optional inline Sobel (8 samples) |

The core advancement of V1.2 over V1 is the separation of *lighting response* (U) from *stylistic abstraction* (V). V1 applies the same level of detail uniformly; V1.2 can make nearby objects crisp and detailed while distant objects dissolve into broad abstract colour zones — a behaviour grounded in how illustrators vary line weight and detail with focal distance.

---

## In-VR Assessment UI — Design Notes

- **No `Canvas.ForceUpdateCanvases()`** — calling it rebuilds all canvases including internal Meta SDK UI, which triggers an IMGUI `EndLayoutGroup` error. Only the panel's own `RectTransform` is rebuilt with `LayoutRebuilder.ForceRebuildLayoutImmediate`.
- **Outline pass guard** — technique `.cginc` files are excluded from the `NPROutline` pass via `!defined(OUTLINE_PASS)` in `app_functions.hlsl`. Without this guard, the technique code was compiled into the outline pass even though it was never called, which caused Unity to silently skip the pass when certain technique keywords (e.g. `EFFECT_SOBEL`) were active.
- **Dependent rows** — rows are shown/hidden dynamically via a `dependsOnProp` field checked in `ResolveAllDependencies()`. Example: Blur Radius is only shown when Gauss Blur is ON.
- **Mode cycle button** — toggles between two display states on each press:
  1. **NPR ON** — `ENABLE_NPR_EDGES` enabled, outline pass enabled, current technique active
  2. **DEFAULT** — `ENABLE_NPR_EDGES` disabled, outline disabled; Meta's full `STYLE_2_STANDARD` PBR (rim light, SSS, hair)
- **Save / Load Preset buttons** — two clickable rows at the top of the panel (below Mode). **Save Preset** writes every float, ShaderToggle, and Color row value to `PlayerPrefs` (keys `NPR_{propName}` / `NPR_ci_{propName}`). **Load Preset** restores those values, updates slider visuals, and calls `SetShaderFloat`/`SetShaderColor` on all NPR materials. Button text changes to **✓ Saved** or **✓ Loaded** on activation so the researcher can confirm success without removing the headset.
- **Technique visibility** — only the parameter rows for the currently selected technique are shown; all others are hidden.
- **Toon darkening fix** — in the Toon family (Techniques 9–11), posterization must run **before** saturation. Applying saturation >1 before posterization can drive low RGB channels negative (clamped to 0 on output), causing the avatar to appear darker. The correct order is: quantize first, then scale saturation on the already-quantized colour.
- **Halftone/Hatching tone source** — both Techniques 12 and 13 derive "tone" from `luminance(o.color)` (the already-composited PBR colour), not from a separate NdotL computation. This means the pattern responds correctly to all PBR lighting including shadows, SSS, and ambient — without any additional light passes.

---

## Screen-Space Post-Process Renderer Features

Both the **Jade avatar (ShaderExperimental)** scene and the **Avaturn** scene share the same active URP pipeline: `URP_QUEST.asset` → `URP_QUEST_Renderer.asset`. Two screen-space passes are now registered in `URP_QUEST_Renderer.asset` as active `ScriptableRendererFeature`s:

| Feature class | Script | Shader |
|---|---|---|
| `KuwaharaFilterFeature` | `Assets/AvatarShaderExperimental/Scripts/Rendering/KuwaharaFilterFeature.cs` | `Assets/Shaders/JadeNPRShaders/AnisotropicKuwahara.shader` |
| `EdgeDetectionFeature` | `Assets/AvatarShaderExperimental/Scripts/Rendering/EdgeDetectionFeature.cs` | `Assets/Shaders/JadeNPRShaders/HierarchicalEdgeDetection.shader` |

Both run at `RenderPassEvent.AfterRenderingTransparents` (event 550), with `avatarLayer: 0` (full-screen, no masking). `URP_QUEST.asset` has `m_RequireDepthTexture: 1` and `m_RequireOpaqueTexture: 1` enabled to supply the depth and normal buffers that `EdgeDetectionFeature` samples.

### Kuwahara Filter Feature

3-pass anisotropic Kuwahara (oil-paint abstraction):

| Pass | Name | Action |
|------|------|--------|
| 0 | StructureTensor | Sobel on luminance → packs `(gx², gx·gy, gy²)` into RGB |
| 1 | TensorBlur | Separable Gaussian smooths the tensor field (H then V) |
| 2 | KuwaharaFilter | Anisotropic sector-weighted mean per pixel |
| 3 | MaskedComposite | Blends effect over avatar silhouette (only when `avatarLayer ≠ 0`) |

Default settings: `kernelSize=4`, `sectorCount=8`, `sharpness=8`, `hardness=8`, `zeroCrossing=0.58`.

### Edge Detection Feature

Screen-space hierarchical edge detection that combines depth, normal, and colour differentials:

| Property | Default | Effect |
|----------|---------|--------|
| `depthThreshold` | 0.5 | World-space depth jump that counts as an edge |
| `normalThreshold` | 0.4 | Normal-angle delta that counts as an edge |
| `colorThreshold` | 0.15 | Colour delta that counts as an edge |
| `depthWeight / normalWeight / colorWeight` | 1 / 1 / 0.5 | Per-layer blend weights |
| `edgeWidth` | 1 | Sampling offset multiplier |
| `adaptiveStrength` | 0.5 | How much edges fade on bright areas |

Requests `ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal` so Unity allocates the normals texture automatically.

### Why these features are NOT applied to the MetaAvatar scene

Two architectural reasons rule this out:

1. **Frame scope** — a `ScriptableRendererFeature` blit operates on the entire camera frame. Applied to the MetaAvatar scene, it would stylise all scene content (walls, floor, props), not just the avatar. Scoping to the avatar alone would require an extra masking render pass (`AvatarMaskCapture.shader` exists for this purpose but adds pipeline complexity).

2. **Quest VR performance** — each Renderer Feature adds a full-resolution blit pass that must be evaluated independently for both eye buffers in stereo. For a computationally intensive effect like the multi-pass Kuwahara or the depth+normals edge detection, this exceeds the acceptable GPU budget on Quest hardware.

The MetaAvatar shader instead implements per-object adaptations of both techniques (`NPREffect_Kuwahara2.cginc` via `EFFECT_KUWAHARA`, `NPREffect_Hierarchical.cginc` via `EFFECT_HIERARCHICAL`) that run inside the `AppSpecificPostManipulation` hook — avatar-scoped, zero extra passes, same artistic intent.

**Jade and Avaturn shader identity:** Both `JadeNPRShaders/AnisotropicKuwahara.shader` and `AvaturnNPRShaders/AnisotropicKuwahara.shader` are algorithmically identical (same 4 passes, same eigendecomposition, same sector blending). The two `HierarchicalEdgeDetection.shader` files are also identical in algorithm. The Avaturn version adds a `SAMPLER(sampler_AvatarMask)` declaration missing from Jade but the detection logic is unchanged.

---

## Avaturn Avatar Animation (Mixamo)

### How it works

Avaturn avatars are loaded from a `.glb` file at runtime by GLTFast. Because the GLB skeleton has no Humanoid Avatar baked in, Mixamo animations (which are **Humanoid** rig type) cannot retarget onto it by default — the Animator silently falls back to Generic mode and the character stands still.

`AvaturnAnimationPrepare.cs` fixes this at runtime:

1. **Finds all skeleton roots** — recursively searches for every Transform whose direct child is `Hips` / `mixamorig:Hips`. Works regardless of nesting depth or how many GLTFast wrapper nodes exist. **Works with both a single avatar and a parent that holds many avatars** — attach it once to a parent to animate all children at once.
2. **Builds a Humanoid Avatar per skeleton** — calls `AvatarBuilder.BuildHumanAvatar()` with a `HumanDescription` mapping all 55 Humanoid slots to both Avaturn naming variants. The T-pose snapshot is taken from the GLTFast-loaded transforms.
3. **Wires up the Animator** — walks top-down from the script's GameObject to each skeleton root, reusing the first Animator found (picks up existing prefab-instance Animators with controllers already assigned). Falls back to creating one on the skeleton root if none exists.

No external packages are required (the old BKUnity approach has been removed).

### Animator Controller

`Assets/Animations/Avaturn Animator.controller` — single state: **Breathing Idle** (loops).  
Animations: `Assets/Animations/Breathing Idle.anim` / `Standing Idle.anim` (extracted from Humanoid FBXs).

### Setup in scene

| GameObject | Component | Setting |
|---|---|---|
| `MainAvatar` | `AvaturnAnimationPrepare` | `Animator Controller` → *Avaturn Animator* |
| `MainAvatar` child 0 | Avaturn `.glb` prefab | (no extra setup needed) |

Press Play — you should see the Breathing Idle animation retargeted onto the avatar.

---

## Standalone Avaturn Avatar Shaders

These are standalone URP shaders (not integrated into the Meta Avatar SDK pipeline) designed for the Avaturn `.glb` avatar model. They run on separate GameObjects/prefabs in the scene alongside the Meta Avatar, providing additional NPR comparison points.

All standalone Avaturn shaders share the same three-pass structure:
1. **OuterOutline** — inverted-hull silhouette (Cull Front), outputs flat `_OuterOutlineColor`
2. **ForwardLit** — main shading pass with normal map TBN (where applicable), toon shading, and NPR edge effects
3. **DepthNormals** — writes bump-map-perturbed normals into URP's `_CameraNormalsTexture` so post-process edge shaders see normal-map detail

V3 and V3.2 are structurally identical in their Unity shader parts: same Properties headers and naming, same v2f struct (`viewDirWS` interpolated), same HLSL uniform declarations, same debug-override pattern (local variable copies), and same master toggles (`_EnableRim`, `_EnableOuterOutline`, `_DebugView`). The only intentional difference is the edge-detection algorithm — V3 uses a simple `step()`-based Sobel; V3.2 adds Gaussian pre-blur, a progressive smoothstep pipeline, normal edges, and Fresnel edges.

**Base shading (V1.2–V3.2):** All shaders from V1.2 onward replaced the V1 stepped-NdotL toon base with a **XToon 2D ramp** — the same ramp approach used by the dedicated XToon shader (VXT) and the Meta `EFFECT_XTOON` cginc. The stepped-toon properties (`_ToonSteps`, `_ToonThreshold`, `_ToonSmoothness`, `_EnableToonShading`) have been removed. V2–V5 now expose: `_ToonRamp` (2D), `_LightSensitivity`, `_RampSmoothing`, `_ShadowColor`, `_ShadowStrength`, `_DetailMode` (Depth/Curvature/Manual keyword enum), `_DetailBias`, `_DepthNear`, `_DepthFar`, `_ManualDetail`. The `#pragma shader_feature_local _DETAILMODE_DEPTH _DETAILMODE_CURVATURE _DETAILMODE_MANUAL` is added to each ForwardLit pass.

### V3 — Sobel Edge Detection
**Avaturn file:** `Assets/Shaders/AvaturnNPRShaders/V3_SobelEdgeDetection.shader`
**Jade file:** `Assets/Shaders/JadeNPRShaders/V3_SobelEdgeDetection.shader`
**Shader GUID:** `ac2e5c7f0a193458e8f848fd6528ee42`

Toon shading (stepped NdotL, toggleable via `_EnableToonShading`) with simple 3×3 UV-space Sobel edge detection using a single `step()` threshold — no Gaussian pre-blur. V3 is the baseline for comparing blur's noise-suppression benefit against V3.2.

**Avaturn-specific additions (not present in Jade):** Normal map (`_BumpMap` / `_BumpScale`) decoded via TBN matrix; DepthNormals pass writes bump-perturbed normals to `_CameraNormalsTexture` for screen-space post-process edge shaders.

**Structural alignment with V3.2:** Both V3 and V3.2 now share identical Properties headers, struct layout (`viewDirWS` in v2f), HLSL uniform declarations, debug override pattern (local variable copies), and toggle checks (`_EnableToonShading`, `_EnableRim`, `_EnableOuterOutline`, `_DebugView`). The only intentional difference is the edge-detection algorithm.

| Property | Description |
|----------|-------------|
| `_InnerLineThreshold` | Minimum Sobel magnitude to draw an edge |
| `_InnerLineBlur` | UV offset multiplier for the 3×3 kernel |
| `_InnerLineStrength` | Edge opacity |
| `_EnableInnerLines` | Toggle Sobel detection on/off |
| `_EnableToonShading` | Switch between stepped toon (on) and flat diffuse (off) |
| `_EnableRim` | Toggle rim lighting |
| `_EnableOuterOutline` | Toggle inverted-hull outline |
| `_DebugView` | 0=Final, 1=RawSobel (enum, mirrors V3.2) |
| `_BumpMap` / `_BumpScale` | Normal map (Avaturn only) |

**Materials:** `Assets/Materials/NPR Avaturn Materials/V3 SobelEdgeDetection/`

---

### V3.2 — Gaussian Pre-filtered Sobel
**Avaturn file:** `Assets/Shaders/AvaturnNPRShaders/V4_GaussianPreFilteredSobel.shader`
**Jade file:** `Assets/Shaders/JadeNPRShaders/V4_GaussianPreFilteredSobel.shader`
**Shader GUID:** `[assigned by Unity on import]`

V3 extended with a 9-tap Gaussian pre-blur applied to each of the 8 Sobel sample positions before the gradient is computed. Reduces false edges from high-frequency texture noise. Also supports screen-space normal edge detection (`_EnableNormalEdges`, via `ddx`/`ddy` of world normals) and Fresnel silhouette edge (`_EnableFresnelEdge`).

**Structural alignment with V3:** V3.2 now includes `_BumpMap` / `_BumpScale` normal map support and a DepthNormals pass (both added to match V3 Avaturn). The normal edge detection in V3.2 (`ddx`/`ddy` of `nWS`) now benefits from bump-map detail because `nWS` is decoded through the TBN matrix before the derivatives are computed.

| Property | Description |
|----------|-------------|
| `_BumpMap` / `_BumpScale` | Normal map, decoded via TBN (added to match V3) |
| `_EnableTextureSobel` | Toggle Gaussian Sobel pipeline |
| `_EnableNormalEdges` | Toggle screen-space normal edge (`ddx`/`ddy` of `nWS`) |
| `_EnableFresnelEdge` | Toggle Fresnel silhouette edge |
| `_EnableGaussianBlur` | Toggle 9-tap Gaussian pre-blur on each Sobel sample |
| `_BlurRadiusMultiplier` | Gaussian blur radius relative to `_InnerLineBlur` |
| `_InnerLineThreshold` / `_InnerLineBlur` / `_InnerLineStrength` | Sobel parameters (same names as V3) |

**Materials:** `Assets/Materials/NPR Avaturn Materials/V3.2 GaussianPreFilteredSobel/`

---

### V5 — Hierarchical Edge Detection with Gaussian Pre-blur
**Avaturn file:** `Assets/Shaders/AvaturnNPRShaders/V5_HierarchicalGaussian.shader`
**Jade file:** `Assets/Shaders/JadeNPRShaders/V5_HierarchicalGaussian.shader`
**Shader name:** `Custom/Avaturn_V5_HierarchicalGaussian`

Three-layer hierarchical edge detection where the color layer applies a 9-tap Gaussian pre-blur to each Roberts Cross sample before computing the gradient. Same algorithm as the Jade `V5_HierarchicalGaussian.shader` with the additions of a normal map (TBN) in ForwardLit and a DepthNormals pass.

**Layers:**
1. **Depth** — `ddx/ddy` of camera-distance proxy → smoothstep threshold
2. **Normal** — `ddx/ddy` of world-space normal (normal-map-perturbed via TBN) → smoothstep threshold
3. **Color** — 4-tap Roberts Cross on texture luminance; each tap optionally pre-blurred with a configurable 9-tap Gaussian kernel

**Fusion:** `max(depth × depthWeight, normal × normalWeight, color × colorWeight)` with per-pixel adaptive brightness suppression.

**Passes:** OuterOutline (inverted hull) + ForwardLit + DepthNormals

| Key Property | Default | Effect |
|---|---|---|
| `_EnableGaussBlur` | 1 (on) | Toggles 9-tap Gaussian preblur on color Roberts Cross samples |
| `_HBlurRadius` | 0.5 | Gaussian kernel radius (×0.001 UV units) |
| `_HEdgeWidth` | 1.0 | Roberts Cross sample offset (×0.001 UV units) |
| `_HDepthThreshold / Weight` | 0.05 / 1.0 | Depth layer threshold and contribution |
| `_HNormalThreshold / Weight` | 0.3 / 1.0 | Normal layer threshold and contribution |
| `_HColorThreshold / Weight` | 0.1 / 0.5 | Color layer threshold and contribution |
| `_HAdaptiveStrength` | 0.5 | Brightness-based suppression of edges on highlights |
| `_EnableRim` | 1 (on) | Toggle rim lighting (default ON) |
| `_RimColor` | (0.408,0.408,0.408,1) | Rim tint colour |
| `_RimPower` | 3.0 | Rim falloff exponent |

**Rim lighting:** Both Jody and Avaturn V5 compute `pow(1 - saturate(N·V), _RimPower) * _RimColor`, added to `shaded` after ambient and before edge overlay. Controlled by `_EnableRim` toggle (default ON). Jody V5 was missing rim lighting prior to this session; it has now been added to match Avaturn V5.

**Materials:** `Assets/Materials/NPR Avaturn Materials/V5 HierarchicalGaussian/` *(create folder and materials in Unity)*

---

### V8 — Quantized Colour + Dual Sobel (UV-space Normal-map Sobel)
**File:** `Assets/Shaders/AvaturnNPRShaders/V8_QuantizedSobel.shader` (Avaturn only)
**Shader GUID:** `e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6`

Most abstract standalone shader. Three-stage pipeline:

**Stage 1 — Colour quantization (posterisation):**
```hlsl
float3 Quantize(float3 col, float steps) {
    return floor(col * steps + 0.5) / steps;
}
```
Reduces the albedo to `_QuantizeSteps` discrete colour levels before any edge detection runs. Catches eyebrow, lip, and skin-tone region transitions at colour-region boundaries.

**Stage 2 — Texture Sobel (optional, `_EnableTexSobel`):**
Standard 3×3 luminance Sobel on the **quantized** albedo. Fires at colour-region boundaries introduced by posterisation.

**Stage 3 — Normal-map Sobel in UV-space (optional, `_EnableNormSobel`):**
Samples `_BumpMap.xy` at 8 UV offsets and computes a 2-channel Sobel:
```hlsl
float2 sobelX = (tr+2.0*r+br) - (tl+2.0*l+bl);
float2 sobelY = (tl+2.0*t+tr) - (bl+2.0*b+br);
float edgeMag = sqrt(dot(sobelX,sobelX)+dot(sobelY,sobelY));
```
This is **view-independent** — it fires on ridges baked into the normal map (eyebrow arch, lip crease, eyelid fold) regardless of camera angle. No screen-space derivatives.

Both edge signals are max-combined and composited over the quantized shaded colour.

| Property Group | Key Properties |
|---------------|----------------|
| Quantization | `_QuantizeSteps` (2–32) |
| Texture Sobel | `_EnableTexSobel`, `_TexEdgeThreshold`, `_TexEdgeSampleDist`, `_TexEdgeStrength`, `_TexEdgeColor` |
| Normal Sobel | `_EnableNormSobel`, `_NormEdgeThreshold`, `_NormEdgeSampleDist`, `_NormEdgeStrength`, `_NormEdgeColor` |
| Outline | `_OuterOutlineWidth`, `_OuterOutlineColor` |

**Materials:** `Assets/Materials/NPR Avaturn Materials/V8 QuantizedSobel/`
- `V8_body.mat` — body texture, both Sobel channels enabled, outline on
- `V8_head.mat` — head texture, both Sobel channels enabled, outline on
- `V8_hair.mat` — hair texture (fileID `7653646275262004549`), both channels enabled
- `V8_eyelash.mat` — eyelash texture, alpha test enabled, Sobel off, no outline
- `V8_look.mat` — eye texture, Sobel off, no outline (eyes should read cleanly)

---

### VHH / V4 — Halftone & Hatching
**Thesis version:** V4 — Halftone Screening and Cross-Hatching
**Shared file:** `Assets/Shaders/CommonNPRShaders/HalftoneHatching.shader` (used by both Jody/Mixamo and Avaturn)
**Shader GUID:** `452f01b8804f54c8eb77c3425cf4614f`
**Meta SDK hooks:** `NPREffect_Halftone.cginc` (Technique 12) + `NPREffect_Hatching.cginc` (Technique 13)

Standalone URP shader that applies either a halftone dot grid, cross-hatching lines, stippling, or a combination — all driven by lighting intensity. Four `shader_feature_local` keyword groups select the active mode at material import time; the float property (`_PatternMode`) stores the selection (0 = Halftone, 1 = Hatching, 2 = Stipple, 3 = Combined).

#### Bug fixes applied 2026-06-05 (two-patch update)

**Patch 1 — safety guards (initial)**

`HalftonePattern` was updated to match the guards already present in `NPREffect_Halftone.cginc`:

```hlsl
// Before
float dotRadius = sqrt(1.0 - tone) * 0.5;
float pattern = 1.0 - smoothstep(dotRadius - 0.5 / _HalftoneSharpness,
                                  dotRadius + 0.5 / _HalftoneSharpness, dist);

// After
float dotRadius = sqrt(max(0.0, 1.0 - tone)) * 0.5;
float sharpInv = 0.5 / max(_HalftoneSharpness, 0.001);
float pattern = 1.0 - smoothstep(dotRadius - sharpInv,
                                  dotRadius + sharpInv, dist);
```

`max(0.0, ...)` prevents NaN from `sqrt` when tone overshoots 1.0 (possible with high `_ToneBias`). `max(..., 0.001)` prevents divide-by-zero when `_HalftoneSharpness` is set to 0 in the Inspector.

**Patch 2 — zero-dotRadius ink artifact + _ToneLevels dead-code fix (revised)**

Two bugs caused uniform-looking dots. A third bug was introduced by the initial Patch 2 and corrected immediately.

*Bug A: zero-dotRadius smoothstep artifact (fixed, retained).* When `tone = 1` (fully lit), `dotRadius = 0`. `smoothstep(-sharpInv, +sharpInv, 0)` evaluates to `0.5`, so `pattern = 0.5` — faint ink appeared at the grid centre even in bright highlights. Fix: an early-return guard suppresses the dot when `dotRadius < sharpInv`.

```hlsl
float dotRadius = sqrt(max(0.0, 1.0 - tone)) * 0.5;
float sharpInv  = 0.5 / max(_HalftoneSharpness, 0.001);
if (dotRadius < sharpInv) return 0.0;   // fully-lit cell: pure paper
float pattern = 1.0 - smoothstep(dotRadius - sharpInv,
                                  dotRadius + sharpInv, dist);
```

*Bug B: `_ToneLevels` dead code + incorrect quantisation (corrected).* The original code had `float levels = _ToneLevels;` in `HatchingPattern()` that was never used — thresholds were hardcoded. The initial fix mistakenly applied tone quantisation in `frag()` before calling pattern functions. This was wrong: Praun 2001 uses **continuous tone interpolation between TAM levels**, not discrete snapping. The quantisation mapped any `tone > 0.83` (with 5 levels) to `1.0`, which triggered the zero-dotRadius guard and produced a large stark-white region on the avatar — the visual "white placed on top of dots" artefact.

**Correct fix:** `_ToneLevels` drives the hatch-layer threshold spacing. Thresholds are at `k / _ToneLevels` for k = 1…N-1, with continuous `smoothstep` blending over one step width — matching Praun's TAM interpolation between adjacent levels. Tone is never quantised; it remains a continuous NdotL × shadow value passed directly to the pattern functions.

**Patch 3 — PBR luminance ceiling + Meta SDK tone normalisation (2026-06-05)**

*Root cause.* Both the standalone shader (`NdotL`-based, `lerp(0.5, tone, _LightingInfluence)` clamp) and the Meta SDK hooks (luminance of composited PBR colour) suffer a luminance ceiling: the maximum achievable tone value is below 1.0. For the standalone shader with default `_LightingInfluence = 0.75`, full `NdotL = 1` yields `tone = 0.875`, not 1.0. For the Meta SDK hooks, dark-albedo skin or clothing (luminance ≈ 0.5–0.75 at full light) means `tone` never reaches 1.0. In both cases `t = 1 − tone > 0` always, so Layer 1 marks activate everywhere including fully-lit highlights — the "uniform hatching" artefact.

*Fix — standalone shader (`HalftoneHatching.shader`).* Added `_ToneWhitePoint` (Range 0.1–1.0, default 1.0). Applied after the `_LightingInfluence` lerp:
```hlsl
tone = saturate(tone / max(_ToneWhitePoint, 0.001));
```
At default 1.0 the remapping is identity (backward compatible). Setting `_ToneWhitePoint = 0.875` with `_LightingInfluence = 0.75` restores a pure-paper highlight zone at full NdotL.

*Fix — Meta SDK hatching hook (`NPREffect_Hatching.cginc`).* Replaced hardcoded thresholds with `_HatToneLevels`-driven spacing (matching the standalone shader). Added `_HatToneWhitePoint` (default 0.75):
```hlsl
tone = saturate(lum / max(_HatToneWhitePoint, 0.001) + _HatToneBias);
```
For a material whose peak lit luminance is 0.75, `lum / 0.75 = 1.0` → `t = 0.0` → pure paper. Darker regions remap proportionally, preserving the full tonal range below the white point.

*Fix — Meta SDK halftone hook (`NPREffect_Halftone.cginc`).* Same `_HTToneWhitePoint` normalisation applied to the dot-radius luminance lookup. Additionally ported the `visibility` ramp from the standalone shader — this was missing in the original cginc, causing the zero-dotRadius smoothstep artefact (faint ink at every grid centre when `tone = 1.0`) to persist even before the white-point fix was needed.

*Calibration guideline.* Set `_HatToneWhitePoint` / `_HTToneWhitePoint` to the luminance observed on the most-lit surface pixel of that material under the scene's key light. Skin under neutral white light: ≈ 0.60–0.75. Light clothing: ≈ 0.70–0.85. Dark clothing: ≈ 0.25–0.45. A too-low white point produces a very large blank highlight zone; a too-high value leaves marks in highlights.

**Patch 4 — absolute TAM thresholds + direct NdotL tone computation (2026-06-06)**

*Root cause.* The `_BrightCutoff` range-remap formula `t = saturate((t − C) / (1 − C))` with default `C = 0.4` had two compounding problems:

1. **Compressed transitions.** All four layer transitions were squeezed into `tone < 0.6`. In typical 3D scenes most surface pixels have `tone > 0.4` (moderate-to-bright), so they received zero pattern. Shadow regions still existed but the layers were jammed into a narrow dark zone with 0.1-tone-unit transition windows — visually indistinguishable from each other.

2. **Dynamic thresholds amplified the problem.** With `_ToneLevels = 6`, `step = 1/6`. Layer 1 started at remapped `t > 0.167`, which requires raw `t > 0.5` (`tone < 0.5`). Only the darkest half of the avatar showed any marks at all. The fill layer needed raw `t > 0.9` (`tone < 0.1`) — nearly invisible in practice.

*Fix — `HalftoneHatching.shader` (standalone, all three pattern modes):* Remove the remap entirely. Use the working experimental shader's absolute thresholds directly on raw `t = 1 − tone`:

```hlsl
// Halftone: natural sqrt scaling — no explicit cutoff needed
float t = max(0.0, 1.0 - tone);
float dotRadius = sqrt(t) * 0.5;  // bright (t=0) → no dot; dark (t=1) → full cell

// Hatching: absolute layer thresholds spread across full tonal range
float t = 1.0 - tone;
if (t > 0.15) pattern = max(pattern, HatchLine(...) * smoothstep(0.15, 0.40, t));  // Layer 1
if (t > 0.35) pattern = max(pattern, HatchLine(...) * smoothstep(0.35, 0.60, t));  // Layer 2
if (t > 0.55) pattern = max(pattern, HatchLine(...) * smoothstep(0.55, 0.80, t));  // Layer 3
if (t > 0.80) pattern = max(pattern, smoothstep(0.80, 1.0, t));                    // Layer 4 fill
```

*Fix — `NPREffect_Hatching.cginc` (Meta SDK hook):* Same absolute thresholds. `_HatToneWhitePoint` normalisation already maps peak PBR luminance → `tone = 1.0`, so the absolute thresholds cover the full tonal range correctly.

*Fix — `NPREffect_Halftone.cginc` (Meta SDK hook):* Replace `(t − _HTBrightCutoff) / (1 − _HTBrightCutoff)` remap with plain `t = max(0.0, 1.0 − tone)`. The `_HTToneWhitePoint` normalisation already ensures bright pixels reach `tone ≈ 1.0` and `dotRadius ≈ 0`.

*Fix — tone computation in `HalftoneHatching.shader`:* The ambient SH + `lerp(0.5, tone, _LightingInfluence)` pipeline that was inherited from earlier shader versions compressed the tone range into ~[0.125, 0.875]. This left less than half the tonal range available for progressive layers. As of Patch 4 this was simplified to `tone = saturate(NdotL * shadow + _ToneBias)` to restore the full [0, 1] range. `_LightingInfluence`, `_ToneWhitePoint`, and `_BrightCutoff` remained declared but inactive in Patch 4 — see Patch 5 below for their proper implementation.

**Patch 5 — `_BrightCutoff` wired up in GUI and Meta SDK includes (2026-06-06)**

*Root cause.* `_BrightCutoff` was declared in Properties and CBUFFER but never applied in the fragment stage, and was missing from `HalftoneHatchingGUI`'s default/debug preset maps. The `_LightingInfluence` and `_ToneWhitePoint` are declared for GUI/preset compatibility only and intentionally NOT applied in the fragment — they were surfaced so artist-tuned material values survive preset round-trips without corrupting other properties.

*Fix — `HalftoneHatching.shader` BrightCutoff:*
```hlsl
// _BrightCutoff: suppress pattern in the well-lit hatch-free zone
pattern *= 1.0 - smoothstep(_BrightCutoff - 0.05, _BrightCutoff + 0.05, tone);
```

*Fix — `NPREffect_Halftone.cginc` and `NPREffect_Hatching.cginc`:* `_HTBrightCutoff` / `_HatBrightCutoff` applied identically after `HT_HalftonePattern` / `Hat_HatchingPattern` returns.

*Fix — `HalftoneHatchingGUI.cs`:* `_BrightCutoff` (default 0.4) added to `DefaultFloats`; `_BrightCutoff` (0.9, wide open for debug) added to `DebugFloats`.

**Patch 6 — Normal map decode corrected + shader aligned with working standalone (2026-06-07)**

*Root cause — inverted halftone pattern.* After applying V4 materials, dots appeared on the lit centre of the face and were absent on the shadowed edges — the opposite of correct halftone behaviour. `HalftoneHatching.shader` had been updated to use `UnpackNormalScale()` (Unity DXT5nm decode). On DX11 / PC this reads the **alpha channel for X** and reconstructs Z; for a texture without a packed alpha, X collapses to 1.0 on every fragment, producing a world-space normal that always points in +X regardless of surface orientation. The wrong NdotL values caused the shadow side to read as lit and the lit side to read as dark, directly inverting the halftone pattern.

Both V4 Jade and V4 Avaturn materials reference the same normal map (GUID `8c8eedd0915724818be4399b70dba86a`), which is a **raw RGB** texture imported via GLTFast — it must be decoded as `rgb * 2.0 - 1.0`, not via DXT5nm.

Fix — `HalftoneHatching.shader` ForwardLit pass:

```hlsl
#if defined(_NORMALMAP)
// Raw-RGB normal map (GLTFast / Avaturn convention) — decode as plain RGB.
// UnpackNormalScale reads the alpha channel for X on DX11 (DXT5nm), which
// produces X≈1 for any texture without a packed alpha → wrong NdotL.
float4 bumpSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap,
                        TRANSFORM_TEX(input.uv, _BumpMap));
float3 normalTS = bumpSample.rgb * 2.0 - 1.0;
normalTS.xy    *= _BumpScale;
normalTS        = normalize(normalTS);
float3x3 TBN = float3x3(normalize(input.tangentWS),
                        normalize(input.bitangentWS),
                        normalWS);
normalWS = normalize(mul(normalTS, TBN));
#endif
```

Same change applied to the DepthNormals pass. Tone formula remains the simple direct form `tone = saturate(NdotL * shadow + _ToneBias)` from the working standalone shader.

#### Core algorithms

**Halftone dot grid — all three platforms:**
```hlsl
// Standalone (Jody / Avaturn): tone = saturate(lerp(1.0, NdotL × shadow, _LightingInfluence) + _ToneBias)
//                              then:  tone = saturate(tone / _ToneWhitePoint)
// Meta SDK:                    tone = saturate(luminance(PBR_composite) / _HTToneWhitePoint + _HTToneBias)
t         = max(0.0, 1.0 - tone)                                   // darkness: 0=lit, 1=dark
dotRadius = sqrt(t) × 0.5                                          // area ∝ darkness (photomechanical)
sharpInv  = 0.5 / max(_HalftoneSharpness, 0.001)
visibility = smoothstep(0, 2×sharpInv, dotRadius)                  // suppress near-zero artifact
pattern   = (1 − smoothstep(dotRadius − sharpInv, dotRadius + sharpInv, dist)) × visibility
```

Expected: highlights → no dots (tone=1 → dotRadius=0), midtones → medium dots, shadows → large dots.

**TAM hatching (Praun et al. 2001) — absolute thresholds, all three platforms:**
```hlsl
t = 1.0 - tone   // darkness (0=lit, 1=dark)

Layer 1 at t > 0.15:  primary lines    × smoothstep(0.15, 0.40, t)
Layer 2 at t > 0.35:  cross hatch      × smoothstep(0.35, 0.60, t)
Layer 3 at t > 0.55:  dense diagonal   × smoothstep(0.55, 0.80, t)  [thickness × 1.5]
Layer 4 at t > 0.80:  near-black fill  = smoothstep(0.80, 1.00, t)
pattern = max across active layers
```

Tonal distribution:
- Highlight (tone > 0.85, t < 0.15): pure paper, no marks
- Light shadow (t ≈ 0.25): sparse single-direction lines appear
- Mid shadow (t ≈ 0.50): cross-hatch adds density
- Deep shadow (t ≈ 0.70): dense diagonal fills gaps
- Near-black (t > 0.80): near-solid ink fill

**Colour model (identical across all three avatar platforms):**
```
paperCol     = lerp(PaperColor, PBRcolor, TextureInfluence)
inkCol       = lerp(InkColor,   PBRcolor × InkColor, TextureInfluence)
patternColor = lerp(paperCol, inkCol, pattern)
finalColor   = lerp(PBRcolor, patternColor, Strength)
```

#### Cross-avatar platform comparison

| Dimension | Jody (Mixamo) | Avaturn | Meta Avatar SDK |
|-----------|--------------|---------|-----------------|
| Shader file | `CommonNPRShaders/HalftoneHatching.shader` | `CommonNPRShaders/HalftoneHatching.shader` | `NPREffect_Halftone.cginc` + `NPREffect_Hatching.cginc` |
| Tone derivation | `saturate(NdotL × shadow + _ToneBias)` | `saturate(NdotL × shadow + _ToneBias)` | `saturate(luminance(PBR_composite) / _HTToneWhitePoint + _HTToneBias)` |
| Coordinate modes | ScreenSpace / ObjectSpace (UV) / WorldSpace | ScreenSpace / ObjectSpace (UV) / WorldSpace | UV-space only |
| OVR skinning bridge | No (standard SkinnedMeshRenderer) | No (GLTFast SkinnedMeshRenderer) | SDK-native |
| Normal map decode | `rgb × 2.0 - 1.0` (GLTFast; incorrect for Jody FBX if `_NORMALMAP` enabled) | `rgb × 2.0 - 1.0` (GLTFast, correct) | N/A (hook receives post-PBR colour) |
| Property prefix | `_Halftone*` / `_Hatch*` | `_Halftone*` / `_Hatch*` | `_HT*` (halftone) / `_Hat*` (hatching) |
| Outline pass | Built-in inverted hull | Built-in inverted hull | Shared `NPROutline` pass (`_OutlineEnabled`) |

**Tone source note:** The Meta SDK hook runs inside `AppSpecificPostManipulation` after all PBR lighting (NdotL, shadows, SSS, ambient, rim) has been composited. Raw NdotL is no longer accessible, so luminance of the composite colour is used instead. The standalone shaders compute NdotL directly in the ForwardLit pass and multiply by URP shadow attenuation. Both approaches capture the same perceptual darkness signal, but the Meta version includes PBR complexity (SSS, rim, ambient) that the standalone NdotL-based version does not.

**Normal map decode note:** `HalftoneHatching.shader` decodes the bump map as `sample.rgb * 2.0 - 1.0` (raw RGB, GLTFast/glTF convention). This is correct for the Avaturn GLB loaded via GLTFast. Jody (Mixamo) is an FBX imported through Unity's standard importer, which expects `UnpackNormalScale()`. If `_NORMALMAP` is enabled on Jody materials using this shared shader, normals will decode incorrectly and produce a grey artifact. In practice the halftone/hatching effect is nearly tone-only so the artefact is subtle, but the limitation is noted.

#### Properties

Uses `_BaseMap` (not `_MainTex`) for the albedo. Has a built-in inverted-hull outline pass.

| Property | Description |
|----------|-------------|
| `_PatternMode` | 0=Halftone, 1=Hatching, 2=Stipple, 3=Combined |
| `_HalftoneScale` / `_HalftoneSharpness` / `_HalftoneAngle` | Dot grid parameters |
| `_HatchScale` / `_HatchAngle` / `_HatchThickness` / `_CrossHatchAngle` | Line parameters |
| `_LightingInfluence` | Blends between flat (0 → tone always 1.0, no pattern) and full NdotL shadow response (1 → tone = NdotL × shadow). Formula: `lerp(1.0, NdotL × shadow, _LightingInfluence)`. Default **0.75**. |
| `_ToneLevels` | Hatch layer count; default **6** matching Praun 2001's 6 TAM columns |
| `_ToneWhitePoint` | Peak NdotL tone remapped to 1.0 (pure paper); compensates for `_LightingInfluence < 1` clamping max tone below 1.0 — lower to widen the hatch-free highlight zone; default **1.0** (no remap, backward compatible) |
| `_ToneBias` | Additional tone offset (positive = lighter overall, simulates extra ambient) |
| `_BrightCutoff` | Suppress pattern in the well-lit hatch-free zone. Applied after all pattern modes via `pattern *= 1 − smoothstep(C−0.05, C+0.05, tone)`. Default **0.4** (pattern only where tone < 0.45). Set to 0.9+ to allow pattern across nearly the full tonal range. Meta SDK equivalents `_HTBrightCutoff` / `_HatBrightCutoff` apply identically in their respective cginc hooks. |
| `_InkColor` / `_PaperColor` / `_TextureInfluence` | Colour model |
| `_OutlineWidth` / `_OutlineColor` | Built-in silhouette outline |
| `_AlphaCutoff` + `_ALPHATEST_ON` keyword | Alpha test for eyelash material |

**Avaturn V4 materials** (thesis-canonical naming, matching V3/V5 folder convention):
`Assets/Materials/NPR Avaturn Materials/V4 HalftoneHatching/`
- `V4_body.mat` — body texture from Avaturn GLB, Halftone/ObjectSpace, outline on
- `V4_head.mat` — head texture, Halftone/ObjectSpace, outline on
- `V4_hair.mat` — hair texture, Halftone/ObjectSpace, outline on
- `V4_eyelash.mat` — eyelash texture, `_ALPHATEST_ON`, `_AlphaCutoff: 0.07`, no outline
- `V4_look.mat` — eye texture, Halftone/ObjectSpace, no outline

**Jody (Mixamo) V4 materials** (consistent naming):
`Assets/AvatarShaderExperimental/Materials/V4 HalftoneHatching/`
- `V4_body.mat` — body texture + normal map (`_NORMALMAP`), Halftone/ObjectSpace, outline on
- `V4_clothing.mat` — clothing texture + normal map, Halftone/ObjectSpace, outline on
- `V4_hair.mat` — hair texture + normal map, `_ALPHATEST_ON`, `_AlphaCutoff: 0.07`, no outline
- `V4_eyelash.mat` — eyelash texture + normal map, `_ALPHATEST_ON`, `_AlphaCutoff: 0.07`, no outline

**Legacy VHH materials** (also fixed):
`Assets/Materials/NPR Avaturn Materials/VHH HalftoneHatching/`
- All five VHH_*.mat files updated: shader GUID corrected to `937be21d7640a4690a1dd9ebc159ba35`, `_HALFTONESPACE_OBJECTSPACE` / `_HATCHSTYLE_LINE` / `_PATTERNMODE_HALFTONE` keywords added. These may remain in scenes that were previously configured; use V4_* materials for new work.

**Consistent parameters across all V4 materials:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| `_HalftoneScale` | 30 | Medium dot density |
| `_HalftoneSharpness` | 10 | Crisp dots |
| `_HalftoneAngle` | 45° | Standard halftone screen angle |
| `_HalftoneSpace` | 1 (ObjectSpace/UV) | Stable on avatar rotation |
| `_HatchScale` | 20 | Line frequency |
| `_HatchAngle` | 45° | Primary line direction |
| `_CrossHatchAngle` | 135° | Perpendicular cross lines |
| `_HatchThickness` | 0.15 | Medium line weight |
| `_ToneLevels` | 5 | Density steps |
| `_ToneBias` | 0 | No bias (adjust per-scene lighting) |
| `_TextureInfluence` | 0.5 | Half PBR tint, half flat ink/paper |
| `_InkColor` | (0.05, 0.05, 0.1) | Dark blue-black ink |
| `_PaperColor` | (0.95, 0.93, 0.88) | Warm cream paper |
| `_OutlineWidth` | 0.002 (body/head/hair) / 0 (eyelash/look) | |

---

### VXT — XToon 2D Ramp with Sobel Edges
**Avaturn file:** `Assets/Shaders/AvaturnNPRShaders/XToon_2DRamp.shader`
**Jade file:** `Assets/Shaders/JadeNPRShaders/XToon_2DRamp.shader` (shader name: `NPR/XToon_2DRamp_Jade`)
**Shader GUID:** `088c73ef0d8f3442d83eb49d1b22a69f`

Based on Barla, Thollot & Markosian "X-Toon: An Extended Toon Shader" (NPAR 2006). Replaces the traditional 1D NdotL toon ramp with a 2D texture:
- **U axis** — lighting intensity (NdotL)
- **V axis** — detail/abstraction level (driven by depth, curvature, or a manual slider)

Also implements Normal Field Abstraction (blend between vertex normals and a smoothed normal map for shape-level abstraction). An inverted-hull outline pass is built-in.

**Sobel inner edges (added):** Optional `_EnableSobel` toggle runs a 3×3 luminance Sobel on the `_BaseMap` texture and composites edge lines over the toon-shaded colour. Uses `_SobelThreshold`, `_SobelSampleDist`, `_SobelStrength`, `_SobelEdgeColor`.

**Important:** XToon uses `_BaseMap` (not `_MainTex`) for its albedo texture. The `_ToonRamp` slot must be filled with a 2D texture — without it the shader falls back to white (flat lit appearance).

| Property Group | Key Properties |
|---------------|----------------|
| Base | `_BaseMap`, `_BaseColor` |
| Toon Ramp | `_ToonRamp`, `_RampSmoothing`, `_LightSensitivity` |
| Abstraction | `_DetailMode` (Depth/Curvature/Manual), `_DetailBias`, `_DepthNear`, `_DepthFar`, `_ManualDetail` |
| Normal Abstraction | `_NormalSmoothing`, `_AbstractNormalMap`, `_UseAbstractNormals` |
| Inner Sobel | `_EnableSobel`, `_SobelEdgeColor`, `_SobelThreshold`, `_SobelSampleDist`, `_SobelStrength` |
| Outline | `_OutlineWidth`, `_OutlineColor` |

**Materials:** `Assets/Materials/NPR Avaturn Materials/VXT XToon/`
- `VXT_body.mat` / `VXT_head.mat` / `VXT_hair.mat` — Sobel on, outline on, `_ToonRamp` slot empty (assign a 2D ramp)
- `VXT_eyelash.mat` — alpha blend enabled (`_SrcBlend=5`, `_DstBlend=10`, `_ZWrite=0`), Sobel off, no outline
- `VXT_look.mat` — eye texture, Sobel off, no outline

---

## Screenshot Scene (Thesis Figure Capture)

Two scripts work together to take thesis screenshots inside Unity Editor Play mode — no Quest headset or build required for the Avaturn and Jade scenes. For Meta SDK avatars the same scripts work: the SDK falls back to a preset avatar from StreamingAssets when no OVR runtime is available.

### ShaderSwapper.cs

Manages a list of named **shader variants** (material sets) and applies them to an avatar's renderers on demand.

**Manual mode (Avaturn / Jade FBX scenes):**
- Populate `Renderer Slots` by dragging `SkinnedMeshRenderer` components from the avatar.
- For each `ShaderVariant`, fill `Materials[]` in the same order as the slots.
- Leave `Avatar Entity` empty.

**Meta SDK mode (metavatars.unity screenshot scene):**
- Drag the `SampleAvatarEntity` (`AvatarEntity1`) into `Avatar Entity`.
- Leave `Renderer Slots` empty.
- For each `ShaderVariant`, fill `Rules[]` instead of `Materials[]`:
  - `Keyword` = partial name matched against the renderer's `gameObject.name` (e.g. `"body"`, `"hair"`, `"eyelash"`, `"look"`). Case-insensitive.
  - Blank keyword = catch-all for any renderer not claimed by a prior rule.
- `ShaderSwapper` subscribes to `OnDefaultAvatarLoadedEvent` + `OnUserAvatarLoadedEvent` in `Start()` and applies materials automatically when the avatar finishes loading.

**Keyboard:** Left/Right arrow keys cycle variants without taking a screenshot.

### ScreenshotController.cs

| Key | Action |
|-----|--------|
| F11 | Single screenshot, current variant |
| F12 | Advance to next variant, then screenshot |
| Ctrl+F12 | Auto-batch: captures every variant in sequence with `batchDelay` seconds between shots |

Output path: `<ProjectRoot>/Screenshots/` in the Editor; `Application.persistentDataPath/Screenshots/` in a build (use ADB `adb pull /sdcard/Android/data/<package>/files/Screenshots/` on Quest).

### CameraCoordinateOverlay.cs

On-screen readout of the active camera's transform, placed in the **top-right corner** of the Game View. Intended for setting up reproducible screenshot viewpoints across thesis figures.

| Key | Action |
|-----|--------|
| F9 | Toggle overlay on / off |

Displayed values (updated every frame):

| Row | Source |
|-----|--------|
| Pos X / Y / Z | `Camera.transform.position` |
| Rot X / Y / Z | `Camera.transform.eulerAngles` |
| Dist *(optional)* | `Vector3.Distance(camera, distanceTarget)` |

**Setup:** attach `CameraCoordinateOverlay` to the Main Camera (or any active scene object that has a `Camera` component). Optionally drag the avatar root into the **Distance Target** slot to display distance from lens to avatar.

The overlay is drawn via IMGUI (`OnGUI`) which is **not** captured by `ScreenshotController`'s `RenderTexture` pipeline — so it is visible on screen during setup but never appears in saved PNGs. Toggle off with **F9** before taking any screenshots that must be completely clean.

File naming: `{AvatarName}_{VariantName}_{yyyy-MM-dd_HHmmss}.png`

**Super Sampling** (`superSampling = 2`): renders at 2× the Game View resolution before encoding, giving thesis-quality PNGs at any window size.

### Recommended variant list for Meta SDK scene

| Variant Name | Rules (keyword → material) |
|---|---|
| `V1_Toon` | body→V1_body, head→V1_head, hair→V1_hair, look→V1_look, eyelash→V1_eyelash, (blank)→V1_body |
| `V2_NormalEdge` | body→V2_body, … |
| `V3_Sobel` | body→V3_body, … |
| `V4_GaussSobel` | body→V4_body, … |
| `V5_Hierarchical` | body→V5_body, head→V5_head (skin discard ON), … |
| `V6_NormalMap` | body→V6_body, … |
| `V7_Crease` | body→V7_body, … |
| `V8_QuantizedSobel` | body→V8_body, … |
| `VXT_XToon_Depth` | body→VXT_body (depth mode), … |
| `VXT_XToon_Curvature` | body→VXT_body (curvature mode), … |

Duplicate `VXT_body.mat` and set `_DetailMode` to the appropriate value before dragging into the variant rule, so each XToon mode is a separate preset.

---

## File Map

```
Assets/
├── Scripts/
│   ├── AvatarSwitcher.cs                  — avatar preset cycling + floating HUD
│   ├── NPREdgeDetectionUI.cs              — in-VR parameter panel
│   ├── PostProcessController.cs           — runtime setter API for KuwaharaFilterFeature + EdgeDetectionFeature (renderer features)
│   ├── HierarchicalShaderController.cs    — runtime setter API for V5_HierarchicalGaussian material properties via MaterialPropertyBlock
│   ├── FreeCameraController.cs            — keyboard/mouse free-fly camera (WASD + right-drag, Q/E vertical)
│   ├── AvaturnLabelManager.cs             — [ExecuteAlways] manager: scans scene for Avaturn roots, spawns floating labels
│   ├── AvaturnLabel.cs                    — per-avatar label with auto-parsed name ("Avaturn (NPR V8)" → "V8")
│   ├── AvaturnAnimationPrepare.cs         — attach to the parent of a GLTFast-loaded Avaturn GLB; builds a Humanoid Avatar
│   │                                         at runtime via AvatarBuilder.BuildHumanAvatar() so Mixamo clips retarget correctly
│   ├── ShaderSwapper.cs                   — applies named shader variant sets to an avatar's renderers
│   │                                         MANUAL MODE: drag SkinnedMeshRenderers into slots; Materials[] ordered by slot
│   │                                         META SDK MODE: assign OvrAvatarEntity; renderers auto-discovered after load;
│   │                                         each variant uses MaterialRule[] (keyword → material, blank = catch-all)
│   │                                         Arrow keys cycle variants; API: NextVariant/PrevVariant/SetVariant/ResetToFirst
│   ├── ScreenshotController.cs            — screenshot capture for thesis figures (no Quest headset required in Editor)
│   │                                         F11 = single shot; F12 = next variant + shot; Ctrl+F12 = auto-batch all variants
│   │                                         Saves to <ProjectRoot>/Screenshots/ (Editor) or persistentDataPath (build)
│   │                                         File naming: {AvatarName}_{VariantName}_{timestamp}.png
│   └── CameraCoordinateOverlay.cs         — IMGUI overlay: shows camera Pos X/Y/Z and Rot X/Y/Z in top-right corner
│                                             F9 = toggle; optional DistanceTarget shows lens-to-avatar distance
│                                             NOT captured by ScreenshotController (IMGUI bypasses RenderTexture pipeline)
├── AvatarShaderExperimental/
│   ├── Scripts/Rendering/
│   │   ├── KuwaharaFilterFeature.cs       — screen-space anisotropic Kuwahara URP feature
│   │   ├── EdgeDetectionFeature.cs        — screen-space hierarchical edge detection URP feature
│   │   └── AnisotropicKuwaharaFeature.cs  — simpler 3-pass Kuwahara (no masking, no edge step)
│   ├── Materials/V1 InvertedHull/         — JadeHull materials using Custom/V1_InvertedHullOutline (same shader as VHull)
│   │   └── JadeHull_body.mat / JadeHull_eyelash.mat / JadeHull_hair.mat / JadeHull_head.mat / JadeHull_look.mat
│   ├── Materials/V4 HalftoneHatching/     — Jody V4 halftone/hatching (same shader as Avaturn V4)
│   │   ├── V4_body.mat / V4_clothing.mat  — body+clothing textures, _NORMALMAP, ObjectSpace, outline on
│   │   └── V4_hair.mat / V4_eyelash.mat   — hair/eyelash texture, _ALPHATEST_ON, _AlphaCutoff 0.07, no outline
│   ├── Materials/Halftone/                — Legacy Jody halftone materials (older per-character shader variant)
├── URP_QUEST_Renderer.asset               — active renderer (all scenes); has Kuwahara + EdgeDetection features
├── URP_QUEST.asset                        — active URP pipeline; depth+opaque textures enabled
├── Shaders/
│   ├── CommonNPRShaders/                  — shaders shared between Jade and Avaturn avatars
│   │   ├── V1_InvertedHullOutline.shader  — two-pass: outline (Cull Front) + full URP PBR (Cull Back)
│   │   ├── HalftoneHatching.shader        — halftone + hatching standalone
│   │   └── AvatarMaskCapture.shader       — avatar silhouette mask
│   ├── JadeNPRShaders/
│   │   ├── V1_ToonShading_GeometryOutline.shader — Jade standalone: toon + inverted hull outline
│   │   ├── V2_NormalEdgeDetection.shader  — Jade standalone: TBN-decoded normal map + Fresnel edges
│   │   ├── V3_SobelEdgeDetection.shader   — Jade standalone: Sobel on texture luma
│   │   ├── V4_GaussianPreFilteredSobel.shader — Jade standalone: Gaussian + Sobel
│   │   ├── V5_HierarchicalGaussian.shader — Jade standalone: depth+normal+Gauss Roberts Cross
│   │   ├── XToon_2DRamp.shader            — Jade standalone: XToon 2D ramp (NPR/XToon_2DRamp_Jade)
│   │   ├── AnisotropicKuwahara.shader     — 4-pass Kuwahara (used by KuwaharaFilterFeature)
│   │   ├── HierarchicalEdgeDetection.shader — depth+normal+color edge (used by EdgeDetectionFeature)
│   │   └── SobelEdgeDetection.shader      — Sobel-only edge shader
│   ├── AvaturnNPRShaders/
│   │   ├── V1_ToonShading_GeometryOutline.shader — Avaturn standalone: toon + inverted hull outline
│   │   ├── V2_NormalEdgeDetection.shader  — Avaturn standalone: TBN-decoded normal map + Fresnel edges
│   │   ├── V3_SobelEdgeDetection.shader   — Avaturn standalone: Sobel on texture luma
│   │   ├── V4_GaussianPreFilteredSobel.shader — Avaturn standalone: Gaussian + Sobel
│   │   ├── V5_HierarchicalGaussian.shader — Avaturn standalone: Hierarchical + Gaussian Roberts Cross
│   │   ├── V8_QuantizedSobel.shader       — Avaturn standalone: quantize + dual Sobel
│   │   ├── XToon_2DRamp.shader            — Avaturn standalone: XToon 2D ramp + Sobel
│   │   └── AnisotropicKuwahara.shader     — Kuwahara shader (Avaturn copy)
│   └── MetaAvatarShaders/
│       ├── Avatar-Meta-UGB.shader         — Meta Avatar NPR shader (Shader "Avatar/MetaNPR")
│       ├── AvatarNPREdgeEffect.cginc      — Technique 1:  Derivative
│       ├── NPREffect_Sobel.cginc          — Technique 2:  Sobel
│       ├── NPREffect_NormalEdge.cginc     — Technique 3:  Normal + Fresnel
│       ├── NPREffect_GaussianSobel.cginc  — Technique 4:  Gaussian Sobel
│       ├── NPREffect_Hierarchical.cginc   — Technique 5:  Hierarchical
│       ├── NPREffect_Kuwahara2.cginc      — Technique 6:  Kuwahara (anisotropic)
│       ├── NPREffect_Kuwahara2Sobel.cginc — Technique 7:  Kuwahara + Sobel
│       ├── NPREffect_Kuwahara2GaussHier.cginc — Technique 8: Kuwahara + Hierarchical
│       ├── NPREffect_Toon.cginc           — Technique 9:  Toon / Cel Shader
│       ├── NPREffect_ToonSobel.cginc      — Technique 10: Toon + Sobel
│       ├── NPREffect_ToonGaussHier.cginc  — Technique 11: Toon + Hierarchical
│       ├── NPREffect_Halftone.cginc       — Technique 12: Halftone
│       ├── NPREffect_Hatching.cginc       — Technique 13: Hatching
│       ├── NPREffect_XToon.cginc          — Technique 14: XToon 2D Ramp (Meta; sampler2D, legacy CG compatible)
│       └── app_specific/
│           └── app_functions.hlsl         — multi_compile keywords + include dispatch + OUTLINE_PASS hook
├── Editor/
│   ├── ShaderPresetStore.cs                   — static CSV store: read/write named presets to Assets/Editor/ShaderPresets.csv
│   │                                             API: SavePreset / LoadPreset / GetPresetNames / HasPreset / DeletePreset / Reload
│   ├── ShaderPresets.csv                      — persistent preset data (multiple named presets per shader/slot combination)
│   ├── AvaturnPresetShaderGUI.cs              — ShaderGUI for Avaturn shaders: CSV-backed Save/Apply/Delete presets + XToon quick-select buttons
│   ├── JadePresetShaderGUI.cs                 — ShaderGUI for Jade XToon shader: same CSV workflow; XToon quick buttons (Depth/Curvature/Manual)
│   ├── InvertedHullPresetShaderGUI.cs         — ShaderGUI for Custom/V1_InvertedHullOutline; routes to Jade or Avaturn preset GUI by path
│   └── VHullTextureAssigner.cs                — One-shot tool (Tools menu): assigns all 4 PBR maps from Avaturn.glb to VHull_* materials
├── Materials/NPR Avaturn Materials/
│   ├── V1 InvertedHull/                   — VHull materials using Custom/V1_InvertedHullOutline
│   │   ├── VHull_body.mat / VHull_head.mat / VHull_hair.mat / VHull_eyelash.mat / VHull_look.mat / VHull_shoe.mat
│   │   └── (run VHullTextureAssigner to assign PBR textures from Avaturn.glb)
│   ├── V1 ToonShading/                    — V1 original (do not modify)
│   ├── V2 NormalEdgeDetection/            — V2 normal-edge materials
│   ├── V3 SobelEdgeDetection/             — V3 Sobel materials (also used by V5–V7 avatars)
│   ├── V3.2 GaussianPreFilteredSobel/       — V3.2 Gaussian-Sobel materials
│   ├── V5 HierarchicalGaussian/           — V5 per-material hierarchical edge; head has skin discard ON
│   │   ├── V5_body.mat                    — opaque body; all edge layers ON
│   │   ├── V5_head.mat                    — face; skin discard ON (suppresses nose/cheek false edges)
│   │   ├── V5_hair.mat                    — alpha-test; edge detection ON
│   │   ├── V5_eyelash.mat                 — alpha-test; all edge layers OFF, no outline
│   │   └── V5_look.mat                    — eyes; all edge layers OFF, no outline
│   ├── V4 HalftoneHatching/               — V4 Halftone/Hatching (thesis-canonical V4_*.mat naming)
│   │   ├── V4_body.mat / V4_head.mat / V4_hair.mat / V4_look.mat
│   │   └── V4_eyelash.mat                 — _ALPHATEST_ON, _AlphaCutoff 0.07, no outline
│   ├── V8 QuantizedSobel/                 — V8 quantized-colour dual-Sobel materials
│   ├── VHH HalftoneHatching/              — Legacy halftone/hatching materials (shader GUID fixed 2026-06-05)
│   └── VXT XToon/                         — XToon 2D-ramp materials (need _ToonRamp assigned)
└── Samples/Meta Avatars SDK/40.0.1/
    └── Sample Scenes/Scripts/
        └── SampleAvatarEntity.cs          — SDK sample script (modified: SwitchPreset added)
```
