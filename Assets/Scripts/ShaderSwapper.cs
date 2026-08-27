using System.Collections.Generic;
using Oculus.Avatar2;
using UnityEngine;

// Manages named shader variants (material sets) and applies them to an avatar's renderers.
//
// ── Two modes ────────────────────────────────────────────────────────────────────
//
// MANUAL MODE (Avaturn / Jade FBX scenes)
//   • Drag your SkinnedMeshRenderers into the Renderer Slots list.
//   • For each ShaderVariant, fill Materials[] in the same order as the slots.
//   • Leave "Avatar Entity" empty.
//
// META SDK MODE (SampleAvatarEntity scenes — screenshot scene)
//   • Assign the SampleAvatarEntity GameObject's OvrAvatarEntity component.
//   • Leave Renderer Slots empty.
//   • For each ShaderVariant, fill Rules[] instead of Materials[]:
//       Keyword = partial name to match against the renderer (e.g. "body", "hair").
//       A blank keyword matches every renderer that no other rule claimed.
//   • ShaderSwapper subscribes to OnDefaultAvatarLoadedEvent and
//     OnUserAvatarLoadedEvent, so materials are applied automatically when
//     the avatar finishes loading — even if it loads asynchronously.
//
// ── Screenshot scene quick-setup ─────────────────────────────────────────────────
//   1. Duplicate or open the metavatars.unity scene.
//   2. Add an empty GameObject named "ScreenshotManager".
//   3. Add ShaderSwapper and ScreenshotController components to it.
//   4. Drag the SampleAvatarEntity from the scene into "Avatar Entity".
//   5. Set Avatar Name (used in file names: e.g. "MetaAvatar").
//   6. Add one ShaderVariant per NPR shader (V1, V2 … VXT).
//      For each variant, add Rules:
//        keyword="body"    → V2_body.mat
//        keyword="head"    → V2_head.mat
//        keyword="hair"    → V2_hair.mat
//        keyword="look"    → V2_look.mat    (eyes / lenses)
//        keyword="eyelash" → V2_eyelash.mat
//        keyword=""        → V2_body.mat    (fallback — catches anything else)
//   7. Assign ShaderSwapper to ScreenshotController.
//   8. Press Play → F11 for a single shot, Ctrl+F12 to batch all variants.
[AddComponentMenu("ThesisNPR/Shader Swapper")]
public class ShaderSwapper : MonoBehaviour
{
    // ── Data types ────────────────────────────────────────────────────────────

    [System.Serializable]
    public class RendererSlot
    {
        public string   label;      // "Body", "Hair" — Inspector readability only
        public Renderer renderer;
    }

    [System.Serializable]
    public class MaterialRule
    {
        [Tooltip("Renderer name must CONTAIN this keyword (case-insensitive). " +
                 "Leave blank to match any renderer not claimed by a previous rule.")]
        public string   keyword = "body";
        public Material material;
    }

    [System.Serializable]
    public class ShaderVariant
    {
        public string name;         // shown in screenshot filenames

        [Tooltip("MANUAL MODE: one Material per Renderer Slot (same order).")]
        public Material[] materials;

        [Tooltip("META SDK MODE: keyword → material rules. First match wins; blank keyword is the catch-all.")]
        public MaterialRule[] rules;
    }

    // ── Inspector fields ──────────────────────────────────────────────────────

    [Header("Identity")]
    public string avatarName = "MetaAvatar";

    [Header("Meta SDK Mode  (assign SampleAvatarEntity; leave Renderer Slots empty)")]
    [Tooltip("OvrAvatarEntity to watch. Materials are applied after it finishes loading.")]
    public OvrAvatarEntity avatarEntity;

    [Header("Manual Mode  (FBX avatars — leave Avatar Entity empty)")]
    [Tooltip("Drag SkinnedMeshRenderers here. Order must match each variant's Materials[].")]
    public List<RendererSlot> slots = new List<RendererSlot>();

    [Header("Shader Variants")]
    public List<ShaderVariant> variants = new List<ShaderVariant>();

    [Header("Runtime state (read-only)")]
    [SerializeField] int _currentIndex;

    // ── Public API ────────────────────────────────────────────────────────────

