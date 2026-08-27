using System.Collections;
using UnityEngine;
using TMPro;

/// Creates a floating world-space text label above the avatar.
/// Attach to any avatar root GameObject and set Label Text in the Inspector.
public class AvatarLabel : MonoBehaviour
{
    [SerializeField] private string _labelText = "Avatar";
    [SerializeField] private float _heightOffset = 2.2f;
    [SerializeField] private float _fontSize = 28f;
    [SerializeField] private Color _textColor = Color.white;

    private Transform _labelTransform;

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
        var go = new GameObject("Label_" + _labelText);
        go.transform.SetParent(transform, false);
        go.transform.localPosition = new Vector3(0, _heightOffset, 0);

        // Scale: 1 canvas pixel = 0.01 m  →  100px canvas = 1m wide
        go.transform.localScale = new Vector3(0.01f, 0.01f, 0.01f);
        _labelTransform = go.transform;

        var canvas = go.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.WorldSpace;
        canvas.worldCamera = cam;

        var rt = go.GetComponent<RectTransform>();
        rt.sizeDelta = new Vector2(400f, 80f); // matches AvaturnLabel canvas dimensions

        var tmp = go.AddComponent<TextMeshProUGUI>();
        tmp.text = _labelText;
        tmp.fontSize = _fontSize;
        tmp.color = _textColor;
        tmp.alignment = TextAlignmentOptions.Center;
        tmp.fontStyle = FontStyles.Bold;
        tmp.enableWordWrapping = false;
    }

    private void LateUpdate()
    {
        if (_labelTransform == null) return;
        var cam = Camera.main ?? FindObjectOfType<Camera>();
        if (cam == null) return;
        _labelTransform.rotation = cam.transform.rotation;
    }
}
