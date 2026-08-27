using UnityEditor;
using UnityEngine;

/// Custom Inspector for Custom/Avaturn_V5_HierarchicalGaussian and Custom/V5_HierarchicalGaussian.
/// Shows a collapsible preset panel for each avatar slot (Head / Body / Hair / Eyelash / Look).
/// Each panel compares current values against the saved defaults and has an Apply button.
public class V5HierarchicalShaderGUI : ShaderGUI
{
    // ── Per-slot presets ──────────────────────────────────────────────────────

    static readonly (string prop, float value)[] HeadPreset =
    {
        ("_OuterOutlineWidth",  0.002f),
        ("_EnableAlphaTest",    0f),
        ("_AlphaCutoff",        0.07f),
        ("_TextureIntensity",   1f),
        ("_ShadowStrength",     0.5f),
        ("_RimPower",           3f),
        ("_BumpScale",          1f),
        ("_EnableDepthEdge",    1f),
        ("_HDepthThreshold",    0.05f),
        ("_HDepthWeight",       1f),
        ("_EnableNormalEdge",   1f),
        ("_HNormalThreshold",   0.3f),
        ("_HNormalWeight",      1f),
        ("_EnableColorEdge",    1f),
        ("_HColorThreshold",    0.1f),
        ("_HColorWeight",       1f),
        ("_HEdgeWidth",         1f),
        ("_EnableGaussBlur",    1f),
        ("_HBlurRadius",        0.5f),
        ("_HCenterWeight",      0.25f),
        ("_HCardinalWeight",    0.125f),
        ("_HDiagonalWeight",    0.0625f),
        ("_HEnableSkinDiscard", 1f),
        ("_HSkinHueMin",        0.02f),
        ("_HSkinHueMax",        0.12f),
        ("_HSkinSatMin",        0.15f),
        ("_HEdgeStrength",      1f),
        ("_HAdaptiveStrength",  0.5f),
    };

    static readonly (string prop, float value)[] BodyPreset =
    {
        ("_OuterOutlineWidth",  0.002f),
        ("_EnableAlphaTest",    0f),
        ("_AlphaCutoff",        0.07f),
        ("_TextureIntensity",   1f),
        ("_ShadowStrength",     0.5f),
        ("_RimPower",           3f),
        ("_BumpScale",          1f),
        ("_EnableDepthEdge",    1f),
        ("_HDepthThreshold",    0.05f),
        ("_HDepthWeight",       1f),
        ("_EnableNormalEdge",   1f),
        ("_HNormalThreshold",   0.3f),
        ("_HNormalWeight",      1f),
        ("_EnableColorEdge",    0f),
        ("_HColorThreshold",    0.1f),
        ("_HColorWeight",       0f),
        ("_HEdgeWidth",         1f),
        ("_EnableGaussBlur",    1f),
        ("_HBlurRadius",        0.5f),
        ("_HCenterWeight",      0.25f),
        ("_HCardinalWeight",    0.125f),
        ("_HDiagonalWeight",    0.0625f),
        ("_HEnableSkinDiscard", 0f),
        ("_HSkinHueMin",        0.02f),
        ("_HSkinHueMax",        0.12f),
        ("_HSkinSatMin",        0.15f),
        ("_HEdgeStrength",      1f),
        ("_HAdaptiveStrength",  0.5f),
    };

    static readonly (string prop, float value)[] HairPreset =
    {
        ("_OuterOutlineWidth",  0.002f),
        ("_EnableAlphaTest",    1f),
        ("_AlphaCutoff",        0.07f),
        ("_TextureIntensity",   1f),
        ("_ShadowStrength",     0.5f),
        ("_RimPower",           3f),
        ("_BumpScale",          1f),
        ("_EnableDepthEdge",    1f),
        ("_HDepthThreshold",    0.05f),
        ("_HDepthWeight",       1f),
        ("_EnableNormalEdge",   1f),
        ("_HNormalThreshold",   0.3f),
        ("_HNormalWeight",      1f),
        ("_EnableColorEdge",    0f),
        ("_HColorThreshold",    0.15f),
        ("_HColorWeight",       0f),
        ("_HEdgeWidth",         1f),
        ("_EnableGaussBlur",    1f),
        ("_HBlurRadius",        0.5f),
        ("_HCenterWeight",      0.25f),
        ("_HCardinalWeight",    0.125f),
        ("_HDiagonalWeight",    0.0625f),
        ("_HEnableSkinDiscard", 0f),
        ("_HSkinHueMin",        0.02f),
        ("_HSkinHueMax",        0.12f),
        ("_HSkinSatMin",        0.15f),
        ("_HEdgeStrength",      1f),
        ("_HAdaptiveStrength",  0.5f),
    };

