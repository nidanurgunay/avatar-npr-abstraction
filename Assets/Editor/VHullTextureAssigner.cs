using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

/// One-shot tool: assigns all four PBR texture maps from Avaturn.glb to every
/// VHull inverted-hull material so the surface matches the default avatar look.
///
/// Texture indices extracted from the GLB's glTF JSON:
///   GLTFast format — metallicRoughnessTexture: G=roughness, B=metallic
///                  — occlusionTexture:          R=occlusion
///
/// Run via  Tools > Assign All Textures to VHull Materials
public static class VHullTextureAssigner
{
    const string GlbPath = "Assets/Avatars/Avaturn.glb";

    // (albedo, normal, metallicRoughness, occlusion) — null = not present in GLB
    static readonly Dictionary<string, (string albedo, string normal, string mr, string occ)> MatToImages = new()
    {
        {
            "Assets/Materials/NPR Avaturn Materials/V1 InvertedHull/VHull_body.mat",
            ("image_1",  "image_2",  "image_0",  null)
        },
        {
            "Assets/Materials/NPR Avaturn Materials/V1 InvertedHull/VHull_eyelash.mat",
            ("image_7",  "image_8",  "image_9",  null)
        },
        {
            "Assets/Materials/NPR Avaturn Materials/V1 InvertedHull/VHull_head.mat",
            ("image_11", "image_12", "image_10", null)
        },
        {
            "Assets/Materials/NPR Avaturn Materials/V1 InvertedHull/VHull_hair.mat",
            ("image_17", "image_18", null,        null)   // hair has no metallic-roughness
        },
        {
            "Assets/Materials/NPR Avaturn Materials/V1 InvertedHull/VHull_shoe.mat",
            ("image_20", "image_21", "image_19", "image_22")
        },
        {
            "Assets/Materials/NPR Avaturn Materials/V1 InvertedHull/VHull_look.mat",
            ("image_24", "image_25", "image_23", "image_26")
        },
    };

    // Per-material PBR scalar defaults.
    // _Metallic  : cloth/skin = 0 (dielectric); shoe = 1 (has metallic buckles/eyelets)
    // _Smoothness: 1.0 for all — the roughness map (G channel) controls smoothness per-pixel
    static readonly Dictionary<string, (float metallic, float smoothness)> MatScalars = new()
    {
        { "VHull_body.mat",    (0f, 1f) },
        { "VHull_eyelash.mat", (0f, 1f) },
        { "VHull_head.mat",    (0f, 1f) },
        { "VHull_hair.mat",    (0f, 1f) },
        { "VHull_shoe.mat",    (1f, 1f) },
        { "VHull_look.mat",    (0f, 1f) },
    };

    [MenuItem("Tools/Assign All Textures to VHull Materials")]
    static void AssignTextures()
    {
        Object[] allAssets = AssetDatabase.LoadAllAssetsAtPath(GlbPath);
        if (allAssets == null || allAssets.Length == 0)
        {
            Debug.LogError($"VHullTextureAssigner: no sub-assets at '{GlbPath}'.");
            return;
        }

        var texByName = new Dictionary<string, Texture2D>();
        foreach (Object a in allAssets)
            if (a is Texture2D t && !string.IsNullOrEmpty(t.name))
                texByName[t.name] = t;

        Debug.Log($"VHullTextureAssigner: found {texByName.Count} textures in GLB.");

        int matCount = 0;
        foreach (var (matPath, (albedoName, normalName, mrName, occName)) in MatToImages)
        {
            var mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
            if (mat == null) { Debug.LogWarning($"VHullTextureAssigner: mat not found: {matPath}"); continue; }

            Undo.RecordObject(mat, "Assign VHull Textures");

            Assign(mat, "_MainTex",          albedoName, texByName);
            Assign(mat, "_BumpMap",           normalName, texByName);
            Assign(mat, "_MetallicGlossMap",  mrName,     texByName);
            Assign(mat, "_OcclusionMap",      occName,    texByName);

            if (mrName != null)
            {
                string matName = System.IO.Path.GetFileName(matPath);
                var (metallic, smoothness) = MatScalars.TryGetValue(matName, out var s) ? s : (0f, 0.5f);
                mat.SetFloat("_Metallic",   metallic);
                mat.SetFloat("_Smoothness", smoothness);
            }
            if (occName != null) mat.SetFloat("_OcclusionStrength", 1f);

            EditorUtility.SetDirty(mat);
            matCount++;
        }

        AssetDatabase.SaveAssets();
        Debug.Log($"VHullTextureAssigner: done — {matCount} materials updated.");
    }

    static void Assign(Material mat, string prop, string imageName,
                       Dictionary<string, Texture2D> texByName)
    {
        if (imageName == null) return;
        if (texByName.TryGetValue(imageName, out Texture2D tex))
        {
            mat.SetTexture(prop, tex);
            Debug.Log($"  {mat.name}.{prop} ← {imageName}");
        }
        else
            Debug.LogWarning($"  {mat.name}.{prop}: '{imageName}' not found in GLB");
    }
}
