using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

// ShaderGUI for all Avaturn NPR shaders (V1–V8, XToon, etc.).
// Presets are saved to Assets/Editor/ShaderPresets.csv — commit it to keep your values.
// For XToon shaders (those with _DetailMode) the panel shows Depth / Curvature / Manual
// quick-select buttons; all other shaders get a free-text preset name.
//
// Auto-save: after every property change, the current values are saved to a preset named
// "AutoSave_<Slot>" (e.g. "AutoSave_Head") as soon as the mouse is released. This means
// the last tuned state is always retrievable from the Saved dropdown even if you forget
// to click Save.
public class AvaturnPresetShaderGUI : ShaderGUI
{
    static readonly string[] SlotNames  = { "Head", "Body", "Hair", "Eyelash", "Look", "Shoe" };
    static readonly string[] XToonNames = { "Depth", "Curvature", "Manual" };

    static readonly Dictionary<string, int>    s_SelectedSlot  = new Dictionary<string, int>();
    static readonly Dictionary<string, bool>   s_PresetFoldout = new Dictionary<string, bool>();
    static readonly Dictionary<string, bool>   s_DiffFoldout   = new Dictionary<string, bool>();
    static readonly Dictionary<string, string> s_PresetName    = new Dictionary<string, string>();

    // Auto-save state: set when a property changes, flushed once hotControl == 0
    static bool   s_PendingAutoSave;
    static string s_PendingAutoSaveMat;

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] props)
    {
        var    material = materialEditor.target as Material;
        string matKey   = AssetDatabase.GetAssetPath(material);
        if (string.IsNullOrEmpty(matKey)) matKey = material.name;

        if (!s_PresetFoldout.ContainsKey(matKey)) s_PresetFoldout[matKey] = true;
        if (!s_DiffFoldout.ContainsKey(matKey))   s_DiffFoldout[matKey]   = false;
        if (!s_SelectedSlot.ContainsKey(matKey))  s_SelectedSlot[matKey]  = DetectSlot(material.name);
        if (!s_PresetName.ContainsKey(matKey))     s_PresetName[matKey]    = "";

        // Flush auto-save once the user releases any dragged control
        if (s_PendingAutoSave && s_PendingAutoSaveMat == matKey && GUIUtility.hotControl == 0)
        {
            s_PendingAutoSave = false;
            string autoSlot = SlotNames[s_SelectedSlot[matKey]];
            ShaderPresetStore.SavePreset(material.shader.name, autoSlot,
                "AutoSave_" + autoSlot, props);
        }

        DrawPresetPanel(materialEditor, props, material, matKey);
        DrawDebugDefaultsToggle(materialEditor, props);

        EditorGUILayout.Space(6);

        // Detect any property change and queue an auto-save
        EditorGUI.BeginChangeCheck();
        base.OnGUI(materialEditor, props);
        if (EditorGUI.EndChangeCheck())
        {
            s_PendingAutoSave    = true;
            s_PendingAutoSaveMat = matKey;
            materialEditor.Repaint();
        }
    }

    void DrawPresetPanel(MaterialEditor materialEditor, MaterialProperty[] props,
                         Material material, string matKey)
    {
        bool autoSavePending = s_PendingAutoSave && s_PendingAutoSaveMat == matKey;
        string header = autoSavePending
            ? "Avaturn Slot Presets  [ unsaved changes ]"
            : "Avaturn Slot Presets";
        s_PresetFoldout[matKey] = EditorGUILayout.BeginFoldoutHeaderGroup(
            s_PresetFoldout[matKey], header);

        if (s_PresetFoldout[matKey])
        {
            EditorGUI.indentLevel++;

            // ── Slot selector ────────────────────────────────────────────────
            EditorGUILayout.LabelField("Slot", EditorStyles.boldLabel);
            int newSlot = GUILayout.SelectionGrid(
                s_SelectedSlot[matKey], SlotNames, 3, EditorStyles.miniButton);
            if (newSlot != s_SelectedSlot[matKey])
                s_SelectedSlot[matKey] = newSlot;

            string slotName   = SlotNames[s_SelectedSlot[matKey]];
            string shaderName = material.shader.name;
            bool   isXToon    = FindProperty("_DetailMode", props, false) != null;

            EditorGUILayout.Space(6);

            // ── XToon quick-select ───────────────────────────────────────────
            if (isXToon)
            {
                EditorGUILayout.LabelField("Quick Select (XToon)", EditorStyles.boldLabel);
                using (new EditorGUILayout.HorizontalScope())
                {
                    foreach (string qn in XToonNames)
                    {
                        bool active = s_PresetName[matKey] == qn;
                        if (GUILayout.Button(qn, active
                                ? EditorStyles.miniButtonMid
                                : EditorStyles.miniButton))
                            s_PresetName[matKey] = qn;
                    }
                }
                EditorGUILayout.Space(4);
            }

            // ── Existing presets dropdown (all slots for this shader) ────────
            List<string> existing = ShaderPresetStore.GetPresetNames(shaderName);
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

            // ── Name text field ──────────────────────────────────────────────
            s_PresetName[matKey] = EditorGUILayout.TextField("Name", s_PresetName[matKey]);
            string presetName = s_PresetName[matKey].Trim();
            bool   hasPreset  = presetName.Length > 0 &&
                                ShaderPresetStore.HasPreset(shaderName, "", presetName);

            EditorGUILayout.Space(4);

            // ── Status + diff ────────────────────────────────────────────────
            if (hasPreset)
            {
                ShaderPresetStore.LoadPreset(shaderName, "", presetName,
                    out List<(string n, float v)> floats,
                    out List<(string n, Color v)> colors);

                bool matches   = MatchesPreset(props, floats, colors);
                var  headStyle = new GUIStyle(EditorStyles.label) { fontStyle = FontStyle.Bold };
                headStyle.normal.textColor = matches
                    ? new Color(0.2f, 0.7f, 0.2f)
                    : new Color(0.75f, 0.45f, 0f);
                EditorGUILayout.LabelField(
                    matches ? $"✓  Matches \"{presetName}\""
                            : $"○  Differs from \"{presetName}\"",
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
                    $"No preset \"{presetName}\" saved yet.\nTune the material and press Save.",
                    MessageType.Info);
            }
            else
            {
                EditorGUILayout.HelpBox(
                    "Enter a name, pick one from Saved, or use a Quick Select button.",
                    MessageType.Info);
            }

            EditorGUILayout.Space(4);

            // ── Action buttons ───────────────────────────────────────────────
            using (new EditorGUI.DisabledScope(presetName.Length == 0))
            {
                using (new EditorGUILayout.HorizontalScope())
                {
                    using (new EditorGUI.DisabledScope(!hasPreset))
                    {
                        if (GUILayout.Button("Apply", GUILayout.Height(26)))
                        {
                            Undo.RecordObject(material, $"Apply Preset {presetName}");
                            ShaderPresetStore.LoadPreset(shaderName, "", presetName,
                                out List<(string n, float v)> floats,
                                out List<(string n, Color v)> colors);
                            ApplyPreset(props, floats, colors);
                            EditorUtility.SetDirty(material);
                            materialEditor.Repaint();
                        }
                    }

                    if (GUILayout.Button("Save", GUILayout.Height(26)))
                    {
                        ShaderPresetStore.SavePreset(shaderName, slotName, presetName, props);
                        Debug.Log($"[ShaderPresets] Saved \"{presetName}\" → {shaderName} / {slotName}");
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

    static void DrawDebugDefaultsToggle(MaterialEditor materialEditor, MaterialProperty[] props)
    {
        var toggleProp = FindProperty("_UseDebugDefaults", props, false);
        if (toggleProp == null) return;

        EditorGUILayout.Space(4);
        EditorGUI.BeginChangeCheck();
        bool current  = toggleProp.floatValue > 0.5f;
        bool newValue = EditorGUILayout.Toggle("Use Debug Defaults", current);
        if (EditorGUI.EndChangeCheck())
        {
            toggleProp.floatValue = newValue ? 1f : 0f;
            if (newValue && !current) materialEditor.Repaint();
        }
    }

    static void ApplyPreset(MaterialProperty[] props,
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
            EditorGUILayout.LabelField(n,
                match ? $"{p.floatValue:G4}  ✓" : $"{p.floatValue:G4}  →  {v:G4}", style);
        }
        foreach (var (n, v) in colors)
        {
            var p = FindProperty(n, props, false);
            if (p == null) continue;
            bool match = p.colorValue == v;
            var  style = new GUIStyle(EditorStyles.miniLabel);
            style.normal.textColor = match ? new Color(0.3f, 0.6f, 0.3f) : new Color(0.8f, 0.35f, 0.1f);
            EditorGUILayout.LabelField(n,
                match ? $"{ColorStr(p.colorValue)}  ✓"
                      : $"{ColorStr(p.colorValue)}  →  {ColorStr(v)}", style);
        }
    }

    static int DetectSlot(string materialName)
    {
        string lower = materialName.ToLowerInvariant();
        if (lower.Contains("head"))                               return 0;
        if (lower.Contains("body"))                               return 1;
        if (lower.Contains("hair"))                               return 2;
        if (lower.Contains("eyelash"))                            return 3;
        if (lower.Contains("look") || lower.Contains("clothing")) return 4;
        if (lower.Contains("shoe") || lower.Contains("sneaker"))  return 5;
        return 0;
    }

    static string ColorStr(Color c) => $"({c.r:F2}, {c.g:F2}, {c.b:F2})";
}
