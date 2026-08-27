using UnityEngine;
using UnityEditor;

/// Prints all texture sub-assets inside Avaturn.glb with their fileID (localIdentifierInFile).
/// Usage: Tools → List Avaturn Texture Sub-Assets
public class AvaturnTextureInspector
{
    [MenuItem("Tools/List Avaturn Texture Sub-Assets")]
    static void ListTextures()
    {
        string glbPath = "Assets/Avatars/Avaturn.glb";
        var allAssets = AssetDatabase.LoadAllAssetsAtPath(glbPath);

        if (allAssets == null || allAssets.Length == 0)
        {
            Debug.LogError("[AvaturnTextureInspector] No assets found at: " + glbPath);
            return;
        }

        Debug.Log($"[AvaturnTextureInspector] Found {allAssets.Length} sub-assets in {glbPath}:");

        foreach (var asset in allAssets)
        {
            if (asset == null) continue;

            if (AssetDatabase.TryGetGUIDAndLocalFileIdentifier(asset, out string guid, out long localID))
            {
                Debug.Log($"  [{asset.GetType().Name}] name='{asset.name}'  fileID={localID}  guid={guid}");
            }
        }
    }
}
