using UnityEngine;

/// Controls the V5_HierarchicalGaussian material properties at runtime
/// by writing into a MaterialPropertyBlock on every Renderer child of the avatar.
///
/// Setup:
///   1. Add this component to any GameObject (e.g. the avatar root or a manager).
///   2. Assign the avatar root (the Avaturn or Jade root GO) to _avatarRoot.
///   3. Call the setter methods from UI sliders, buttons, or other scripts.
public class HierarchicalShaderController : MonoBehaviour
{
    [Tooltip("Root GameObject of the avatar. All child Renderers will receive the property changes.")]
    [SerializeField] private GameObject _avatarRoot;

    private Renderer[] _renderers;
    private MaterialPropertyBlock _block;

    private void Awake()
    {
        if (_avatarRoot == null) _avatarRoot = gameObject;

        // Collect every Renderer in the avatar hierarchy (body, head, hair, eyes…)
        _renderers = _avatarRoot.GetComponentsInChildren<Renderer>(true);
        _block = new MaterialPropertyBlock();
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    private void SetFloat(string prop, float value)
    {
        foreach (var r in _renderers)
        {
            r.GetPropertyBlock(_block);   // read existing block so we don't erase other props
            _block.SetFloat(prop, value);
            r.SetPropertyBlock(_block);
        }
    }

    private void SetColor(string prop, Color value)
    {
        foreach (var r in _renderers)
        {
            r.GetPropertyBlock(_block);
            _block.SetColor(prop, value);
            r.SetPropertyBlock(_block);
        }
    }

    // ── Layer toggles ─────────────────────────────────────────────────────────

    public void SetDepthEdgeEnabled(bool on)
        => SetFloat("_EnableDepthEdge", on ? 1f : 0f);

    public void SetNormalEdgeEnabled(bool on)
        => SetFloat("_EnableNormalEdge", on ? 1f : 0f);

    public void SetColorEdgeEnabled(bool on)
        => SetFloat("_EnableColorEdge", on ? 1f : 0f);

    public void SetGaussBlurEnabled(bool on)
        => SetFloat("_EnableGaussBlur", on ? 1f : 0f);

    // ── Depth layer ───────────────────────────────────────────────────────────

    public void SetDepthThreshold(float v)
        => SetFloat("_HDepthThreshold", Mathf.Clamp(v, 0.001f, 0.2f));

    public void SetDepthWeight(float v)
        => SetFloat("_HDepthWeight", Mathf.Clamp01(v));

    // ── Normal layer ──────────────────────────────────────────────────────────

    public void SetNormalThreshold(float v)
        => SetFloat("_HNormalThreshold", Mathf.Clamp(v, 0.05f, 1.0f));

    public void SetNormalWeight(float v)
        => SetFloat("_HNormalWeight", Mathf.Clamp01(v));

    // ── Color layer ───────────────────────────────────────────────────────────

    public void SetColorThreshold(float v)
        => SetFloat("_HColorThreshold", Mathf.Clamp(v, 0.01f, 0.5f));

    public void SetColorWeight(float v)
        => SetFloat("_HColorWeight", Mathf.Clamp01(v));

    // ── Appearance ────────────────────────────────────────────────────────────

    public void SetEdgeWidth(float v)
        => SetFloat("_HEdgeWidth", Mathf.Clamp(v, 0.5f, 10f));

    public void SetEdgeStrength(float v)
        => SetFloat("_HEdgeStrength", Mathf.Clamp01(v));

    public void SetAdaptiveStrength(float v)
        => SetFloat("_HAdaptiveStrength", Mathf.Clamp01(v));

    public void SetEdgeColor(Color c)
        => SetColor("_HEdgeColor", c);

    // ── Gaussian preblur weights ───────────────────────────────────────────────

    public void SetBlurRadius(float v)
        => SetFloat("_HBlurRadius", Mathf.Clamp(v, 0.1f, 5f));

    public void SetCenterWeight(float v)
        => SetFloat("_HCenterWeight", Mathf.Clamp01(v));

    public void SetCardinalWeight(float v)
        => SetFloat("_HCardinalWeight", Mathf.Clamp(v, 0f, 0.5f));

    public void SetDiagonalWeight(float v)
        => SetFloat("_HDiagonalWeight", Mathf.Clamp(v, 0f, 0.25f));
}