    public string AvatarName         => avatarName;
    public int    VariantCount       => variants.Count;
    public string CurrentVariantName => variants.Count > 0
                                           ? variants[_currentIndex].name
                                           : "None";

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    void Start()
    {
        if (avatarEntity != null)
        {
            avatarEntity.OnDefaultAvatarLoadedEvent.AddListener(OnAvatarLoaded);
            avatarEntity.OnUserAvatarLoadedEvent.AddListener(OnAvatarLoaded);
        }
        else if (variants.Count > 0)
        {
            Apply(_currentIndex);
        }
    }

    void OnDestroy()
    {
        if (avatarEntity == null) return;
        avatarEntity.OnDefaultAvatarLoadedEvent.RemoveListener(OnAvatarLoaded);
        avatarEntity.OnUserAvatarLoadedEvent.RemoveListener(OnAvatarLoaded);
    }

    void OnAvatarLoaded(OvrAvatarEntity entity)
    {
        if (variants.Count > 0) Apply(_currentIndex);
    }

    // ── Variant navigation ────────────────────────────────────────────────────

    public void NextVariant()
    {
        if (variants.Count == 0) return;
        _currentIndex = (_currentIndex + 1) % variants.Count;
        Apply(_currentIndex);
    }

    public void PrevVariant()
    {
        if (variants.Count == 0) return;
        _currentIndex = (_currentIndex - 1 + variants.Count) % variants.Count;
        Apply(_currentIndex);
    }

    public void SetVariant(int index)
    {
        if (index < 0 || index >= variants.Count) return;
        _currentIndex = index;
        Apply(_currentIndex);
    }

    public void ResetToFirst()
    {
        _currentIndex = 0;
        if (variants.Count > 0) Apply(0);
    }

    // ── Keyboard shortcut ─────────────────────────────────────────────────────

    void Update()
    {
        if (UnityEngine.InputSystem.Keyboard.current == null) return;
        if (UnityEngine.InputSystem.Keyboard.current.rightArrowKey.wasPressedThisFrame) NextVariant();
        if (UnityEngine.InputSystem.Keyboard.current.leftArrowKey.wasPressedThisFrame)  PrevVariant();
    }

    // ── Apply ─────────────────────────────────────────────────────────────────

    void Apply(int index)
    {
        ShaderVariant v = variants[index];

        if (avatarEntity != null)
            ApplyByKeyword(v);
        else
            ApplyBySlot(v);

        Debug.Log($"[ShaderSwapper] {avatarName} → {v.name}");
    }

    // Manual mode: positional assignment (Renderers[i] → Materials[i])
    void ApplyBySlot(ShaderVariant v)
    {
        for (int i = 0; i < slots.Count; i++)
        {
            if (slots[i].renderer == null) continue;
            if (v.materials == null || i >= v.materials.Length || v.materials[i] == null) continue;
            slots[i].renderer.sharedMaterial = v.materials[i];
        }
    }

    // Meta SDK mode: keyword matching against every child Renderer
    void ApplyByKeyword(ShaderVariant v)
    {
        if (v.rules == null || v.rules.Length == 0) return;

        var renderers = avatarEntity.GetComponentsInChildren<Renderer>(true);
        var claimed   = new bool[renderers.Length];

        // Pass 1: assign each non-blank keyword rule
        foreach (var rule in v.rules)
        {
            if (string.IsNullOrEmpty(rule.keyword) || rule.material == null) continue;
            string kw = rule.keyword.ToLowerInvariant();

            for (int i = 0; i < renderers.Length; i++)
            {
                if (claimed[i]) continue;
                // Check the renderer's own GameObject name and its parent's name
                string rName = renderers[i].gameObject.name.ToLowerInvariant();
                string pName = renderers[i].transform.parent != null
                               ? renderers[i].transform.parent.name.ToLowerInvariant()
                               : "";

                if (rName.Contains(kw) || pName.Contains(kw))
                {
                    renderers[i].sharedMaterial = rule.material;
                    claimed[i] = true;
                }
            }
        }

        // Pass 2: blank-keyword rule is the catch-all for everything not yet claimed
        foreach (var rule in v.rules)
        {
            if (!string.IsNullOrEmpty(rule.keyword) || rule.material == null) continue;
            for (int i = 0; i < renderers.Length; i++)
            {
                if (!claimed[i])
                {
                    renderers[i].sharedMaterial = rule.material;
                    claimed[i] = true;
                }
            }
        }
    }
}
