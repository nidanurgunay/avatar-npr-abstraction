using System.Collections;
using UnityEngine;
using TMPro;

/// Floating world-space label for Avaturn avatar GameObjects.
/// Parses the GameObject name automatically:
///   "Avaturn (NPR V8 Custom)" → "V8 Custom"
///   "Avaturn (NPR  VXT)"      → "VXT"
///   "Avaturn"                 → "Default"
/// Override with a non-empty _customLabel to bypass auto-parsing.
public class AvaturnLabel : MonoBehaviour
{
    [Tooltip("Leave empty to auto-parse from GameObject name.")]
    [SerializeField] private string _customLabel = "";
    [SerializeField] private float  _heightOffset = 2.2f;
    [SerializeField] private float  _fontSize     = 28f;
    [SerializeField] private Color  _textColor    = Color.white;

    private Transform       _labelTransform;
    private TextMeshProUGUI _tmp;

    private IEnumerator Start()
    {
        Camera cam = null;
        while (cam == null)
        {
            cam = Camera.main ?? FindObjectOfType<Camera>();
            yield return null;
        }
        CreateLabel(cam);
    }

    private void CreateLabel(Camera cam)
    {
        string text = ResolveLabel();

        var go = new GameObject("AvaturnLabel_" + text);
        go.transform.SetParent(transform, false);
        go.transform.localPosition = new Vector3(0, _heightOffset, 0);
        go.transform.localScale    = new Vector3(0.01f, 0.01f, 0.01f);
        _labelTransform = go.transform;

        var canvas = go.AddComponent<Canvas>();
        canvas.renderMode  = RenderMode.WorldSpace;
        canvas.worldCamera = cam;

        var rt = go.GetComponent<RectTransform>();
        rt.sizeDelta = new Vector2(400f, 80f);

        _tmp = go.AddComponent<TextMeshProUGUI>();
        _tmp.text               = text;
        _tmp.fontSize           = _fontSize;
        _tmp.color              = _textColor;
        _tmp.alignment          = TextAlignmentOptions.Center;
        _tmp.fontStyle          = FontStyles.Bold;
        _tmp.enableWordWrapping = false;
    }

    private void LateUpdate()
    {
        if (_labelTransform == null) return;
        var cam = Camera.main ?? FindObjectOfType<Camera>();
        if (cam != null)
            _labelTransform.rotation = cam.transform.rotation;
    }

    private string ResolveLabel()
    {
        return string.IsNullOrWhiteSpace(_customLabel)
            ? ParseLabel(gameObject.name)
            : _customLabel;
    }

    public static string ParseLabel(string goName)
    {
        const string marker = "NPR ";
        int idx = goName.IndexOf(marker, System.StringComparison.OrdinalIgnoreCase);
        if (idx < 0)
            return "Default";

        string after = goName[(idx + marker.Length)..]
                             .Trim()
                             .TrimEnd(')', ' ')
                             .Trim();

        return string.IsNullOrEmpty(after) ? "Default" : after;
    }

#if UNITY_EDITOR
    private void OnValidate()
    {
        if (_tmp != null)
            _tmp.text = ResolveLabel();
    }
#endif
}
