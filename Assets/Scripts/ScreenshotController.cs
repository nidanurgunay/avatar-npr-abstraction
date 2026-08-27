using System;
using System.IO;
using UnityEngine;
using UnityEngine.InputSystem;

// Attach to any GameObject in the screenshot scene.
//
// F11            — take one screenshot right now
// F12            — batch mode: apply next shader variant then screenshot
//                  (loops through all variants defined on ShaderSwapper)
// Ctrl + F12     — batch ALL variants automatically, one per frame
//
// Files land in:  <project>/Screenshots/
//   e.g.  Screenshots/Avaturn_VXT_XToon_2024-01-15_143022.png
public class ScreenshotController : MonoBehaviour
{
    [Header("References")]
    public ShaderSwapper shaderSwapper;

    [Header("Camera")]
    [Tooltip("Leave empty to use Camera.main.")]
    public Camera screenshotCamera;

    [Header("Output")]
    [Tooltip("Folder relative to the project root (Assets/../).")]
    public string outputFolder = "Screenshots";

    [Tooltip("Resolution multiplier over the current Game View size (1 = native, 2 = 2×).")]
    [Range(1, 4)]
    public int superSampling = 2;

    [Header("Batch")]
    [Tooltip("Seconds to wait between auto-batch shots (so the scene finishes rendering).")]
    public float batchDelay = 0.2f;

    // ── Internal ──────────────────────────────────────────────────────────────

    string _saveDir;
    bool   _batchRunning;
    int    _batchIndex;
    float  _batchTimer;

    void Awake()
    {
        if (screenshotCamera == null)
            screenshotCamera = Camera.main;

        // Editor: save next to the project folder so you can open them immediately.
        // Built player (PC / Quest): save to persistentDataPath (accessible via ADB on Quest).
        string root = Application.isEditor
            ? Path.GetDirectoryName(Application.dataPath)
            : Application.persistentDataPath;

        _saveDir = Path.Combine(root, outputFolder);
        Directory.CreateDirectory(_saveDir);
        Debug.Log($"[Screenshot] Save directory: {_saveDir}");
    }

    void Update()
    {
        var kb = Keyboard.current;
        if (kb == null) return;

        bool ctrl = kb.ctrlKey.isPressed || kb.leftCtrlKey.isPressed;

        // Ctrl + F12 → start full auto-batch
        if (ctrl && kb.f12Key.wasPressedThisFrame)
        {
            StartBatch();
            return;
        }

        // F12 → single step: advance variant then screenshot
        if (!ctrl && kb.f12Key.wasPressedThisFrame)
        {
            if (shaderSwapper != null) shaderSwapper.NextVariant();
            TakeScreenshot();
            return;
        }

        // F11 → single screenshot, no variant change
        if (kb.f11Key.wasPressedThisFrame)
        {
            TakeScreenshot();
        }

        // Run automatic batch
        if (_batchRunning) TickBatch();
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public void TakeScreenshot()
    {
        if (screenshotCamera == null) { Debug.LogWarning("[Screenshot] No camera found."); return; }

        string variant = shaderSwapper != null ? shaderSwapper.CurrentVariantName : "NoShader";
        string avatar  = shaderSwapper != null ? shaderSwapper.AvatarName        : "Avatar";
        string ts      = DateTime.Now.ToString("yyyy-MM-dd_HHmmss");
        string file    = Path.Combine(_saveDir, $"{avatar}_{variant}_{ts}.png");

        int w = Screen.width  * superSampling;
        int h = Screen.height * superSampling;

        var rt  = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        var old = screenshotCamera.targetTexture;
        screenshotCamera.targetTexture = rt;
        screenshotCamera.Render();
        screenshotCamera.targetTexture = old;

        RenderTexture.active = rt;
        var tex = new Texture2D(w, h, TextureFormat.ARGB32, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();
        RenderTexture.active = null;
        rt.Release();
        Destroy(rt);

        File.WriteAllBytes(file, tex.EncodeToPNG());
        Destroy(tex);

        Debug.Log($"[Screenshot] Saved: {file}");
    }

    // ── Batch ─────────────────────────────────────────────────────────────────

    void StartBatch()
    {
        if (shaderSwapper == null) { Debug.LogWarning("[Screenshot] ShaderSwapper not assigned."); return; }
        shaderSwapper.ResetToFirst();
        _batchIndex   = 0;
        _batchTimer   = batchDelay;   // wait one frame-delay before first shot
        _batchRunning = true;
        Debug.Log($"[Screenshot] Batch started — {shaderSwapper.VariantCount} variants.");
    }

    void TickBatch()
    {
        _batchTimer -= Time.deltaTime;
        if (_batchTimer > 0f) return;

        TakeScreenshot();
        _batchIndex++;

        if (_batchIndex >= shaderSwapper.VariantCount)
        {
            _batchRunning = false;
            Debug.Log("[Screenshot] Batch complete.");
            return;
        }

        shaderSwapper.NextVariant();
        _batchTimer = batchDelay;
    }
}
