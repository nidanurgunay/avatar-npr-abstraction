using UnityEngine;
using UnityEngine.InputSystem;

// Attach to the Main Camera (or any active GameObject in the scene).
//
// Shows camera position, rotation, and optional distance to a target in the top-right
// corner during Play Mode. Useful for reproducing thesis screenshot viewpoints.
//
// F9          — toggle overlay on / off
// Inspector   — assign DistanceTarget to see "Dist" from camera to that object
//
// The overlay uses IMGUI (OnGUI) so it is NOT captured by ScreenshotController's
// RenderTexture pipeline — it appears on screen for reference only.
public class CameraCoordinateOverlay : MonoBehaviour
{
    [Header("Display")]
    [Tooltip("Start with the overlay visible.")]
    public bool showOnStart = true;

    [Tooltip("Optional: assign a GameObject (e.g. your avatar) to display distance from camera.")]
    public Transform distanceTarget;

    [Header("Style")]
    [Range(10, 30)]
    public int fontSize = 15;

    [Tooltip("Panel width in screen pixels.")]
    public float panelWidth = 260f;

    // ── Internal ──────────────────────────────────────────────────────────────
    bool   _visible;
    Camera _cam;

    static readonly Color BgColor   = new Color(0f,    0f,    0f,    0.55f);
    static readonly Color LabelColor = new Color(0.55f, 0.85f, 1f,   1f);
    static readonly Color ValueColor = new Color(1f,    1f,    1f,   1f);

    GUIStyle _labelStyle;
    GUIStyle _valueStyle;
    GUIStyle _bgStyle;

    void Awake()
    {
        _cam     = GetComponent<Camera>() ?? Camera.main;
        _visible = showOnStart;
    }

    void Update()
    {
        var kb = Keyboard.current;
        if (kb != null && kb.f9Key.wasPressedThisFrame)
            _visible = !_visible;
    }

    void OnGUI()
    {
        if (!_visible) return;

        EnsureStyles();

        var t = _cam != null ? _cam.transform : transform;

        Vector3 pos = t.position;
        Vector3 rot = t.eulerAngles;

        // Build text lines
        float dist = distanceTarget != null
            ? Vector3.Distance(t.position, distanceTarget.position)
            : -1f;

        int lineCount = dist >= 0f ? 7 : 6;
        float lineH   = fontSize + 4f;
        float padH    = 10f;
        float padW    = 10f;
        float panelH  = lineH * lineCount + padH * 2f;
        float x       = Screen.width - panelWidth - 8f;
        float y       = 8f;

        // Background
        GUI.color = BgColor;
        GUI.DrawTexture(new Rect(x, y, panelWidth, panelH), Texture2D.whiteTexture);
        GUI.color = Color.white;

        float cx = x + padW;
        float cy = y + padH;

        DrawRow(ref cy, lineH, cx, "CAMERA", "", true);
        DrawRow(ref cy, lineH, cx, "Pos X", pos.x.ToString("F3"));
        DrawRow(ref cy, lineH, cx, "    Y", pos.y.ToString("F3"));
        DrawRow(ref cy, lineH, cx, "    Z", pos.z.ToString("F3"));
        DrawRow(ref cy, lineH, cx, "Rot X", rot.x.ToString("F1") + "°");
        DrawRow(ref cy, lineH, cx, "    Y", rot.y.ToString("F1") + "°");
        if (dist >= 0f)
            DrawRow(ref cy, lineH, cx, "Dist ", dist.ToString("F3"));
    }

    void DrawRow(ref float cy, float lineH, float cx, string label, string value, bool header = false)
    {
        float valX = cx + panelWidth * 0.48f;
        float w    = panelWidth - 20f;

        if (header)
        {
            GUI.Label(new Rect(cx, cy, w, lineH), label, _labelStyle);
        }
        else
        {
            GUI.Label(new Rect(cx,   cy, w * 0.45f, lineH), label, _labelStyle);
            GUI.Label(new Rect(valX, cy, w * 0.52f, lineH), value, _valueStyle);
        }
        cy += lineH;
    }

    void EnsureStyles()
    {
        if (_labelStyle != null) return;

        _bgStyle = new GUIStyle(GUI.skin.box)
        {
            normal = { background = Texture2D.whiteTexture }
        };

        _labelStyle = new GUIStyle(GUI.skin.label)
        {
            fontSize  = fontSize,
            fontStyle = FontStyle.Normal,
        };
        _labelStyle.normal.textColor = LabelColor;

        _valueStyle = new GUIStyle(GUI.skin.label)
        {
            fontSize  = fontSize,
            fontStyle = FontStyle.Bold,
            alignment = TextAnchor.MiddleRight,
        };
        _valueStyle.normal.textColor = ValueColor;
    }
}
