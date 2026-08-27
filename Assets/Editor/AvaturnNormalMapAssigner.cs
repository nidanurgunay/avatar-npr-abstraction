using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

/// <summary>
/// One-shot tool: finds the embedded normal-map Texture2D sub-assets inside
/// Avaturn.glb (added there by GLTFast) and assigns them to the _BumpMap slot
/// of every V5 HierarchicalGaussian material.
///
/// Run once via  Tools > Assign Avaturn Normal Maps to V5 Materials.
/// </summary>
public static class AvaturnNormalMapAssigner
{
    const string GlbPath = "Assets/Avatars/Avaturn.glb";

    // GLTFast names each Texture2D after its *image* index inside the GLB
    // (format: "image_N").  Normal-map image indices derived from the GLTF JSON:
    //   Body   → texture 2  → source image 2  → "image_2"
    //   Eyelash→ texture 8  → source image 8  → "image_8"
    //   Head   → texture 12 → source image 12 → "image_12"
    //   Hair   → texture 18 → source image 18 → "image_18"
    //   Look   → texture 25 → source image 25 → "image_25"
    static readonly Dictionary<string, string> MatToNormalImageName = new()
    {
        { "Assets/Materials/NPR Avaturn Materials/V5 HierarchicalGaussian/V5_body.mat",    "image_2"  },
        { "Assets/Materials/NPR Avaturn Materials/V5 HierarchicalGaussian/V5_eyelash.mat", "image_8"  },
        { "Assets/Materials/NPR Avaturn Materials/V5 HierarchicalGaussian/V5_head.mat",    "image_12" },
        { "Assets/Materials/NPR Avaturn Materials/V5 HierarchicalGaussian/V5_hair.mat",    "image_18" },
        { "Assets/Materials/NPR Avaturn Materials/V5 HierarchicalGaussian/V5_look.mat",    "image_25" },
    };

    [MenuItem("Tools/Assign Avaturn Normal Maps to V5 Materials")]
    static void AssignNormalMaps()
    {
        // Load all sub-assets from the GLB and index the Texture2Ds by name.
        Object[] allAssets = AssetDatabase.LoadAllAssetsAtPath(GlbPath);
        if (allAssets == null || allAssets.Length == 0)
        {
            Debug.LogError($"AvaturnNormalMapAssigner: no sub-assets found at '{GlbPath}'. " +
                           "Make sure the file exists and has been imported by GLTFast.");
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
            Debug.LogError("AvaturnNormalMapAssigner: no Texture2D sub-assets found in the GLB. " +
                           "The file might not be imported by GLTFast (check its meta file).");
            return;
        }

        Debug.Log($"AvaturnNormalMapAssigner: found {texByName.Count} textures in GLB: " +
                  string.Join(", ", texByName.Keys));

        int assigned = 0;
        foreach (var (matPath, imageName) in MatToNormalImageName)
        {
            var mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
            if (mat == null)
            {
                Debug.LogWarning($"AvaturnNormalMapAssigner: material not found at '{matPath}'.");
                continue;
            }

            if (!texByName.TryGetValue(imageName, out Texture2D normalTex))
            {
                Debug.LogWarning($"AvaturnNormalMapAssigner: texture '{imageName}' not found in GLB " +
                                 $"(needed for {mat.name}). Available: {string.Join(", ", texByName.Keys)}");
                continue;
            }

            Undo.RecordObject(mat, "Assign Normal Map");
            mat.SetTexture("_BumpMap", normalTex);
            EditorUtility.SetDirty(mat);
            Debug.Log($"AvaturnNormalMapAssigner: assigned '{imageName}' → {mat.name}._BumpMap");
            assigned++;
        }

        AssetDatabase.SaveAssets();
        Debug.Log($"AvaturnNormalMapAssigner: done — {assigned}/{MatToNormalImageName.Count} normal maps assigned.");
    }
}
