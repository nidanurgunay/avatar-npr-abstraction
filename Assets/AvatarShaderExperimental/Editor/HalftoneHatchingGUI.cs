using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class HalftoneHatchingGUI : ShaderGUI
{
    // =========================================================================
    // Preset panel state  (mirrors AvaturnPresetShaderGUI pattern)
    // =========================================================================
    static readonly string[] SlotNames = { "Head", "Body", "Hair", "Eyelash", "Look" };

    static readonly Dictionary<string, int>    s_SelectedSlot  = new();
    static readonly Dictionary<string, bool>   s_PresetFoldout = new();
    static readonly Dictionary<string, bool>   s_DiffFoldout   = new();
    static readonly Dictionary<string, string> s_PresetName    = new();

    // =========================================================================
    // NORMAL DEFAULTS  (shown as hints, applied by Reset button)
    // =========================================================================
    static readonly Color DefaultBaseColor    = Color.white;
    static readonly Color DefaultInkColor     = new Color(0.05f, 0.05f, 0.10f, 1f);
    static readonly Color DefaultPaperColor   = new Color(0.95f, 0.93f, 0.88f, 1f);
    static readonly Color DefaultOutlineColor = Color.black;

    const float DefaultPatternMode    = 0f;   // Halftone
    const float DefaultHalftoneSpace  = 2f;   // WorldSpace
    const float DefaultHatchStyle     = 0f;   // Line

    static readonly (string name, float value)[] DefaultFloats =
    {
        ("_TextureInfluence",  0.5f),
        ("_LightingInfluence", 0.75f),
        ("_HalftoneScale",     30f),
        ("_HalftoneSharpness", 10f),
        ("_HalftoneAngle",     45f),
        ("_HatchScale",        20f),
        ("_HatchAngle",        45f),
        ("_HatchThickness",    0.15f),
        ("_CrossHatchAngle",   135f),
        ("_DotSize",           0.12f),
        ("_StippleScale",      50f),
        ("_StippleDensity",    1f),
        ("_ToneLevels",        6f),
        ("_ToneBias",          0f),
        ("_ToneWhitePoint",    1f),
        ("_BrightCutoff",      0.4f),
        ("_OutlineWidth",      0.002f),
        ("_Alpha",             1f),
        ("_AlphaCutoff",       0.5f),
    };

    // =========================================================================
    // DEBUG DEFAULTS  ← fill these in when you're ready
    // =========================================================================
    static readonly Color DebugBaseColor    = Color.white;          // TODO
    static readonly Color DebugInkColor     = Color.black;          // TODO
    static readonly Color DebugPaperColor   = Color.white;          // TODO
    static readonly Color DebugOutlineColor = Color.black;          // TODO

    const float DebugPatternMode   = 0f;   // TODO
    const float DebugHalftoneSpace = 2f;   // TODO
    const float DebugHatchStyle    = 0f;   // TODO

    static readonly (string name, float value)[] DebugFloats =
    {
        ("_TextureInfluence",  1f),
        ("_LightingInfluence", 1f),
        ("_HalftoneScale",     30f),
        ("_HalftoneSharpness", 10f),
        ("_HalftoneAngle",     45f),
        ("_HatchScale",        20f),
        ("_HatchAngle",        45f),
        ("_HatchThickness",    0.15f),
        ("_CrossHatchAngle",   135f),
        ("_DotSize",           0.12f),
        ("_StippleScale",      50f),
        ("_StippleDensity",    1f),
        ("_ToneLevels",        6f),
        ("_ToneBias",          0f),
        ("_ToneWhitePoint",    1f),
        ("_BrightCutoff",      0.9f),
        ("_OutlineWidth",      0.002f),
        ("_Alpha",             1f),
        ("_AlphaCutoff",       0.5f),
    };

    // =========================================================================
    // Keyword tables
    // =========================================================================
    static readonly string[] PatternKeywords    = { "_PATTERNMODE_HALFTONE", "_PATTERNMODE_HATCHING", "_PATTERNMODE_STIPPLE", "_PATTERNMODE_COMBINED" };
    static readonly string[] SpaceKeywords      = { "_HALFTONESPACE_SCREENSPACE", "_HALFTONESPACE_OBJECTSPACE", "_HALFTONESPACE_WORLDSPACE" };
    static readonly string[] HatchStyleKeywords = { "_HATCHSTYLE_LINE", "_HATCHSTYLE_DOTS", "_HATCHSTYLE_COMPOSITION" };

    static readonly string[] PatternModeLabels  = { "Halftone (0)", "Hatching (1)", "Stipple (2)", "Combined (3)" };
    static readonly string[] HalftoneSpcLabels  = { "ScreenSpace (0)", "ObjectSpace (1)", "WorldSpace (2)" };
    static readonly string[] HatchStyleLabels   = { "Line (0)", "Dots (1)", "Composition (2)" };

    enum SurfaceType { Opaque, Cutout, Transparent }

    // =========================================================================
    // Styles
    // =========================================================================
    static GUIStyle _hintStyle;
    static GUIStyle HintStyle
    {
        get
        {
            if (_hintStyle != null) return _hintStyle;
            _hintStyle = new GUIStyle(EditorStyles.miniLabel)
            {
                normal    = { textColor = new Color(0.5f, 0.5f, 0.5f) },
                alignment = TextAnchor.MiddleRight,
                fontSize  = 9,
            };
            return _hintStyle;
        }
    }

    static GUIStyle _debugBoxStyle;
    static GUIStyle DebugBoxStyle
    {
        get
        {
            if (_debugBoxStyle != null) return _debugBoxStyle;
            _debugBoxStyle = new GUIStyle(EditorStyles.helpBox);
            return _debugBoxStyle;
        }
    }

    // =========================================================================
    // Inspector
    // =========================================================================
    public override void OnGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        var    material = editor.target as Material;
        string matKey   = AssetDatabase.GetAssetPath(material);
        if (string.IsNullOrEmpty(matKey)) matKey = material.name;

        if (!s_PresetFoldout.ContainsKey(matKey)) s_PresetFoldout[matKey] = true;
        if (!s_DiffFoldout.ContainsKey(matKey))   s_DiffFoldout[matKey]   = false;
        if (!s_SelectedSlot.ContainsKey(matKey))  s_SelectedSlot[matKey]  = DetectSlot(material.name);
        if (!s_PresetName.ContainsKey(matKey))    s_PresetName[matKey]    = "";

        DrawPresetPanel(editor, props, material, matKey);
        EditorGUILayout.Space(6);

        Header("Base");
        DrawWithHint(editor, FindProp("_BaseColor",        props), "default: white");
        DrawWithHint(editor, FindProp("_BaseMap",          props), "default: none");
        DrawNormalMap(editor, props);
        DrawWithHint(editor, FindProp("_InkColor",         props), "default: (0.05, 0.05, 0.1)");
        DrawWithHint(editor, FindProp("_PaperColor",       props), "default: (0.95, 0.93, 0.88)  used at Influence=0");
        DrawWithHint(editor, FindProp("_TextureInfluence", props), "default: 0.5  (0=flat paper+ink, 1=full texture)");

        EditorGUILayout.Space(4);
        Header("Pattern Mode");
        DrawWithHint(editor, FindProp("_PatternMode", props), $"default: {PatternModeLabels[(int)DefaultPatternMode]}");

        EditorGUILayout.Space(4);
        Header("Halftone");
        DrawWithHint(editor, FindProp("_HalftoneScale",     props), "default: 30");
        DrawWithHint(editor, FindProp("_HalftoneSharpness", props), "default: 10");
        DrawWithHint(editor, FindProp("_HalftoneSpace",     props), $"default: {HalftoneSpcLabels[(int)DefaultHalftoneSpace]}");
        DrawWithHint(editor, FindProp("_HalftoneAngle",     props), "default: 45°");

        EditorGUILayout.Space(4);
        Header("Hatching");
        DrawWithHint(editor, FindProp("_HatchStyle",      props), $"default: {HatchStyleLabels[(int)DefaultHatchStyle]}");
        DrawWithHint(editor, FindProp("_HatchScale",      props), "default: 20");
        DrawWithHint(editor, FindProp("_HatchAngle",      props), "default: 45°");
        DrawWithHint(editor, FindProp("_HatchThickness",  props), "default: 0.15  (Line only)");
        DrawWithHint(editor, FindProp("_CrossHatchAngle", props), "default: 135°");
        DrawWithHint(editor, FindProp("_DotSize",         props), "default: 0.12  (Dots / Composition)");

        EditorGUILayout.Space(4);
        Header("Stipple");
        DrawWithHint(editor, FindProp("_StippleScale",   props), "default: 50");
        DrawWithHint(editor, FindProp("_StippleDensity", props), "default: 1");

        EditorGUILayout.Space(4);
        Header("Lighting Response");
        DrawWithHint(editor, FindProp("_LightingInfluence", props), "0=flat uniform  1=full NdotL  default: 0.75");
        DrawWithHint(editor, FindProp("_ToneLevels",        props), "Praun TAM=6 levels  default: 6");
        DrawWithHint(editor, FindProp("_ToneBias",          props), "default: 0");
        DrawWithHint(editor, FindProp("_ToneWhitePoint",    props), "peak NdotL tone → pure paper (1=no remap, lower to widen highlight zone)");

        EditorGUILayout.Space(4);
        Header("Outline");
        DrawWithHint(editor, FindProp("_OutlineColor", props), "default: black");
        DrawWithHint(editor, FindProp("_OutlineWidth", props), "default: 0.002");

        EditorGUILayout.Space(4);
        Header("Surface");
        DrawSurfaceTypeGUI(editor, props);

        EditorGUILayout.Space(8);
        editor.RenderQueueField();

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("", GUI.skin.horizontalSlider);

        if (GUILayout.Button("Reset to Defaults", GUILayout.Height(28)))
            ApplyPreset(editor, isDebug: false);
    }

    // =========================================================================
    // Preset panel (ShaderPresetStore-backed, same as AvaturnPresetShaderGUI)
    // =========================================================================
    void DrawPresetPanel(MaterialEditor editor, MaterialProperty[] props,
                         Material material, string matKey)
    {
        s_PresetFoldout[matKey] = EditorGUILayout.BeginFoldoutHeaderGroup(
            s_PresetFoldout[matKey], "Halftone/Hatching Slot Presets");

        if (s_PresetFoldout[matKey])
        {
            EditorGUI.indentLevel++;

            EditorGUILayout.LabelField("Slot", EditorStyles.boldLabel);
            int newSlot = GUILayout.SelectionGrid(
                s_SelectedSlot[matKey], SlotNames, 5, EditorStyles.miniButton);
            if (newSlot != s_SelectedSlot[matKey])
                s_SelectedSlot[matKey] = newSlot;

            string slotName   = SlotNames[s_SelectedSlot[matKey]];
            string shaderName = material.shader.name;

            EditorGUILayout.Space(6);

            List<string> existing = ShaderPresetStore.GetPresetNames(shaderName, slotName);
            if (existing.Count > 0)
            {
                using (new EditorGUILayout.HorizontalScope())
                {
                    int curIdx = existing.IndexOf(s_PresetName[matKey]);
                    EditorGUI.BeginChangeCheck();
                    int newIdx = EditorGUILayout.Popup(
                        "Saved", curIdx < 0 ? 0 : curIdx, existing.ToArray());
                    if (EditorGUI.EndChangeCheck())
                        s_PresetName[matKey] = existing[newIdx];

                    if (GUILayout.Button("↺", GUILayout.Width(26)))
                        ShaderPresetStore.Reload();
                }
            }

            s_PresetName[matKey] = EditorGUILayout.TextField("Name", s_PresetName[matKey]);
            string presetName = s_PresetName[matKey].Trim();
            bool   hasPreset  = presetName.Length > 0 &&
                                ShaderPresetStore.HasPreset(shaderName, slotName, presetName);

            EditorGUILayout.Space(4);

            if (hasPreset)
            {
                ShaderPresetStore.LoadPreset(shaderName, slotName, presetName,
                    out List<(string n, float v)> floats,
                    out List<(string n, Color v)> colors);

                bool matches   = MatchesPreset(props, floats, colors);
                var  headStyle = new GUIStyle(EditorStyles.label) { fontStyle = FontStyle.Bold };
                headStyle.normal.textColor = matches
                    ? new Color(0.2f, 0.7f, 0.2f) : new Color(0.75f, 0.45f, 0f);
                EditorGUILayout.LabelField(
                    matches ? $"✓  Matches \"{presetName}\"" : $"○  Differs from \"{presetName}\"",
                    headStyle);

                s_DiffFoldout[matKey] = EditorGUILayout.Foldout(
                    s_DiffFoldout[matKey], "Property diff", true);
                if (s_DiffFoldout[matKey])
                {
                    EditorGUI.indentLevel++;
                    DrawDiff(props, floats, colors);
                    EditorGUI.indentLevel--;
                }
            }
            else if (presetName.Length > 0)
            {
                EditorGUILayout.HelpBox(
                    $"No preset \"{presetName}\" saved yet. Tune the material and press Save.",
                    MessageType.Info);
            }
            else
            {
                EditorGUILayout.HelpBox(
                    "Enter a name or pick from Saved to manage presets.",
                    MessageType.Info);
            }

            EditorGUILayout.Space(4);

            using (new EditorGUI.DisabledScope(presetName.Length == 0))
            {
                using (new EditorGUILayout.HorizontalScope())
                {
                    using (new EditorGUI.DisabledScope(!hasPreset))
                    {
                        if (GUILayout.Button("Apply", GUILayout.Height(26)))
                        {
                            Undo.RecordObject(material, $"Apply Preset {presetName}");
                            ShaderPresetStore.LoadPreset(shaderName, slotName, presetName,
                                out List<(string n, float v)> floats,
                                out List<(string n, Color v)> colors);
                            ApplyPresetValues(props, floats, colors);
                            SyncKeywords(material);
                            EditorUtility.SetDirty(material);
                            editor.Repaint();
                        }
                    }

                    if (GUILayout.Button("Save", GUILayout.Height(26)))
                    {
                        ShaderPresetStore.SavePreset(shaderName, slotName, presetName, props);
                        Debug.Log($"[HalftoneHatchingGUI] Saved \"{presetName}\" → {shaderName} / {slotName}");
                    }

                    using (new EditorGUI.DisabledScope(!hasPreset))
                    {
                        if (GUILayout.Button("Delete", GUILayout.Height(26)))
                        {
                            if (EditorUtility.DisplayDialog("Delete Preset",
                                $"Delete \"{presetName}\" for {slotName}?", "Delete", "Cancel"))
                            {
                                ShaderPresetStore.DeletePreset(shaderName, slotName, presetName);
                                s_PresetName[matKey] = "";
                            }
                        }
                    }
                }
            }

            EditorGUI.indentLevel--;
        }

        EditorGUILayout.EndFoldoutHeaderGroup();
    }

    // After loading float values for _PatternMode / _HalftoneSpace / _HatchStyle,
    // sync the corresponding shader_feature keywords so the correct variant compiles.
    static void SyncKeywords(Material mat)
    {
        if (mat.HasProperty("_PatternMode"))
        {
            int idx = Mathf.RoundToInt(mat.GetFloat("_PatternMode"));
            foreach (var kw in PatternKeywords) mat.DisableKeyword(kw);
            if (idx >= 0 && idx < PatternKeywords.Length) mat.EnableKeyword(PatternKeywords[idx]);
        }
        if (mat.HasProperty("_HalftoneSpace"))
        {
            int idx = Mathf.RoundToInt(mat.GetFloat("_HalftoneSpace"));
            foreach (var kw in SpaceKeywords) mat.DisableKeyword(kw);
            if (idx >= 0 && idx < SpaceKeywords.Length) mat.EnableKeyword(SpaceKeywords[idx]);
        }
        if (mat.HasProperty("_HatchStyle"))
        {
            int idx = Mathf.RoundToInt(mat.GetFloat("_HatchStyle"));
            foreach (var kw in HatchStyleKeywords) mat.DisableKeyword(kw);
            if (idx >= 0 && idx < HatchStyleKeywords.Length) mat.EnableKeyword(HatchStyleKeywords[idx]);
        }
    }

    static void ApplyPresetValues(MaterialProperty[] props,
        List<(string n, float v)> floats, List<(string n, Color v)> colors)
    {
        foreach (var (n, v) in floats)
        { var p = FindProperty(n, props, false); if (p != null) p.floatValue = v; }
        foreach (var (n, v) in colors)
        { var p = FindProperty(n, props, false); if (p != null) p.colorValue = v; }
    }

    static bool MatchesPreset(MaterialProperty[] props,
        List<(string n, float v)> floats, List<(string n, Color v)> colors)
    {
        foreach (var (n, v) in floats)
        { var p = FindProperty(n, props, false); if (p != null && !Mathf.Approximately(p.floatValue, v)) return false; }
        foreach (var (n, v) in colors)
        { var p = FindProperty(n, props, false); if (p != null && p.colorValue != v) return false; }
        return true;
    }

    static void DrawDiff(MaterialProperty[] props,
        List<(string n, float v)> floats, List<(string n, Color v)> colors)
    {
        foreach (var (n, v) in floats)
        {
            var p = FindProperty(n, props, false);
            if (p == null) continue;
            bool match = Mathf.Approximately(p.floatValue, v);
            var  style = new GUIStyle(EditorStyles.miniLabel);
            style.normal.textColor = match ? new Color(0.3f, 0.6f, 0.3f) : new Color(0.8f, 0.35f, 0.1f);
            EditorGUILayout.LabelField(n, match ? $"{p.floatValue:G4}  ✓" : $"{p.floatValue:G4}  →  {v:G4}", style);
        }
        foreach (var (n, v) in colors)
        {
            var p = FindProperty(n, props, false);
            if (p == null) continue;
            bool match = p.colorValue == v;
            var  style = new GUIStyle(EditorStyles.miniLabel);
            style.normal.textColor = match ? new Color(0.3f, 0.6f, 0.3f) : new Color(0.8f, 0.35f, 0.1f);
            string cv = $"({p.colorValue.r:F2},{p.colorValue.g:F2},{p.colorValue.b:F2})";
            string sv = $"({v.r:F2},{v.g:F2},{v.b:F2})";
            EditorGUILayout.LabelField(n, match ? $"{cv}  ✓" : $"{cv}  →  {sv}", style);
        }
    }

    static int DetectSlot(string name)
    {
        string l = name.ToLowerInvariant();
        if (l.Contains("head") || l.Contains("face")) return 0;
        if (l.Contains("body"))                        return 1;
        if (l.Contains("hair"))                        return 2;
        if (l.Contains("eyelash"))                     return 3;
        if (l.Contains("look") || l.Contains("eye"))   return 4;
        return 1;
    }

    // =========================================================================
    // Debug GUI
    // =========================================================================
    static void DrawDebugGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        Material mat = (Material)editor.target;
        bool debugOn = mat.IsKeywordEnabled("_DEBUG_ON");

        EditorGUI.BeginChangeCheck();
        bool newDebugOn = EditorGUILayout.Toggle("Enable Debug Values", debugOn);
        if (EditorGUI.EndChangeCheck() && newDebugOn != debugOn)
        {
            Undo.RecordObjects(editor.targets, "Toggle Debug Values");
            foreach (Object t in editor.targets)
            {
                Material m = (Material)t;
                if (newDebugOn)
                {
                    m.EnableKeyword("_DEBUG_ON");
                    ApplyPreset(editor, isDebug: true, singleTarget: m);
                }
                else
                {
                    m.DisableKeyword("_DEBUG_ON");
                    ApplyPreset(editor, isDebug: false, singleTarget: m);
                }
            }
        }

        if (newDebugOn)
        {
            EditorGUILayout.HelpBox(
                "Debug values are active. Uncheck to restore normal defaults.",
                MessageType.Warning);
        }
    }

    // =========================================================================
    // Surface type
    // =========================================================================
    static void DrawSurfaceTypeGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        Material mat = (Material)editor.target;
        SurfaceType current = DetectSurfaceType(mat);

        EditorGUI.BeginChangeCheck();
        SurfaceType selected = (SurfaceType)EditorGUILayout.EnumPopup("Surface Type", current);
        Rect hintRect = EditorGUILayout.GetControlRect(false, 11f);
        hintRect.x    += EditorGUIUtility.labelWidth;
        hintRect.width -= EditorGUIUtility.labelWidth;
        GUI.Label(hintRect, "default: Opaque", HintStyle);

        if (EditorGUI.EndChangeCheck())
        {
            Undo.RecordObjects(editor.targets, "Surface Type Change");
            foreach (Object t in editor.targets)
                ApplySurfaceType((Material)t, selected);
        }

        if (current == SurfaceType.Transparent || current == SurfaceType.Cutout)
            DrawWithHint(editor, FindProp("_Alpha", props), "default: 1");

        if (current == SurfaceType.Cutout)
            DrawWithHint(editor, FindProp("_AlphaCutoff", props), "default: 0.5");
    }

    static SurfaceType DetectSurfaceType(Material mat)
    {
        if (mat.IsKeywordEnabled("_ALPHATEST_ON")) return SurfaceType.Cutout;
        if (mat.GetFloat("_DstBlend") > 0)         return SurfaceType.Transparent;
        return SurfaceType.Opaque;
    }

    static void ApplySurfaceType(Material mat, SurfaceType type)
    {
        switch (type)
        {
            case SurfaceType.Opaque:
                mat.SetFloat("_SrcBlend", (float)BlendMode.One);
                mat.SetFloat("_DstBlend", (float)BlendMode.Zero);
                mat.SetFloat("_ZWrite",   1f);
                mat.DisableKeyword("_ALPHATEST_ON");
                mat.renderQueue = (int)RenderQueue.Geometry;
                mat.SetOverrideTag("RenderType", "Opaque");
                break;
            case SurfaceType.Cutout:
                mat.SetFloat("_SrcBlend", (float)BlendMode.One);
                mat.SetFloat("_DstBlend", (float)BlendMode.Zero);
                mat.SetFloat("_ZWrite",   1f);
                mat.EnableKeyword("_ALPHATEST_ON");
                mat.renderQueue = (int)RenderQueue.AlphaTest;
                mat.SetOverrideTag("RenderType", "TransparentCutout");
                break;
            case SurfaceType.Transparent:
                mat.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
                mat.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
                mat.SetFloat("_ZWrite",   0f);
                mat.DisableKeyword("_ALPHATEST_ON");
                mat.renderQueue = (int)RenderQueue.Transparent;
                mat.SetOverrideTag("RenderType", "Transparent");
                break;
        }
        EditorUtility.SetDirty(mat);
    }

    // =========================================================================
    // Apply preset (normal or debug) — optionally to a single material
    // =========================================================================
    static void ApplyPreset(MaterialEditor editor, bool isDebug, Material singleTarget = null)
    {
        var targets = singleTarget != null
            ? new Object[] { singleTarget }
            : editor.targets;

        if (singleTarget == null)
            Undo.RecordObjects(targets, isDebug ? "Apply Debug Values" : "Reset to Defaults");

        var floats  = isDebug ? DebugFloats  : DefaultFloats;
        var inkCol  = isDebug ? DebugInkColor     : DefaultInkColor;
        var paperCol= isDebug ? DebugPaperColor   : DefaultPaperColor;
        var baseCol = isDebug ? DebugBaseColor     : DefaultBaseColor;
        var outCol  = isDebug ? DebugOutlineColor  : DefaultOutlineColor;
        var patMode = isDebug ? DebugPatternMode   : DefaultPatternMode;
        var hSpace  = isDebug ? DebugHalftoneSpace : DefaultHalftoneSpace;
        var hStyle  = isDebug ? DebugHatchStyle    : DefaultHatchStyle;

        foreach (Object t in targets)
        {
            Material mat = (Material)t;

            SetColor(mat, "_BaseColor",    baseCol);
            SetColor(mat, "_InkColor",     inkCol);
            SetColor(mat, "_PaperColor",   paperCol);
            SetColor(mat, "_OutlineColor", outCol);

            foreach (var (name, value) in floats)
                SetFloat(mat, name, value);

            SetKeywordEnum(mat, "_PatternMode",   patMode, PatternKeywords);
            SetKeywordEnum(mat, "_HalftoneSpace", hSpace,  SpaceKeywords);
            SetKeywordEnum(mat, "_HatchStyle",    hStyle,  HatchStyleKeywords);

            if (!isDebug)
            {
                if (mat.HasProperty("_BaseMap"))
                    mat.SetTexture("_BaseMap", null);
                ApplySurfaceType(mat, SurfaceType.Opaque);
            }

            EditorUtility.SetDirty(mat);
        }
    }

    // =========================================================================
    // Draw helpers
    // =========================================================================
    static void DrawNormalMap(MaterialEditor editor, MaterialProperty[] props)
    {
        var bumpMap   = FindProp("_BumpMap",   props);
        var bumpScale = FindProp("_BumpScale", props);
        if (bumpMap == null || bumpScale == null) return;

        EditorGUI.BeginChangeCheck();
        DrawWithHint(editor, bumpMap,   "default: none  (assigns normal map texture)");
        DrawWithHint(editor, bumpScale, "default: 1.0  (only active when map is assigned)");

        if (EditorGUI.EndChangeCheck())
        {
            foreach (Object t in editor.targets)
            {
                Material mat = (Material)t;
                if (mat.GetTexture("_BumpMap") != null)
                    mat.EnableKeyword("_NORMALMAP");
                else
                    mat.DisableKeyword("_NORMALMAP");
                EditorUtility.SetDirty(mat);
            }
        }
    }

    static void DrawWithHint(MaterialEditor editor, MaterialProperty prop, string hint)
    {
        if (prop == null) return;
        editor.ShaderProperty(prop, prop.displayName);
        Rect hintRect = EditorGUILayout.GetControlRect(false, 11f);
        hintRect.x    += EditorGUIUtility.labelWidth;
        hintRect.width -= EditorGUIUtility.labelWidth;
        GUI.Label(hintRect, hint, HintStyle);
    }

    static void Header(string title) =>
        EditorGUILayout.LabelField(title, EditorStyles.boldLabel);

    static MaterialProperty FindProp(string name, MaterialProperty[] props) =>
        FindProperty(name, props, false);

    // =========================================================================
    // Low-level setters
    // =========================================================================
    static void SetFloat(Material mat, string name, float value)
    {
        if (mat.HasProperty(name)) mat.SetFloat(name, value);
    }

    static void SetColor(Material mat, string name, Color value)
    {
        if (mat.HasProperty(name)) mat.SetColor(name, value);
    }

    static void SetKeywordEnum(Material mat, string floatName, float index, string[] keywords)
    {
        if (!mat.HasProperty(floatName)) return;
        mat.SetFloat(floatName, index);
        for (int i = 0; i < keywords.Length; i++)
        {
            if (i == (int)index) mat.EnableKeyword(keywords[i]);
            else                 mat.DisableKeyword(keywords[i]);
        }
    }
}
