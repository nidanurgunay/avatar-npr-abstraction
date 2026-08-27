using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

/// One-shot tool: assigns the embedded base-colour Texture2D sub-assets from
/// Avaturn.glb to the _BaseMap slot of every VXT XToon material, including the
/// newly added VXT_shoe material (image_20 = avaturn_shoes_0 base colour).
///
/// Run once via  Tools > Assign Avaturn Base Maps to VXT Materials.
public static class AvaturnBaseMapAssigner
{
    const string GlbPath = "Assets/Avatars/Avaturn.glb";

    // GLTFast names each Texture2D after its image index: "image_N"
    // Indices derived from the glTF JSON (base-colour images only):
    //   Body   → image 1  → "image_1"
    //   Eyelash→ image 7  → "image_7"
    //   Head   → image 11 → "image_11"
    //   Hair   → image 17 → "image_17"
    //   Shoe   → image 20 → "image_20"   (avaturn_shoes_0_material)
    //   Look   → image 24 → "image_24"
    static readonly Dictionary<string, string> MatToBaseImageName = new()
    {
        { "Assets/Materials/NPR Avaturn Materials/VXT XToon/VXT_body.mat",    "image_1"  },
        { "Assets/Materials/NPR Avaturn Materials/VXT XToon/VXT_eyelash.mat", "image_7"  },
        { "Assets/Materials/NPR Avaturn Materials/VXT XToon/VXT_head.mat",    "image_11" },
        { "Assets/Materials/NPR Avaturn Materials/VXT XToon/VXT_hair.mat",    "image_17" },
        { "Assets/Materials/NPR Avaturn Materials/VXT XToon/VXT_shoe.mat",    "image_20" },
        { "Assets/Materials/NPR Avaturn Materials/VXT XToon/VXT_look.mat",    "image_24" },
    };

    [MenuItem("Tools/Assign Avaturn Base Maps to VXT Materials")]
    static void AssignBaseMaps()
    {
        Object[] allAssets = AssetDatabase.LoadAllAssetsAtPath(GlbPath);
        if (allAssets == null || allAssets.Length == 0)
        {
            Debug.LogError($"AvaturnBaseMapAssigner: no sub-assets found at '{GlbPath}'.");
            return;
        }

        var texByName = new Dictionary<string, Texture2D>();
        foreach (Object asset in allAssets)
        {
            if (asset is Texture2D tex && !string.IsNullOrEmpty(tex.name))
                texByName[tex.name] = tex;
        }

        if (texByName.Count == 0)
        {
            Debug.LogError("AvaturnBaseMapAssigner: no Texture2D sub-assets found in the GLB.");
            return;
        }

        Debug.Log($"AvaturnBaseMapAssigner: found {texByName.Count} textures in GLB.");

        int assigned = 0;
        foreach (var (matPath, imageName) in MatToBaseImageName)
        {
            var mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
            if (mat == null)
            {
                Debug.LogWarning($"AvaturnBaseMapAssigner: material not found at '{matPath}'.");
                continue;
            }

            if (!texByName.TryGetValue(imageName, out Texture2D baseTex))
            {
                Debug.LogWarning($"AvaturnBaseMapAssigner: texture '{imageName}' not found in GLB " +
                                 $"(needed for {mat.name}).");
                continue;
            }

            Undo.RecordObject(mat, "Assign Base Map");
            mat.SetTexture("_BaseMap", baseTex);
            EditorUtility.SetDirty(mat);
            Debug.Log($"AvaturnBaseMapAssigner: assigned '{imageName}' → {mat.name}._BaseMap");
            assigned++;
        }

        AssetDatabase.SaveAssets();
        Debug.Log($"AvaturnBaseMapAssigner: done — {assigned}/{MatToBaseImageName.Count} base maps assigned.");
    }
}