    static readonly (string prop, float value)[] EyelashPreset =
    {
        ("_OuterOutlineWidth",  0f),
        ("_EnableAlphaTest",    1f),
        ("_AlphaCutoff",        0.1f),
        ("_TextureIntensity",   1f),
        ("_ShadowStrength",     0.3f),
        ("_RimPower",           3f),
        ("_BumpScale",          1f),
        ("_EnableDepthEdge",    0f),
        ("_HDepthThreshold",    0.05f),
        ("_HDepthWeight",       0f),
        ("_EnableNormalEdge",   0f),
        ("_HNormalThreshold",   0.3f),
        ("_HNormalWeight",      0f),
        ("_EnableColorEdge",    0f),
        ("_HColorThreshold",    0.1f),
        ("_HColorWeight",       0f),
        ("_HEdgeWidth",         1f),
        ("_EnableGaussBlur",    0f),
        ("_HBlurRadius",        0.5f),
        ("_HCenterWeight",      0.25f),
        ("_HCardinalWeight",    0.125f),
        ("_HDiagonalWeight",    0.0625f),
        ("_HEnableSkinDiscard", 0f),
        ("_HSkinHueMin",        0.02f),
        ("_HSkinHueMax",        0.12f),
        ("_HSkinSatMin",        0.15f),
        ("_HEdgeStrength",      0f),
        ("_HAdaptiveStrength",  0f),
    };

    static readonly (string prop, float value)[] LookPreset =
    {
        ("_OuterOutlineWidth",  0f),
        ("_EnableAlphaTest",    0f),
        ("_AlphaCutoff",        0.07f),
        ("_TextureIntensity",   1f),
        ("_ShadowStrength",     0.2f),
        ("_RimPower",           5f),
        ("_BumpScale",          1f),
        ("_EnableDepthEdge",    0f),
        ("_HDepthThreshold",    0.05f),
        ("_HDepthWeight",       0f),
        ("_EnableNormalEdge",   0f),
        ("_HNormalThreshold",   0.3f),
        ("_HNormalWeight",      0f),
        ("_EnableColorEdge",    0f),
        ("_HColorThreshold",    0.1f),
        ("_HColorWeight",       0f),
        ("_HEdgeWidth",         1f),
        ("_EnableGaussBlur",    0f),
        ("_HBlurRadius",        0.5f),
        ("_HCenterWeight",      0.25f),
        ("_HCardinalWeight",    0.125f),
        ("_HDiagonalWeight",    0.0625f),
        ("_HEnableSkinDiscard", 0f),
        ("_HSkinHueMin",        0.02f),
        ("_HSkinHueMax",        0.12f),
        ("_HSkinSatMin",        0.15f),
        ("_HEdgeStrength",      0f),
        ("_HAdaptiveStrength",  0f),
    };

    // ── Foldout state ─────────────────────────────────────────────────────────
    static bool _headFoldout    = true;
    static bool _bodyFoldout    = false;
    static bool _hairFoldout    = false;
    static bool _eyelashFoldout = false;
    static bool _lookFoldout    = false;

    // ── GUI ───────────────────────────────────────────────────────────────────

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        var bumpMapProp   = FindProperty("_BumpMap", props, false);
        bool bumpAssigned = bumpMapProp != null && bumpMapProp.textureValue != null;

