using UnityEngine;
using UnityEngine.Rendering.Universal;

/// Exposes runtime control over KuwaharaFilterFeature and EdgeDetectionFeature.
/// 1. Assign your URP_QUEST_Renderer.asset to the _rendererData field.
/// 2. Call the setter methods from UI, NPREdgeDetectionUI, or any other script.
public class PostProcessController : MonoBehaviour
{
    [SerializeField] private ScriptableRendererData _rendererData;

    private KuwaharaFilterFeature _kuwahara;
    private EdgeDetectionFeature  _edge;

    private void Awake()
    {
        if (_rendererData == null)
        {
            Debug.LogError("PostProcessController: assign URP_QUEST_Renderer.asset in the Inspector.");
            return;
        }

        foreach (var feature in _rendererData.rendererFeatures)
        {
            if (feature is KuwaharaFilterFeature k) _kuwahara = k;
            if (feature is EdgeDetectionFeature  e) _edge     = e;
        }
    }

    // ── Kuwahara ─────────────────────────────────────────────────────────────

    public void SetKuwaharaActive(bool on)
    {
        if (_kuwahara != null) _kuwahara.SetActive(on);
    }

    public void SetKernelSize(int value)
    {
        if (_kuwahara != null) _kuwahara.settings.kernelSize = Mathf.Clamp(value, 2, 32);
    }

    public void SetSectorCount(int value)
    {
        if (_kuwahara != null) _kuwahara.settings.sectorCount = Mathf.Clamp(value, 4, 8);
    }

    public void SetSharpness(float value)
    {
        if (_kuwahara != null) _kuwahara.settings.sharpness = Mathf.Clamp(value, 1f, 18f);
    }

    public void SetHardness(float value)
    {
        if (_kuwahara != null) _kuwahara.settings.hardness = Mathf.Clamp(value, 1f, 18f);
    }

    public void SetZeroCrossing(float value)
    {
        if (_kuwahara != null) _kuwahara.settings.zeroCrossing = Mathf.Clamp(value, 0.3f, 0.8f);
    }

    // ── Edge Detection ───────────────────────────────────────────────────────

    public void SetEdgeActive(bool on)
    {
        if (_edge != null) _edge.SetActive(on);
    }

    public void SetDepthThreshold(float value)
    {
        if (_edge != null) _edge.settings.depthThreshold = Mathf.Clamp(value, 0.01f, 5f);
    }

    public void SetNormalThreshold(float value)
    {
        if (_edge != null) _edge.settings.normalThreshold = Mathf.Clamp(value, 0.05f, 5f);
    }

    public void SetColorThreshold(float value)
    {
        if (_edge != null) _edge.settings.colorThreshold = Mathf.Clamp(value, 0.01f, 1f);
    }

    public void SetDepthWeight(float value)
    {
        if (_edge != null) _edge.settings.depthWeight = Mathf.Clamp01(value);
    }

    public void SetNormalWeight(float value)
    {
        if (_edge != null) _edge.settings.normalWeight = Mathf.Clamp01(value);
    }

    public void SetColorWeight(float value)
    {
        if (_edge != null) _edge.settings.colorWeight = Mathf.Clamp01(value);
    }

    public void SetEdgeColor(Color color)
    {
        if (_edge != null) _edge.settings.edgeColor = color;
    }

    public void SetEdgeWidth(float value)
    {
        if (_edge != null) _edge.settings.edgeWidth = Mathf.Clamp(value, 0.5f, 4f);
    }

    public void SetAdaptiveStrength(float value)
    {
        if (_edge != null) _edge.settings.adaptiveStrength = Mathf.Clamp01(value);
    }
}
