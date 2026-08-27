using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEditor;
using UnityEngine;

// Editor-only. Reads/writes Assets/Editor/ShaderPresets.csv.
// CSV format (one row per property):
//   shader,slot,preset,type,propname,propvalue
// Color values use r|g|b|a (pipe-separated) to stay CSV-safe.
public static class ShaderPresetStore
{
    public const string CSV_RELATIVE = "Assets/Editor/ShaderPresets.csv";

    struct Row
    {
        public string shader, slot, preset, type, propName, propValue;
    }

    static List<Row> s_Rows;

    static string AbsPath =>
        Path.Combine(Path.GetDirectoryName(Application.dataPath), CSV_RELATIVE);

    // ── Public API ────────────────────────────────────────────────────────────

    public static void Reload()
    {
        s_Rows = new List<Row>();
        if (!File.Exists(AbsPath)) return;

        foreach (string line in File.ReadAllLines(AbsPath))
        {
            string trimmed = line.TrimStart();
            if (trimmed.StartsWith("#") || trimmed.StartsWith("shader,")) continue;
            string[] c = line.Split(',');
            if (c.Length < 6) continue;
            s_Rows.Add(new Row
            {
                shader   = c[0], slot     = c[1], preset   = c[2],
                type     = c[3], propName = c[4], propValue = c[5]
            });
        }
    }

    // Pass slot = "" to get preset names across all slots for this shader.
    public static List<string> GetPresetNames(string shader, string slot = "")
    {
        EnsureLoaded();
        var names = new List<string>();
        foreach (Row r in s_Rows)
            if (r.shader == shader && (slot == "" || r.slot == slot) && !names.Contains(r.preset))
                names.Add(r.preset);
        return names;
    }

    // Pass slot = "" to check across all slots.
    public static bool HasPreset(string shader, string slot, string preset)
    {
        EnsureLoaded();
        foreach (Row r in s_Rows)
            if (r.shader == shader && (slot == "" || r.slot == slot) && r.preset == preset)
                return true;
        return false;
    }

    // Pass slot = "" to load from whichever slot contains this preset name.
    public static void LoadPreset(string shader, string slot, string preset,
        out List<(string n, float v)>  floats,
        out List<(string n, Color v)>  colors)
    {
        EnsureLoaded();
        floats = new List<(string, float)>();
        colors = new List<(string, Color)>();

        foreach (Row r in s_Rows)
        {
            if (r.shader != shader || r.preset != preset) continue;
            if (slot != "" && r.slot != slot) continue;

            if (r.type == "float")
            {
                if (float.TryParse(r.propValue, out float fv))
                    floats.Add((r.propName, fv));
            }
            else if (r.type == "color")
            {
                string[] p = r.propValue.Split('|');
                if (p.Length >= 3 &&
                    float.TryParse(p[0], out float cr) &&
                    float.TryParse(p[1], out float cg) &&
                    float.TryParse(p[2], out float cb))
                {
                    float ca = p.Length > 3 && float.TryParse(p[3], out float a) ? a : 1f;
                    colors.Add((r.propName, new Color(cr, cg, cb, ca)));
                }
            }
        }
    }

    public static void SavePreset(string shader, string slot, string preset,
        MaterialProperty[] props)
    {
        EnsureLoaded();
        s_Rows.RemoveAll(r => r.shader == shader && r.slot == slot && r.preset == preset);

        foreach (MaterialProperty p in props)
        {
            if ((p.flags & MaterialProperty.PropFlags.HideInInspector) != 0) continue;

            if (p.type == MaterialProperty.PropType.Float ||
                p.type == MaterialProperty.PropType.Range)
            {
                s_Rows.Add(new Row
                {
                    shader = shader, slot = slot, preset = preset,
                    type = "float", propName = p.name,
                    propValue = p.floatValue.ToString("G6")
                });
            }
            else if (p.type == MaterialProperty.PropType.Color)
            {
                Color c = p.colorValue;
                s_Rows.Add(new Row
                {
                    shader = shader, slot = slot, preset = preset,
                    type = "color", propName = p.name,
                    propValue = $"{c.r:G4}|{c.g:G4}|{c.b:G4}|{c.a:G4}"
                });
            }
        }
        Flush();
    }

    public static void DeletePreset(string shader, string slot, string preset)
    {
        EnsureLoaded();
        s_Rows.RemoveAll(r => r.shader == shader && r.slot == slot && r.preset == preset);
        Flush();
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    static void EnsureLoaded()
    {
        if (s_Rows == null) Reload();
    }

    static void Flush()
    {
        var sb = new StringBuilder();
        sb.AppendLine("shader,slot,preset,type,propname,propvalue");
        foreach (Row r in s_Rows)
            sb.AppendLine($"{r.shader},{r.slot},{r.preset},{r.type},{r.propName},{r.propValue}");

        string dir = Path.GetDirectoryName(AbsPath);
        if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(AbsPath, sb.ToString());
        AssetDatabase.ImportAsset(CSV_RELATIVE, ImportAssetOptions.Default);
    }
}