        DrawPresetPanel(editor, props, "Head Preset",    ref _headFoldout,    HeadPreset,    bumpAssigned, bumpMapProp);
        DrawPresetPanel(editor, props, "Body Preset",    ref _bodyFoldout,    BodyPreset,    bumpAssigned, bumpMapProp);
        DrawPresetPanel(editor, props, "Hair Preset",    ref _hairFoldout,    HairPreset,    bumpAssigned, bumpMapProp);
        DrawPresetPanel(editor, props, "Eyelash Preset", ref _eyelashFoldout, EyelashPreset, bumpAssigned, bumpMapProp);
        DrawPresetPanel(editor, props, "Look Preset",    ref _lookFoldout,    LookPreset,    bumpAssigned, bumpMapProp);

        EditorGUILayout.Space(6);

        // ── Standard property fields ──────────────────────────────────────────
        base.OnGUI(editor, props);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    static void DrawPresetPanel(MaterialEditor editor, MaterialProperty[] props,
                                string label, ref bool foldout,
                                (string prop, float value)[] preset,
                                bool bumpAssigned, MaterialProperty bumpMapProp)
    {
        foldout = EditorGUILayout.BeginFoldoutHeaderGroup(foldout, label);
        if (foldout)
        {
            EditorGUI.indentLevel++;

            bool floatsMatch = MatchesPreset(props, preset);
            bool matches     = floatsMatch && bumpAssigned;

            var statusStyle = new GUIStyle(EditorStyles.label);
            statusStyle.fontStyle = FontStyle.Bold;
            statusStyle.normal.textColor = matches
                ? new Color(0.2f, 0.7f, 0.2f)
                : new Color(0.75f, 0.45f, 0f);
            EditorGUILayout.LabelField(
                matches ? "✓  Matches preset" : "○  Differs from preset",
                statusStyle);

            EditorGUI.indentLevel++;

            // Normal map row
            {
                var rowStyle = new GUIStyle(EditorStyles.miniLabel);
                rowStyle.normal.textColor = bumpAssigned
                    ? new Color(0.3f, 0.6f, 0.3f)
                    : new Color(0.8f, 0.35f, 0.1f);
                string bumpLabel = bumpAssigned
                    ? $"{bumpMapProp.textureValue.name}  ✓"
                    : "None  →  run Tools > Assign Avaturn Normal Maps";
                EditorGUILayout.LabelField("_BumpMap", bumpLabel, rowStyle);
            }

            foreach (var (propName, reference) in preset)
            {
                var p = FindProperty(propName, props, false);
                if (p == null) continue;

                float current   = p.floatValue;
                bool  propMatch = Mathf.Approximately(current, reference);
                var   rowStyle  = new GUIStyle(EditorStyles.miniLabel);
                rowStyle.normal.textColor = propMatch
                    ? new Color(0.3f, 0.6f, 0.3f)
                    : new Color(0.8f, 0.35f, 0.1f);
                EditorGUILayout.LabelField(
                    propName,
                    propMatch ? $"{current:G4}  ✓" : $"{current:G4}  →  {reference:G4}",
                    rowStyle);
            }

            EditorGUI.indentLevel--;
            EditorGUILayout.Space(4);

            using (new EditorGUI.DisabledScope(floatsMatch))
            {
                if (GUILayout.Button($"Apply {label} (floats)", GUILayout.Height(24)))
                {
                    Undo.RecordObjects(editor.targets, $"Apply V5 {label}");
                    ApplyPreset(props, preset);
                }
            }

            if (!bumpAssigned)
            {
                EditorGUILayout.HelpBox(
                    "Normal map not assigned. Run  Tools > Assign Avaturn Normal Maps to V5 Materials.",
                    MessageType.Warning);
            }

            EditorGUI.indentLevel--;
        }
        EditorGUILayout.EndFoldoutHeaderGroup();
    }

    static bool MatchesPreset(MaterialProperty[] props, (string, float)[] preset)
    {
        foreach (var (name, reference) in preset)
        {
            var p = FindProperty(name, props, false);
            if (p != null && !Mathf.Approximately(p.floatValue, reference))
                return false;
        }
        return true;
    }

    static void ApplyPreset(MaterialProperty[] props, (string, float)[] preset)
    {
        foreach (var (name, value) in preset)
        {
            var p = FindProperty(name, props, false);
            if (p != null) p.floatValue = value;
        }
    }
}
