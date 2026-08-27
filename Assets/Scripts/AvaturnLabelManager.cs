using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;
using TMPro;
#if UNITY_EDITOR
using UnityEditor;
#endif

/// Attach to any GameObject (e.g. Main Camera).
/// Scans the direct children of <see cref="_containerName"/> for names starting with
/// <see cref="_avatarPrefix"/> and spawns a floating world-space label above each one.
/// Visible in both Scene view and Play mode.
///
/// Default values work for the Avaturn scene ("Avatars" / "Avaturn").
/// For the Jade scene set _containerName = "NPR Jade" and _avatarPrefix = "Jade".
///
/// Parsing rules (same as AvaturnLabel):
///   "Avaturn (NPR V8 Custom)" -> "V8 Custom"
///   "Avaturn (NPR  VXT)"      -> "VXT"
///   "Avaturn"                 -> full name fallback
///   "Jade (Original)"         -> full name fallback
[ExecuteAlways]
public class AvaturnLabelManager : MonoBehaviour
{
    [Tooltip("Name of the scene GameObject whose direct children are the avatar roots.")]
    [SerializeField] private string _containerName = "Avatars";

    [Tooltip("Only children whose names START with this prefix receive a label. Leave empty to label all children.")]
    [SerializeField] private string _avatarPrefix  = "Avaturn";

    [SerializeField] private float _heightOffset = 2.2f;
    [SerializeField] private float _fontSize     = 28f;
    [SerializeField] private Color _textColor    = Color.white;

    private readonly List<(Transform avatar, Transform label)> _pairs =
        new List<(Transform, Transform)>();

    private void OnEnable()
    {
        // During editor startup the scene may not be loaded yet; defer so
        // GetRootGameObjects() is called only after the scene is fully ready.
#if UNITY_EDITOR
        if (!Application.isPlaying)
        {
            EditorApplication.delayCall += () => { if (this != null) Rebuild(); };
            return;
        }
#endif
        Rebuild();
    }
    private void OnDisable() => ClearLabels();

    private void OnValidate()
    {
#if UNITY_EDITOR
        // Defer Rebuild out of OnValidate — creating GameObjects during OnValidate
        // triggers SendMessage which Unity forbids in that callback.
        EditorApplication.delayCall += () => { if (this != null) Rebuild(); };
#endif
    }

    // No per-frame rotation override — the label's initial world rotation is set
    // once in CreateLabel (pointing toward the camera at spawn time).
    // Because the label is a child of the avatar it rotates with it naturally,
    // and the user can freely adjust the rotation in the Inspector.

    private void Rebuild()
    {
        ClearLabels();

        Camera cam = Camera.main ?? FindObjectOfType<Camera>();

        foreach (var root in AvaturnRoots())
            _pairs.Add((root, CreateLabel(root, cam)));
    }

    private void ClearLabels()
    {
        foreach (var (_, label) in _pairs)
        {
            if (label == null) continue;

            if (Application.isPlaying)
                Destroy(label.gameObject);
            else
                DestroyImmediate(label.gameObject);
        }
        _pairs.Clear();
    }

    private IEnumerable<Transform> AvaturnRoots()
    {
        var scene = SceneManager.GetActiveScene();
        if (!scene.isLoaded) yield break;

        var avatarsGO = GameObject.Find(_containerName);
        if (avatarsGO == null) yield break;

        bool filterByPrefix = !string.IsNullOrEmpty(_avatarPrefix);
        foreach (Transform child in avatarsGO.transform)
        {
            if (!filterByPrefix || child.name.StartsWith(_avatarPrefix, System.StringComparison.OrdinalIgnoreCase))
                yield return child;
        }
    }

    private Transform CreateLabel(Transform avatar, Camera cam)
    {
        string parsed = AvaturnLabel.ParseLabel(avatar.name);
        // "Default" means no NPR marker found — fall back to the full GameObject name so
        // Jade avatars ("Jade (Original)", "Jade (SG2)", …) still get meaningful labels.
        string text = parsed == "Default" ? avatar.name : parsed;

        var go = new GameObject("AvaturnLabel_" + text);
        go.hideFlags = HideFlags.DontSave; // don't serialize into the scene file
        go.transform.SetParent(avatar, false);
        go.transform.localPosition = new Vector3(0f, _heightOffset, 0f);
        go.transform.localScale    = new Vector3(0.01f, 0.01f, 0.01f);
        // Face the camera once at creation time. After this the rotation is yours
        // to adjust; it will also rotate with the parent avatar as expected.
        if (cam != null)
            go.transform.rotation = cam.transform.rotation;

        var canvas = go.AddComponent<Canvas>();
        canvas.renderMode  = RenderMode.WorldSpace;
        canvas.worldCamera = cam;

        var rt = go.GetComponent<RectTransform>();
        rt.sizeDelta = new Vector2(400f, 80f);

        var tmp = go.AddComponent<TextMeshProUGUI>();
        tmp.text               = text;
        tmp.fontSize           = _fontSize;
        tmp.color              = _textColor;
        tmp.alignment          = TextAlignmentOptions.Center;
        tmp.fontStyle          = FontStyles.Bold;
        tmp.enableWordWrapping = false;

        return go.transform;
    }
}
