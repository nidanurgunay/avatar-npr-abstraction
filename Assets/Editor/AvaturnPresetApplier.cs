using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

// Window → Avaturn → Apply Preset to All Slots
// Finds every material in the project that uses a given Avaturn NPR shader,
// then applies a saved preset to all of them at once — one click per photo.
public class AvaturnPresetApplier : EditorWindow
{
    [MenuItem("Window/Avaturn/Apply Preset to All Slots")]
    static void Open() => GetWindow<AvaturnPresetApplier>("Preset Applier");

    static readonly string[] ShaderNames =
    {
        "Custom/GaussianPrefilteredSobel",
        "Custom/HierarchicalGaussian_Forward",
        "Custom/SobelEdgeDetection",
        "Custom/V7_KuwaharaSobel",
    };

    string   _selectedShader = "Custom/GaussianPrefilteredSobel";
    string   _selectedPreset = "";
    string   _sourceSlot     = "Look";
    string   _statusMsg      = "";
    bool     _statusOk       = true;

    static readonly string[] SlotNames = { "Head", "Body", "Hair", "Eyelash", "Look", "Shoe" };

    void OnGUI()
    {
        EditorGUILayout.Space(6);
        EditorGUILayout.LabelField("Apply Preset to All Slots", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox(
            "Pick a shader, the slot the preset was saved under, and the preset name.\n" +
            "Every project material using that shader will receive the same values.",
            MessageType.Info);

        EditorGUILayout.Space(6);

        // Shader picker
        EditorGUILayout.LabelField("Shader", EditorStyles.boldLabel);
        int shaderIdx = System.Array.IndexOf(ShaderNames, _selectedShader);
        shaderIdx = EditorGUILayout.Popup(shaderIdx < 0 ? 0 : shaderIdx, ShaderNames);
        _selectedShader = ShaderNames[shaderIdx];

        EditorGUILayout.Space(4);

        // Source slot (where the preset was originally saved)
        EditorGUILayout.LabelField("Preset was saved under slot", EditorStyles.boldLabel);
        int slotIdx = System.Array.IndexOf(SlotNames, _sourceSlot);
        slotIdx    = GUILayout.SelectionGrid(slotIdx < 0 ? 4 : slotIdx, SlotNames, 3,
                         EditorStyles.miniButton);
        _sourceSlot = SlotNames[slotIdx];

        EditorGUILayout.Space(4);

        // Preset name picker
        List<string> presets = ShaderPresetStore.GetPresetNames(_selectedShader, _sourceSlot);
        EditorGUILayout.LabelField("Preset", EditorStyles.boldLabel);
        if (presets.Count == 0)
        {
            EditorGUILayout.HelpBox(
                $"No presets saved for shader \"{_selectedShader}\" / slot \"{_sourceSlot}\".",
                MessageType.Warning);
        }
        else
        {
            int presetIdx = presets.IndexOf(_selectedPreset);
            presetIdx     = EditorGUILayout.Popup(presetIdx < 0 ? 0 : presetIdx, presets.ToArray());
            _selectedPreset = presets[presetIdx];
        }

        EditorGUILayout.Space(8);

        using (new EditorGUI.DisabledScope(presets.Count == 0 || _selectedPreset.Length == 0))
        {
            if (GUILayout.Button("Apply to All Materials Using This Shader", GUILayout.Height(32)))
                ApplyToAll();
        }

        EditorGUILayout.Space(6);
        if (_statusMsg.Length > 0)
        {
            EditorGUILayout.HelpBox(_statusMsg,
                _statusOk ? MessageType.Info : MessageType.Error);
        }
    }

    void ApplyToAll()
    {
        ShaderPresetStore.LoadPreset(_selectedShader, _sourceSlot, _selectedPreset,
            out List<(string n, float v)> floats,
            out List<(string n, Color v)> colors);

        if (floats.Count == 0 && colors.Count == 0)
        {
            _statusMsg = $"Preset \"{_selectedPreset}\" loaded no properties. Nothing applied.";
            _statusOk  = false;
            return;
        }

        Shader shader = Shader.Find(_selectedShader);
        if (shader == null)
        {
            _statusMsg = $"Shader \"{_selectedShader}\" not found in project.";
            _statusOk  = false;
            return;
        }

        string[] guids = AssetDatabase.FindAssets("t:Material");
        int count = 0;
        foreach (string guid in guids)
        {
            string path = AssetDatabase.GUIDToAssetPath(guid);
            var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (mat == null || mat.shader != shader) continue;

            Undo.RecordObject(mat, $"Apply Preset {_selectedPreset}");
            foreach (var (n, v) in floats)
                if (mat.HasProperty(n)) mat.SetFloat(n, v);
            foreach (var (n, v) in colors)
                if (mat.HasProperty(n)) mat.SetColor(n, v);

            EditorUtility.SetDirty(mat);
            count++;
        }

        AssetDatabase.SaveAssets();
        _statusMsg = $"Applied \"{_selectedPreset}\" to {count} material(s).";
        _statusOk  = true;
        Repaint();
    }
}
