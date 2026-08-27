using System;
using System.Collections.Generic;
using UnityEngine;

/// ScriptableObject that persists per-shader, per-slot material presets.
/// Stored at Assets/Editor/AvaturnSlotPresets.asset — commit it to keep your tested values.
public class AvaturnSlotPresets : ScriptableObject
{
    // ── Data types ────────────────────────────────────────────────────────────

    [Serializable] public class FloatProp { public string name; public float value; }
    [Serializable] public class ColorProp { public string name; public Color value; }

    [Serializable]
    public class SlotPreset
    {
        public string slotName;
        public List<FloatProp> floats = new List<FloatProp>();
        public List<ColorProp> colors = new List<ColorProp>();
    }

    [Serializable]
    public class ShaderEntry
    {
        public string shaderName;
        public List<SlotPreset> slots = new List<SlotPreset>();
    }

    // ── Storage ───────────────────────────────────────────────────────────────

    public List<ShaderEntry> shaders = new List<ShaderEntry>();

    // ── API ───────────────────────────────────────────────────────────────────

    public SlotPreset Get(string shaderName, string slotName)
    {
        var se = shaders.Find(s => s.shaderName == shaderName);
        return se?.slots.Find(s => s.slotName == slotName);
    }

    public SlotPreset GetOrCreate(string shaderName, string slotName)
    {
        var se = shaders.Find(s => s.shaderName == shaderName);
        if (se == null) { se = new ShaderEntry { shaderName = shaderName }; shaders.Add(se); }
        var slot = se.slots.Find(s => s.slotName == slotName);
        if (slot == null) { slot = new SlotPreset { slotName = slotName }; se.slots.Add(slot); }
        return slot;
    }
}
