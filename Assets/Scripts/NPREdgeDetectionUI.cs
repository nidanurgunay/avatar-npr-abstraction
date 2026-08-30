using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.InputSystem;

/// In-VR panel for live-tuning Avatar/MetaNPR edge-detection parameters.
/// Techniques: Derivative | Sobel | Normal+Fresnel | Gauss Sobel | Hierarchical | Kuwahara | X-Toon
/// Controls: B/Y/Tab = toggle | Trigger DOWN = select row / pick technique | Trigger HOLD = drag locked slider | Grip = step cursor row
public class NPREdgeDetectionUI : MonoBehaviour
{
    [Header("Panel placement")]
    [SerializeField] private Transform _anchor;
    [SerializeField] private float _spawnDistance = 1.5f;
    [SerializeField] private float _spawnYOffset   = 0f;

    [Header("Panel size")]
    [SerializeField] private float _panelWidth = 1.5f;

    private const float CANVAS_W = 1000f;

    // ── Technique ─────────────────────────────────────────────────────────────
    private enum Technique { Derivative = 0, Sobel = 1, NormalEdge = 2, GaussSobel = 3, Hierarchical = 4, Kuwahara = 5, Toon = 6, XToon = 7, InvertedHull = 8 }
    private static readonly string[] TechniqueNames    = { "Derivative", "Sobel", "Normal Edge", "Gauss Sobel", "Hierarchical", "Kuwahara", "Toon", "X-Toon", "Inverted Hull" };
    private static readonly string[] TechniqueKeywords = { "", "EFFECT_SOBEL", "EFFECT_NORMAL_EDGE", "EFFECT_GAUSS_SOBEL", "EFFECT_HIERARCHICAL", "EFFECT_KUWAHARA", "EFFECT_TOON", "EFFECT_XTOON", "" };
    private Technique _currentTechnique = Technique.Derivative;

    // ── Display mode (cycles on the Mode row) ────────────────────────────────
    // 0 = NPR ON  (ENABLE_NPR_EDGES + current technique)
    // 1 = DEFAULT (Meta PBR as-is — NPR off, outline off)
    private int _displayMode = 0;

    // ── Row data ──────────────────────────────────────────────────────────────
    private enum RowKind { Float, Color, TechSelector, TechOption, ShaderToggle, CompareDefault, Action, KeywordCycle }
    private const int ACTION_SAVE = 0;
    private const int ACTION_LOAD = 1;

    private struct Row
    {
        public RowKind     kind;
        public string      label;
        public string      propName;
        public float       currentValue;
        public float       min, max, step;
        public int         colorIndex;       // also used as cycleIndex for KeywordCycle
        public int         techniqueFilter;  // -1 = always visible, 0/1/2 = per technique
        public string      dependsOnProp;    // if set, hidden when the named ShaderToggle is OFF
        public string[]    cycleLabels;      // KeywordCycle: display names for each option
        public string[]    cycleKeywords;    // KeywordCycle: shader keyword per option
        public Text        valueText;
        public Image       highlight;
        public Text        cursorText;
        public BoxCollider collider;
        public Image       sliderFill;
        public GameObject  rowGo;
    }

    // Section label GameObjects that should hide with a specific technique
    private readonly List<(int filter, GameObject go)> _sectionLabels = new();

    // ── Color presets ─────────────────────────────────────────────────────────
    private static readonly (string name, Color color)[] ColorPresets =
    {
        ("Black",    Color.black),
        ("Navy",     new Color(0.05f, 0.05f, 0.25f)),
        ("Dark Red", new Color(0.25f, 0.02f, 0.02f)),
        ("Brown",    new Color(0.20f, 0.10f, 0.00f)),
        ("Gray",     new Color(0.30f, 0.30f, 0.30f)),
        ("White",    Color.white),
        ("Cyan",     new Color(0.00f, 0.60f, 0.80f)),
        ("Gold",     new Color(0.80f, 0.60f, 0.00f)),
    };

    [System.NonSerialized] private readonly List<Row> _rows = new();


    private int  _cursor           = -1;
    private int  _hoveredRow       = -1;
    private int  _draggingRow      = -1;
    private bool _techDropdownOpen = false;
    private bool _visible;

    private GameObject    _panel;
    private RectTransform _panelRt;
    private ScrollRect    _scrollRect;
    private const float   SCROLL_SPEED = 0.8f;
    private Transform     _camTransform;
    private Transform     _controllerTransform;
    private MonoBehaviour _locomotion;   // OVRPlayerController disabled while panel is open
    private LineRenderer  _lr;

    [System.NonSerialized] private readonly List<Material> _nprMaterials = new();
    private float _materialRefreshTimer;
    private const float MATERIAL_REFRESH = 3f;

    private float _decCooldown;
    private const float FIRST_REPEAT = 0.45f;
    private const float HOLD_REPEAT  = 0.12f;

    private float _debugTimer;
    private readonly RaycastHit[] _hitBuffer = new RaycastHit[16];

    // ─────────────────────────────────────────────────────────────────────────
    void Start()
    {
        Debug.Log("[NPREdgeDetectionUI] Start() on " + gameObject.name);

        // Ensure freeze controller exists in scene (auto-add so user doesn't need to wire it manually)
        if (FindObjectOfType<AvatarFreezeController>() == null)
            gameObject.AddComponent<AvatarFreezeController>();

        // Disable SampleSceneLocomotion (Meta Avatar SDK sample, lives on CenterEyeAnchor)
        // so thumbstick scroll doesn't also move the scene while the panel is open
        var loco = FindObjectOfType<SampleSceneLocomotion>();
        if (loco != null) _locomotion = loco;
        else Debug.LogWarning("[NPREdgeDetectionUI] SampleSceneLocomotion not found — scene will still move while panel is open.");

        ResolveCamera();
        ResolveController();
        RefreshNPRMaterials();
        BuildPanel();
        BuildRayLine();
        PushAllValues();
        SetVisible(false);
        Debug.Log("[NPREdgeDetectionUI] Ready — B/Y/Tab to open.");
    }

    // ── Material collection ───────────────────────────────────────────────────
    void RefreshNPRMaterials()
    {
        _nprMaterials.Clear();
        foreach (var rend in FindObjectsOfType<Renderer>())
        {
            if (rend == null) continue;
            foreach (var mat in rend.sharedMaterials)
            {
                if (mat != null && mat.shader != null &&
                    (mat.shader.name.Contains("MetaNPR") || mat.shader.name.Contains("Avatar/Meta")) &&
                    !_nprMaterials.Contains(mat))
                    _nprMaterials.Add(mat);
            }
        }
        Debug.Log("[NPREdgeDetectionUI] Found " + _nprMaterials.Count + " MetaNPR material(s).");
    }

    void SetShaderFloat(string prop, float val)
    {
        bool hit = false;
        foreach (var mat in _nprMaterials)
            if (mat != null && mat.HasProperty(prop)) { mat.SetFloat(prop, val); hit = true; }
        if (!hit) { RefreshNPRMaterials(); foreach (var mat in _nprMaterials) if (mat != null && mat.HasProperty(prop)) mat.SetFloat(prop, val); }
    }

    void SetShaderColor(string prop, Color c)
    {
        bool hit = false;
        foreach (var mat in _nprMaterials)
            if (mat != null && mat.HasProperty(prop)) { mat.SetColor(prop, c); hit = true; }
        if (!hit) { RefreshNPRMaterials(); foreach (var mat in _nprMaterials) if (mat != null && mat.HasProperty(prop)) mat.SetColor(prop, c); }
    }

    void PushAllValues()
    {
        RefreshNPRMaterials();
        foreach (var row in _rows)
        {
            if (row.kind == RowKind.Float)
                SetShaderFloat(row.propName, row.currentValue);
            else if (row.kind == RowKind.Color)
            {
                var (_, c) = ColorPresets[row.colorIndex];
                SetShaderColor(row.propName, c);
            }
            else if (row.kind == RowKind.ShaderToggle)
                SetShaderFloat(row.propName, row.currentValue);
            else if (row.kind == RowKind.KeywordCycle)
                ApplyKeywordCycle(row);
        }
        ApplyTechniqueKeywords();
        ApplyTechniqueVisibility();
        UpdateTechniqueLabel();

        // Re-apply display mode so the periodic refresh doesn't undo it
        ApplyDisplayMode();

        Debug.Log("[NPREdgeDetectionUI] PushAll mats=" + _nprMaterials.Count
                  + " technique=" + TechniqueNames[(int)_currentTechnique]);
    }

    // ── Technique selection ───────────────────────────────────────────────────
    void SelectTechnique(int index)
    {
        _currentTechnique = (Technique)index;
        ApplyTechniqueKeywords();
        ApplyTechniqueVisibility();
        UpdateTechniqueLabel();
        foreach (var row in _rows)
            if (row.kind == RowKind.Float && (row.techniqueFilter == -1 || row.techniqueFilter == (int)_currentTechnique))
                SetShaderFloat(row.propName, row.currentValue);
    }

    void ApplyTechniqueKeywords()
    {
        bool isInvertedHull = _currentTechnique == Technique.InvertedHull;
        foreach (var mat in _nprMaterials)
        {
            if (mat == null) continue;
            foreach (var kw in TechniqueKeywords) if (kw.Length > 0) mat.DisableKeyword(kw);
            string active = TechniqueKeywords[(int)_currentTechnique];
            if (active.Length > 0) mat.EnableKeyword(active);
            // Inverted Hull: no screen-space edges, outline forced ON
            if (isInvertedHull)
            {
                mat.DisableKeyword("ENABLE_NPR_EDGES");
                mat.SetFloat("_OutlineEnabled", 1f);
            }
            // Other techniques: _OutlineEnabled controlled by the toggle row — don't override it
        }
        // Sync toggle UI when InvertedHull forces outline on
        if (isInvertedHull)
            SetOutlineToggleUI(1f);
    }

    void SetOutlineToggleUI(float value)
    {
        for (int i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            if (row.kind == RowKind.ShaderToggle && row.propName == "_OutlineEnabled")
            {
                row.currentValue = value;
                bool on = value > 0.5f;
                if (row.valueText != null) { row.valueText.text = on ? "ON" : "OFF"; row.valueText.color = on ? new Color(0.4f, 0.9f, 1f) : new Color(0.5f, 0.5f, 0.5f); }
                _rows[i] = row;
                break;
            }
        }
    }

    void ApplyTechniqueVisibility()
    {
        int t = (int)_currentTechnique;
        for (int i = 0; i < _rows.Count; i++)
        {
            if (_rows[i].techniqueFilter == -1) continue;
            if (_rows[i].rowGo == null) continue;
            if (!string.IsNullOrEmpty(_rows[i].dependsOnProp)) continue; // resolved separately
            _rows[i].rowGo.SetActive(_rows[i].techniqueFilter == t);
        }
        foreach (var (filter, go) in _sectionLabels)
            if (go != null) go.SetActive(filter == t);
        ResolveAllDependencies();
    }

    void ResolveAllDependencies()
    {
        int t = (int)_currentTechnique;
        for (int i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            if (row.rowGo == null || string.IsNullOrEmpty(row.dependsOnProp)) continue;
            bool techVisible = row.techniqueFilter == -1 || row.techniqueFilter == t;
            bool toggleOn    = true;
            for (int j = 0; j < _rows.Count; j++)
                if (_rows[j].kind == RowKind.ShaderToggle && _rows[j].propName == row.dependsOnProp)
                { toggleOn = _rows[j].currentValue > 0.5f; break; }
            row.rowGo.SetActive(techVisible && toggleOn);
        }
    }

    void UpdateTechniqueLabel()
    {
        string indicator = _techDropdownOpen ? " [-]" : " [+]";
        for (int i = 0; i < _rows.Count; i++)
        {
            var r = _rows[i];
            if (r.kind == RowKind.TechSelector && r.valueText != null)
            {
                r.valueText.text = TechniqueNames[(int)_currentTechnique] + indicator;
            }
            else if (r.kind == RowKind.TechOption)
            {
                bool active = r.colorIndex == (int)_currentTechnique;
                if (r.valueText != null)
                {
                    r.valueText.text  = active ? "ACTIVE" : "";
                    r.valueText.color = active ? new Color(0.4f, 0.9f, 1f) : Color.clear;
                }
                if (r.highlight != null)
                    r.highlight.color = active ? new Color(0.2f, 0.6f, 1f, 0.28f) : Color.clear;
            }
        }
    }

    void ToggleTechDropdown()
    {
        _techDropdownOpen = !_techDropdownOpen;
        for (int i = 0; i < _rows.Count; i++)
            if (_rows[i].kind == RowKind.TechOption && _rows[i].rowGo != null)
                _rows[i].rowGo.SetActive(_techDropdownOpen);
        UpdateTechniqueLabel();
    }

    // ─────────────────────────────────────────────────────────────────────────
    void Update()
    {
        _debugTimer += Time.deltaTime;
        if (_debugTimer >= 5f)
        {
            _debugTimer = 0f;
            Debug.Log("[NPREdgeDetectionUI] Heartbeat visible=" + _visible + " mats=" + _nprMaterials.Count);
        }

        if (_visible)
        {
            _materialRefreshTimer += Time.deltaTime;
            if (_materialRefreshTimer >= MATERIAL_REFRESH) { _materialRefreshTimer = 0f; PushAllValues(); }
        }

        // B (right top) = NPR UI   |   Y (left top) = Avatar Switcher (handled in AvatarSwitcher)
        // Use Controller.RTouch explicitly — Controller.Active fails when activeControllerType
        // is None or LTouch (same bug that broke Y; A/X/B/Y all need explicit controller).
        bool bBtn = OVRInput.GetDown(OVRInput.RawButton.B, OVRInput.Controller.RTouch);
        bool tab  = Keyboard.current != null && Keyboard.current.tabKey.wasPressedThisFrame;
        if (bBtn || tab) SetVisible(!_visible);

        // Thumbstick scroll — either stick, Y axis
        if (_visible && _scrollRect != null)
        {
            float scrollY = OVRInput.Get(OVRInput.Axis2D.PrimaryThumbstick).y
                          + OVRInput.Get(OVRInput.Axis2D.SecondaryThumbstick).y;
            if (Mathf.Abs(scrollY) > 0.1f)
                _scrollRect.verticalNormalizedPosition = Mathf.Clamp01(
                    _scrollRect.verticalNormalizedPosition + scrollY * SCROLL_SPEED * Time.deltaTime);
        }

        if (!_visible) { if (_lr != null) _lr.gameObject.SetActive(false); return; }

        if (_camTransform != null)
        {
            Vector3 toCam = _camTransform.position - _panel.transform.position;
            toCam.y = 0f;
            if (toCam.sqrMagnitude > 0.001f)
                _panel.transform.rotation = Quaternion.LookRotation(-toCam.normalized, Vector3.up);
        }

        UpdateRayInteraction();
    }

    void UpdateRayInteraction()
    {
        if (_controllerTransform == null) return;

        var ray = new Ray(_controllerTransform.position, _controllerTransform.forward);

        bool trigHeld = OVRInput.Get(OVRInput.Button.PrimaryIndexTrigger)
                     || OVRInput.Get(OVRInput.Button.SecondaryIndexTrigger);
        bool trigDown = OVRInput.GetDown(OVRInput.Button.PrimaryIndexTrigger)
                     || OVRInput.GetDown(OVRInput.Button.SecondaryIndexTrigger);
        bool trigUp   = OVRInput.GetUp(OVRInput.Button.PrimaryIndexTrigger)
                     || OVRInput.GetUp(OVRInput.Button.SecondaryIndexTrigger);
        bool rightGripDown = OVRInput.GetDown(OVRInput.Button.PrimaryHandTrigger);
        bool rightGripHeld = OVRInput.Get(OVRInput.Button.PrimaryHandTrigger);
        bool leftGripDown  = OVRInput.GetDown(OVRInput.Button.SecondaryHandTrigger);
        bool leftGripHeld  = OVRInput.Get(OVRInput.Button.SecondaryHandTrigger);
        bool gripDown = rightGripDown || leftGripDown;
        bool gripHeld = rightGripHeld || leftGripHeld;

        // Release drag lock when trigger is released
        if (trigUp) _draggingRow = -1;

        // While dragging: project ray onto the locked row's plane only — ignore hover
        if (trigHeld && _draggingRow >= 0)
        {
            DragSliderByRay(_draggingRow, ray);
            if (_lr != null)
            {
                _lr.gameObject.SetActive(true);
                _lr.SetPosition(0, ray.origin);
                _lr.SetPosition(1, ray.origin + ray.direction * 3f);
            }
            // Grip still steps the cursor row during drag
            if (_cursor >= 0 && _cursor < _rows.Count && _rows[_cursor].kind == RowKind.Float)
            {
                float gripDir = rightGripDown || rightGripHeld ? -1f : 1f;
                if (gripDown) { AdjustStep(gripDir); _decCooldown = FIRST_REPEAT; }
                else if (gripHeld) { _decCooldown -= Time.deltaTime; if (_decCooldown <= 0f) { _decCooldown = HOLD_REPEAT; AdjustStep(gripDir); } }
                else _decCooldown = 0f;
            }
            return;
        }

        // ── Normal hover detection ────────────────────────────────────────────
        int hitCount = Physics.RaycastNonAlloc(ray, _hitBuffer, 5f);
        int     newHover    = -1;
        float   closest     = float.MaxValue;
        Vector3 rowHitPoint = Vector3.zero;

        for (int j = 0; j < hitCount; j++)
        {
            var h = _hitBuffer[j];
            for (int i = 0; i < _rows.Count; i++)
            {
                if (_rows[i].collider != null && _rows[i].collider == h.collider && h.distance < closest)
                { closest = h.distance; newHover = i; rowHitPoint = h.point; }
            }
        }

        if (_lr != null)
        {
            _lr.gameObject.SetActive(true);
            _lr.SetPosition(0, ray.origin);
            _lr.SetPosition(1, newHover >= 0 ? rowHitPoint : ray.origin + ray.direction * 3f);
        }

        if (newHover != _hoveredRow)
        {
            SetHover(_hoveredRow, false);
            _hoveredRow  = newHover;
            // _cursor is NOT auto-updated on hover — only updated on trigger down
            SetHover(_hoveredRow, true);
            _decCooldown = 0f;
        }

        // ── Trigger DOWN: select hovered row ─────────────────────────────────
        if (trigDown && _hoveredRow >= 0)
        {
            _cursor = _hoveredRow;
            var row = _rows[_hoveredRow];
            switch (row.kind)
            {
                case RowKind.CompareDefault:
                    CycleDisplayMode(_hoveredRow);
                    break;

                case RowKind.Action:
                    if (row.colorIndex == ACTION_SAVE) SavePreset(_hoveredRow);
                    else                               LoadPreset(_hoveredRow);
                    break;

                case RowKind.TechSelector:
                    ToggleTechDropdown();
                    break;

                case RowKind.TechOption:
                    SelectTechnique(row.colorIndex);
                    if (_techDropdownOpen) ToggleTechDropdown();
                    break;

                case RowKind.Float:
                    _draggingRow = _hoveredRow;
                    DragSlider(_hoveredRow, rowHitPoint);
                    break;

                case RowKind.Color:
                    AdjustColor(+1);
                    break;

                case RowKind.KeywordCycle:
                    CycleKeyword(_hoveredRow, +1);
                    break;

                case RowKind.ShaderToggle:
                {
                    var r = _rows[_hoveredRow];
                    r.currentValue    = r.currentValue > 0.5f ? 0f : 1f;
                    bool on           = r.currentValue > 0.5f;
                    r.valueText.text  = on ? "ON" : "OFF";
                    r.valueText.color = on ? new Color(0.4f, 0.9f, 1f) : new Color(0.5f, 0.5f, 0.5f);
                    _rows[_hoveredRow] = r;
                    SetShaderFloat(r.propName, r.currentValue);
                    ResolveAllDependencies();
                    break;
                }
            }
        }

        // ── Grip: step / cycle the cursor row (regardless of hover position) ─
        if (_cursor >= 0 && _cursor < _rows.Count)
        {
            var curRow = _rows[_cursor];
            if (curRow.kind == RowKind.Float)
            {
                float gripDir = rightGripDown || rightGripHeld ? -1f : 1f;
                if (gripDown) { AdjustStep(gripDir); _decCooldown = FIRST_REPEAT; }
                else if (gripHeld) { _decCooldown -= Time.deltaTime; if (_decCooldown <= 0f) { _decCooldown = HOLD_REPEAT; AdjustStep(gripDir); } }
                else _decCooldown = 0f;
            }
            else if (curRow.kind == RowKind.Color)
            {
                if (gripDown) AdjustColor(-1);
            }
            else if (curRow.kind == RowKind.KeywordCycle)
            {
                if (gripDown) CycleKeyword(_cursor, -1);
            }
            else if (curRow.kind == RowKind.TechSelector)
            {
                if (gripDown) ToggleTechDropdown();
            }
        }
    }

    void DragSliderByRay(int rowIndex, Ray ray)
    {
        var row = _rows[rowIndex];
        if (row.sliderFill == null) return;
        var bgRt = row.sliderFill.rectTransform.parent as RectTransform;
        if (bgRt == null) return;
        if (!new Plane(bgRt.forward, bgRt.position).Raycast(ray, out float enter)) return;
        DragSlider(rowIndex, ray.GetPoint(enter));
    }

    void DragSlider(int rowIndex, Vector3 worldHitPoint)
    {
        var row  = _rows[rowIndex];
        var bgRt = row.sliderFill.rectTransform.parent as RectTransform;
        if (bgRt == null) return;
        float width = bgRt.rect.width;
        if (width < 1f) return;

        Vector3 localPt = bgRt.InverseTransformPoint(worldHitPoint);
        float   t       = Mathf.Clamp01((localPt.x + width * 0.5f) / width);
        float   newVal  = Mathf.Lerp(row.min, row.max, t);

        row.currentValue = newVal;
        row.valueText.text = newVal.ToString("F3");
        row.sliderFill.rectTransform.anchorMax = new Vector2(t, 1f);
        _rows[rowIndex] = row;
        SetShaderFloat(row.propName, newVal);
    }

    void AdjustStep(float direction)
    {
        if (_cursor < 0 || _cursor >= _rows.Count) return;
        var row = _rows[_cursor];
        if (row.kind != RowKind.Float) return;
        float next = Mathf.Clamp(row.currentValue + direction * row.step, row.min, row.max);
        float t    = Mathf.InverseLerp(row.min, row.max, next);
        row.currentValue = next;
        row.valueText.text = next.ToString("F3");
        if (row.sliderFill != null) row.sliderFill.rectTransform.anchorMax = new Vector2(t, 1f);
        _rows[_cursor] = row;
        SetShaderFloat(row.propName, next);
    }

    void AdjustColor(int direction)
    {
        if (_cursor < 0 || _cursor >= _rows.Count) return;
        var row = _rows[_cursor];
        if (row.kind != RowKind.Color) return;
        row.colorIndex = (int)Mathf.Repeat(row.colorIndex + direction, ColorPresets.Length);
        var (cname, c) = ColorPresets[row.colorIndex];
        row.valueText.text  = cname;
        row.valueText.color = (c.r + c.g + c.b < 0.3f) ? new Color(0.7f, 0.7f, 0.7f) : c;
        _rows[_cursor] = row;
        SetShaderColor(row.propName, c);
    }

    void SetHover(int index, bool on)
    {
        if (index < 0 || index >= _rows.Count) return;
        var row = _rows[index];
        if (row.highlight  != null) row.highlight.color  = on ? new Color(0.25f, 0.65f, 1f, 0.25f) : Color.clear;
        if (row.cursorText != null) row.cursorText.color = on ? new Color(0.4f,  0.9f,  1f)         : Color.clear;
    }

    void SetVisible(bool v)
    {
        _visible = v;
        _panel.SetActive(v);
        if (_locomotion != null) _locomotion.enabled = !v;   // freeze locomotion while panel is open
        if (v)
        {
            PlacePanel();
            // Rebuild only our panel — Canvas.ForceUpdateCanvases() rebuilds ALL canvases and
            // triggers an IMGUI EndLayoutGroup error inside Meta SDK UI components.
            if (_panelRt != null)
                LayoutRebuilder.ForceRebuildLayoutImmediate(_panelRt);
            _materialRefreshTimer = MATERIAL_REFRESH;
            PushAllValues();
        }
        if (!v && _lr != null) _lr.gameObject.SetActive(false);
    }

    void ApplyPanelScale() { if (_panelRt != null) _panelRt.localScale = Vector3.one * (_panelWidth / CANVAS_W); }
    void OnValidate()      => ApplyPanelScale();

    void PlacePanel()
    {
        if (_camTransform == null) { ResolveCamera(); if (_camTransform == null) return; }
        ApplyPanelScale();
        Vector3 fwd = _camTransform.forward; fwd.y = 0f;
        if (fwd.sqrMagnitude < 0.001f) fwd = Vector3.forward;
        fwd.Normalize();
        _panel.transform.SetPositionAndRotation(
            _camTransform.position + fwd * _spawnDistance + Vector3.up * _spawnYOffset,
            Quaternion.LookRotation(fwd, Vector3.up));
    }

    // ─────────────────────────────────────────────────────────────────────────
    void BuildPanel()
    {
        _panel = new GameObject("NPREdgePanel");
        _panel.transform.SetParent(transform, false);

        var canvas = _panel.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.WorldSpace;

        _panelRt = _panel.GetComponent<RectTransform>();
        _panelRt.sizeDelta = new Vector2(CANVAS_W, 900f);  // visible window height
        ApplyPanelScale();

        // Background fills the visible window
        var bg = Go("BG", _panel.transform);
        bg.AddComponent<Image>().color = new Color(0.07f, 0.07f, 0.07f, 0.95f);
        Stretch(bg);

        // ScrollRect sits over the full panel
        var scrollGo = Go("Scroll", _panel.transform);
        Stretch(scrollGo);
        _scrollRect = scrollGo.AddComponent<ScrollRect>();
        _scrollRect.horizontal     = false;
        _scrollRect.vertical       = true;
        _scrollRect.movementType   = ScrollRect.MovementType.Clamped;
        _scrollRect.inertia        = false;

        // Viewport masks content that has scrolled out of view
        var viewportGo  = Go("Viewport", scrollGo.transform);
        Stretch(viewportGo);
        var viewportImg = viewportGo.AddComponent<Image>();
        viewportImg.color = Color.white;           // must be non-zero alpha for Mask stencil
        viewportGo.AddComponent<Mask>().showMaskGraphic = false;

        // Content: top-anchored, auto-height via ContentSizeFitter
        var contentGo = Go("Content", viewportGo.transform);
        var contentRt = contentGo.GetComponent<RectTransform>();
        contentRt.anchorMin = new Vector2(0f, 1f);
        contentRt.anchorMax = new Vector2(1f, 1f);
        contentRt.pivot     = new Vector2(0.5f, 1f);
        contentRt.offsetMin = contentRt.offsetMax = Vector2.zero;

        var vlg = contentGo.AddComponent<VerticalLayoutGroup>();
        vlg.padding               = new RectOffset(30, 30, 24, 24);
        vlg.spacing               = 8;
        vlg.childControlWidth     = true;
        vlg.childControlHeight    = false;
        vlg.childForceExpandWidth = true;

        var csf = contentGo.AddComponent<ContentSizeFitter>();
        csf.verticalFit   = ContentSizeFitter.FitMode.PreferredSize;
        csf.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;

        _scrollRect.viewport = viewportGo.GetComponent<RectTransform>();
        _scrollRect.content  = contentRt;

        var t = contentGo.transform;
        Label(t, "NPR EDGE DETECTION",                                      28, new Color(0.4f, 0.9f, 1f));
        Label(t, "Trigger = select/drag   Grip = step selected   B/Y = close", 16, new Color(0.5f, 0.5f, 0.5f));
        Space(t, 6);

        // ── A/B compare: toggle all NPR effects off to see base avatar ────────
        AddCompareDefaultRow(t);
        AddActionRow(t, "Save Preset", ACTION_SAVE);
        AddActionRow(t, "Load Preset", ACTION_LOAD);
        Space(t, 4);

        // ── Technique selector (cycles on trigger/grip) ──────────────────────
        AddTechSelectorRow(t);
        Space(t, 6);


        // ── Derivative parameters (technique 0) ──────────────────────────────
        SectionLabel(t, "Derivative Edge", 0);
        AddFloatRow(t, 0, "Toon Bands",    "_ToonBands",        2f,    8f,    1f,     4f);
        AddFloatRow(t, 0, "Toon Strength", "_ToonStrength",     0f,    1f,    0.01f,  0f);
        AddFloatRow(t, 0, "Color Thresh",  "_ColorThreshold",   0f,    0.5f,  0.005f, 0.05f);
        AddFloatRow(t, 0, "Color Max",     "_ColorEdgeMax",     0.05f, 2f,    0.05f,  0.50f);
        AddFloatRow(t, 0, "Color Str",     "_ColorStrength",    0f,    1f,    0.01f,  1.00f);
        AddFloatRow(t, 0, "Normal Thresh", "_NormalThreshold",  0f,    0.5f,  0.005f, 0.05f);
        AddFloatRow(t, 0, "Normal Max",    "_NormalEdgeMax",    0.05f, 2f,    0.05f,  0.50f);
        AddFloatRow(t, 0, "Normal Str",    "_NormalStrength",   0f,    1f,    0.01f,  1.00f);

        // ── Sobel parameters (technique 1) ───────────────────────────────────
        SectionLabel(t, "Sobel Edge", 1);
        AddShaderToggleRow(t, 1, "Sobel On",     "_EnableSobel",    true);
        AddFloatRow(t, 1, "Sample Dist",   "_SobelSampleDist", 0f,   10f,  0.1f,  0.5f,  "_EnableSobel");
        AddFloatRow(t, 1, "Threshold",     "_SobelThreshold",  0f,   1f,   0.01f, 0.15f, "_EnableSobel");
        AddFloatRow(t, 1, "Sobel Max",     "_SobelMax",        0.1f, 8f,   0.1f,  2.0f,  "_EnableSobel");
        AddFloatRow(t, 1, "Seam Limit",    "_SobelSeamLimit",  0f,   1f,   0.01f, 0.60f, "_EnableSobel");
        AddFloatRow(t, 1, "Strength",      "_SobelStrength",   0f,   1f,   0.01f, 1.00f, "_EnableSobel");

        // ── Normal+Fresnel parameters (technique 2) ──────────────────────────
        SectionLabel(t, "Normal+Fresnel Edge", 2);
        AddFloatRow(t, 2, "Norm Thresh",    "_NormalEdgeThreshold",  0f,    1f,   0.01f, 0.30f);
        AddFloatRow(t, 2, "Norm Strength",  "_NormalEdgeStrength",   0f,    1f,   0.01f, 0.80f);
        AddFloatRow(t, 2, "Norm Smooth",    "_NormalEdgeSmoothness", 0.01f, 0.5f, 0.01f, 0.10f);
        AddFloatRow(t, 2, "Fresnel Thresh", "_FresnelEdgeThreshold", 0f,    1f,   0.01f, 0.30f);
        AddFloatRow(t, 2, "Fresnel Str",    "_FresnelEdgeStrength",  0f,    1f,   0.01f, 0.50f);

        // ── Gaussian Sobel parameters (technique 3) ──────────────────────────
        SectionLabel(t, "Gaussian Sobel Edge", 3);
        AddShaderToggleRow(t, 3, "Gauss Blur",  "_GSobelEnableGaussBlur", true);
        AddFloatRow(t, 3, "Sample Dist",   "_GSobelSampleDist",     0f,    10f,  0.1f,    1.00f);
        AddFloatRow(t, 3, "Blur Radius",   "_GSobelBlurRadius",     0f,    5f,   0.1f,    1.00f,   "_GSobelEnableGaussBlur");
        AddFloatRow(t, 3, "Center W",      "_GSobelCenterWeight",   0.1f,  0.5f, 0.005f,  0.25f,   "_GSobelEnableGaussBlur");
        AddFloatRow(t, 3, "Cardinal W",    "_GSobelCardinalWeight", 0f,    0.3f, 0.005f,  0.125f,  "_GSobelEnableGaussBlur");
        AddFloatRow(t, 3, "Diagonal W",    "_GSobelDiagonalWeight", 0f,    0.1f, 0.002f,  0.0625f, "_GSobelEnableGaussBlur");
        AddFloatRow(t, 3, "Threshold",     "_GSobelThreshold",      0f,    0.5f, 0.005f,  0.15f);
        AddFloatRow(t, 3, "Thresh Min",    "_GSobelThreshMin",      0f,    1f,   0.05f,   0.50f);
        AddFloatRow(t, 3, "Thresh Max",    "_GSobelThreshMax",      1f,    5f,   0.1f,    1.50f);
        AddFloatRow(t, 3, "Tightness",     "_GSobelTightness",      0f,    1f,   0.05f,   0.20f);
        AddFloatRow(t, 3, "Power Curve",   "_GSobelPowerCurve",     0.5f,  5f,   0.1f,    1.50f);
        AddFloatRow(t, 3, "Strength",      "_GSobelStrength",       0f,    1f,   0.01f,   1.00f);
        AddColorRow( t, 3, "Edge Color",   "_GSobelEdgeColor",      0);

        // ── Hierarchical parameters (technique 4) ────────────────────────────
        SectionLabel(t, "Hierarchical Edge", 4);
        AddFloatRow(t, 4, "Depth Thresh",  "_HDepthThreshold",   0.001f, 0.2f, 0.005f, 0.02f);
        AddFloatRow(t, 4, "Norm Thresh",   "_HNormalThreshold",  0.05f,  1f,   0.01f,  0.30f);
        AddFloatRow(t, 4, "Color Thresh",  "_HColorThreshold",   0.01f,  0.5f, 0.01f,  0.10f);
        AddShaderToggleRow(t, 4, "Gauss Blur",   "_HEnableGaussBlur",  false);
        AddFloatRow(t, 4, "Blur Radius",   "_HBlurRadius",       0f,    5f,    0.1f,   1.00f,   "_HEnableGaussBlur");
        AddFloatRow(t, 4, "Center W",      "_HCenterWeight",     0.1f,  0.5f,  0.005f, 0.25f,   "_HEnableGaussBlur");
        AddFloatRow(t, 4, "Cardinal W",    "_HCardinalWeight",   0f,    0.3f,  0.005f, 0.125f,  "_HEnableGaussBlur");
        AddFloatRow(t, 4, "Diagonal W",    "_HDiagonalWeight",   0f,    0.1f,  0.002f, 0.0625f, "_HEnableGaussBlur");
        AddFloatRow(t, 4, "Depth Weight",  "_HDepthWeight",      0f,     1f,   0.01f,  0.80f);
        AddFloatRow(t, 4, "Norm Weight",   "_HNormalWeight",     0f,     1f,   0.01f,  0.80f);
        AddFloatRow(t, 4, "Color Weight",  "_HColorWeight",      0f,     1f,   0.01f,  0.60f);
        AddFloatRow(t, 4, "Edge Width",    "_HEdgeWidth",        0.5f,   10f,  0.1f,   1.50f);
        AddFloatRow(t, 4, "Adaptive Str",  "_HAdaptiveStrength", 0f,     1f,   0.01f,  0.50f);
        AddColorRow( t, 4, "Edge Color",   "_HEdgeColor",        0);
        AddShaderToggleRow(t, 4, "Skin Discard",  "_HEnableSkinDiscard",  false);
        AddFloatRow(t, 4, "Skin Hue Min",  "_HSkinHueMin",  0f, 0.2f, 0.005f, 0.02f, "_HEnableSkinDiscard");
        AddFloatRow(t, 4, "Skin Hue Max",  "_HSkinHueMax",  0f, 0.2f, 0.005f, 0.12f, "_HEnableSkinDiscard");
        AddFloatRow(t, 4, "Skin Sat Min",  "_HSkinSatMin",  0f, 1f,   0.01f,  0.15f, "_HEnableSkinDiscard");

        // ── Kuwahara parameters (technique 5 — anisotropic) ──────────────────
        SectionLabel(t, "Kuwahara Filter", 5);
        AddFloatRow(t, 5, "Radius",    "_K2Radius",   0.5f, 20f,   0.1f,   2.0f);
        AddFloatRow(t, 5, "Strength",  "_K2Strength", 0f,   1f,    0.01f,  1.0f);
        AddFloatRow(t, 5, "Alpha",     "_K2Alpha",    0.5f, 3f,    0.05f,  1.0f);
        AddFloatRow(t, 5, "Q Sharp",   "_K2Q",        1f,   16f,   0.5f,   8.0f);
        AddFloatRow(t, 5, "Tau Floor", "_K2Tau",      0.001f,0.1f, 0.002f, 0.02f);

        // ── Kuwahara+Sobel parameters (technique 6) ───────────────────────────
        SectionLabel(t, "Kuwahara+Sobel", 6);
        AddFloatRow(t, 6, "Kuw Radius",   "_K2SKuwRadius",   0.5f, 20f,   0.1f,    2.0f);
        AddFloatRow(t, 6, "Kuw Strength", "_K2SKuwStrength", 0f,   1f,    0.01f,   0.8f);
        AddFloatRow(t, 6, "Kuw Alpha",    "_K2SKuwAlpha",    0.5f, 3f,    0.05f,   1.0f);
        AddFloatRow(t, 6, "Kuw Q",        "_K2SKuwQ",        1f,   16f,   0.5f,    8.0f);
        AddFloatRow(t, 6, "Kuw Tau",      "_K2SKuwTau",      0.001f,0.1f, 0.002f,  0.02f);
        AddShaderToggleRow(t, 6, "Gauss Blur",  "_K2SEnableGaussBlur", true);
        AddFloatRow(t, 6, "Sample Dist",  "_K2SSobelSampleDist", 0f,   10f,   0.1f,    1.0f);
        AddFloatRow(t, 6, "Blur Radius",  "_K2SBlurRadius",      0f,   5f,    0.1f,    1.0f,    "_K2SEnableGaussBlur");
        AddFloatRow(t, 6, "Center W",     "_K2SCenterWeight",    0.1f, 0.5f,  0.005f,  0.25f,   "_K2SEnableGaussBlur");
        AddFloatRow(t, 6, "Cardinal W",   "_K2SCardinalWeight",  0f,   0.3f,  0.005f,  0.125f,  "_K2SEnableGaussBlur");
        AddFloatRow(t, 6, "Diagonal W",   "_K2SDiagonalWeight",  0f,   0.1f,  0.002f,  0.0625f, "_K2SEnableGaussBlur");
        AddFloatRow(t, 6, "Threshold",    "_K2SThreshold",       0f,   0.5f,  0.005f,  0.15f);
        AddFloatRow(t, 6, "Thresh Min",   "_K2SThreshMin",       0f,   1f,    0.05f,   0.5f);
        AddFloatRow(t, 6, "Thresh Max",   "_K2SThreshMax",       1f,   5f,    0.1f,    1.5f);
        AddFloatRow(t, 6, "Tightness",    "_K2STightness",       0f,   1f,    0.05f,   0.2f);
        AddFloatRow(t, 6, "Power Curve",  "_K2SPowerCurve",      0.5f, 5f,    0.1f,    1.5f);
        AddFloatRow(t, 6, "Edge Str",     "_K2SSobelStrength",   0f,   1f,    0.01f,   1.0f);

        // ── Kuwahara+Hier parameters (technique 7) ───────────────────────────
        SectionLabel(t, "Kuw+Hier", 7);
        AddFloatRow(t, 7, "Kuw Radius",   "_K2HKuwRadius",   0.5f,  20f,   0.1f,    2.0f);
        AddFloatRow(t, 7, "Kuw Strength", "_K2HKuwStrength", 0f,    1f,    0.01f,   0.8f);
        AddFloatRow(t, 7, "Kuw Alpha",    "_K2HKuwAlpha",    0.5f,  3f,    0.05f,   1.0f);
        AddFloatRow(t, 7, "Kuw Q",        "_K2HKuwQ",        1f,    16f,   0.5f,    8.0f);
        AddFloatRow(t, 7, "Kuw Tau",      "_K2HKuwTau",      0.001f,0.1f,  0.002f,  0.02f);
        AddFloatRow(t, 7, "Depth Thresh", "_K2HDepthThreshold",  0.001f, 0.2f,  0.005f, 0.02f);
        AddFloatRow(t, 7, "Norm Thresh",  "_K2HNormalThreshold", 0.05f,  1f,    0.01f,  0.3f);
        AddFloatRow(t, 7, "Color Thresh", "_K2HColorThreshold",  0.01f,  0.5f,  0.01f,  0.1f);
        AddFloatRow(t, 7, "Depth Weight", "_K2HDepthWeight",     0f,     1f,    0.01f,  0.8f);
        AddFloatRow(t, 7, "Norm Weight",  "_K2HNormalWeight",    0f,     1f,    0.01f,  0.8f);
        AddFloatRow(t, 7, "Color Weight", "_K2HColorWeight",     0f,     1f,    0.01f,  0.6f);
        AddFloatRow(t, 7, "Edge Width",   "_K2HEdgeWidth",       0.5f,   10f,   0.1f,   1.5f);
        AddFloatRow(t, 7, "Adaptive Str", "_K2HAdaptiveStrength",0f,     1f,    0.01f,  0.5f);
        AddFloatRow(t, 7, "Hier Tight",   "_K2HHierTightness",   0f,     1f,    0.05f,  0.5f);
        AddFloatRow(t, 7, "Hier Str",     "_K2HHStrength",       0f,     1f,    0.01f,  1.0f);
        AddShaderToggleRow(t, 7, "Color Blur",   "_K2HEnableGaussBlur", false);
        AddFloatRow(t, 7, "Blur Radius",  "_K2HBlurRadius",      0f,    5f,    0.1f,    1.0f,    "_K2HEnableGaussBlur");
        AddFloatRow(t, 7, "Center W",     "_K2HCenterWeight",    0.1f,  0.5f,  0.005f,  0.25f,   "_K2HEnableGaussBlur");
        AddFloatRow(t, 7, "Cardinal W",   "_K2HCardinalWeight",  0f,    0.3f,  0.005f,  0.125f,  "_K2HEnableGaussBlur");
        AddFloatRow(t, 7, "Diagonal W",   "_K2HDiagonalWeight",  0f,    0.1f,  0.002f,  0.0625f, "_K2HEnableGaussBlur");
        AddColorRow( t, 7, "Edge Color",  "_K2HEdgeColor",       0);

        // ── Toon parameters (technique 8 — posterise only, no edges) ─────────
        SectionLabel(t, "Toon / Cel Shader", 8);
        AddFloatRow(t, 8, "Color Bands",   "_ToonColorBands",        2f, 8f,  1f,    4f);
        AddFloatRow(t, 8, "Posterize Str", "_ToonPosterizeStrength", 0f, 1f,  0.01f, 0.85f);
        AddFloatRow(t, 8, "Saturation",    "_ToonSaturation",        0f, 3f,  0.05f, 1.0f);

        // ── Toon+Sobel parameters (technique 9) ──────────────────────────────
        SectionLabel(t, "Toon+Sobel", 9);
        AddFloatRow(t, 9, "Color Bands",   "_TSColorBands",        2f,    8f,    1f,      4f);
        AddFloatRow(t, 9, "Posterize Str", "_TSPosterizeStrength", 0f,    1f,    0.01f,   0.85f);
        AddFloatRow(t, 9, "Saturation",    "_TSSaturation",        0f,    3f,    0.05f,   1.0f);
        AddShaderToggleRow(t, 9, "Gauss Blur",  "_TSEnableGaussBlur", true);
        AddFloatRow(t, 9, "Sample Dist",   "_TSSobelSampleDist",   0f,    10f,   0.1f,    1.0f);
        AddFloatRow(t, 9, "Blur Radius",   "_TSBlurRadius",        0f,    5f,    0.1f,    1.0f,   "_TSEnableGaussBlur");
        AddFloatRow(t, 9, "Center W",      "_TSCenterWeight",      0.1f,  0.5f,  0.005f,  0.25f,  "_TSEnableGaussBlur");
        AddFloatRow(t, 9, "Cardinal W",    "_TSCardinalWeight",    0f,    0.3f,  0.005f,  0.125f, "_TSEnableGaussBlur");
        AddFloatRow(t, 9, "Diagonal W",    "_TSDiagonalWeight",    0f,    0.1f,  0.002f,  0.0625f,"_TSEnableGaussBlur");
        AddFloatRow(t, 9, "Threshold",     "_TSThreshold",         0f,    0.5f,  0.005f,  0.15f);
        AddFloatRow(t, 9, "Thresh Min",    "_TSThreshMin",         0f,    1f,    0.05f,   0.5f);
        AddFloatRow(t, 9, "Thresh Max",    "_TSThreshMax",         1f,    5f,    0.1f,    1.5f);
        AddFloatRow(t, 9, "Tightness",     "_TSTightness",         0f,    1f,    0.05f,   0.2f);
        AddFloatRow(t, 9, "Power Curve",   "_TSPowerCurve",        0.5f,  5f,    0.1f,    1.5f);
        AddFloatRow(t, 9, "Edge Str",      "_TSSobelStrength",     0f,    1f,    0.01f,   1.0f);

        // ── Toon+Hier parameters (technique 10) ───────────────────────────────
        SectionLabel(t, "Toon+Hier", 10);
        AddFloatRow(t, 10, "Color Bands",   "_THColorBands",        2f,     8f,    1f,     4f);
        AddFloatRow(t, 10, "Posterize Str", "_THPosterizeStrength", 0f,     1f,    0.01f,  0.85f);
        AddFloatRow(t, 10, "Saturation",    "_THSaturation",        0f,     3f,    0.05f,  1.0f);
        AddFloatRow(t, 10, "Depth Thresh",  "_THDepthThreshold",    0.001f, 0.2f,  0.005f, 0.02f);
        AddFloatRow(t, 10, "Norm Thresh",   "_THNormalThreshold",   0.05f,  1f,    0.01f,  0.3f);
        AddFloatRow(t, 10, "Color Thresh",  "_THColorThreshold",    0.01f,  0.5f,  0.01f,  0.1f);
        AddFloatRow(t, 10, "Depth Weight",  "_THDepthWeight",       0f,     1f,    0.01f,  0.8f);
        AddFloatRow(t, 10, "Norm Weight",   "_THNormalWeight",      0f,     1f,    0.01f,  0.8f);
        AddFloatRow(t, 10, "Color Weight",  "_THColorWeight",       0f,     1f,    0.01f,  0.6f);
        AddFloatRow(t, 10, "Edge Width",    "_THEdgeWidth",         0.5f,   10f,   0.1f,   1.5f);
        AddFloatRow(t, 10, "Adaptive Str",  "_THAdaptiveStrength",  0f,     1f,    0.01f,  0.5f);
        AddFloatRow(t, 10, "Hier Tight",    "_THHierTightness",     0f,     1f,    0.05f,  0.5f);
        AddFloatRow(t, 10, "Hier Str",      "_THHStrength",         0f,     1f,    0.01f,  1.0f);
        AddShaderToggleRow(t, 10, "Color Blur",  "_THEnableGaussBlur", false);
        AddFloatRow(t, 10, "Blur Radius",   "_THBlurRadius",        0f,    5f,    0.1f,    1.0f,    "_THEnableGaussBlur");
        AddFloatRow(t, 10, "Center W",      "_THCenterWeight",      0.1f,  0.5f,  0.005f,  0.25f,   "_THEnableGaussBlur");
        AddFloatRow(t, 10, "Cardinal W",    "_THCardinalWeight",    0f,    0.3f,  0.005f,  0.125f,  "_THEnableGaussBlur");
        AddFloatRow(t, 10, "Diagonal W",    "_THDiagonalWeight",    0f,    0.1f,  0.002f,  0.0625f, "_THEnableGaussBlur");
        AddColorRow( t, 10, "Edge Color",   "_THEdgeColor",         0);

        // ── Halftone parameters (technique 11) ───────────────────────────────
        SectionLabel(t, "Halftone", 11);
        AddFloatRow(t, 11, "Dot Scale",    "_HTScale",            2f,    100f,  1f,     30f);
        AddFloatRow(t, 11, "Sharpness",    "_HTSharpness",        1f,    50f,   0.5f,   10f);
        AddFloatRow(t, 11, "Grid Angle",   "_HTAngle",            0f,    90f,   1f,     45f);
        AddFloatRow(t, 11, "Tone Bias",    "_HTToneBias",        -0.5f,  0.5f,  0.01f,  0f);
        AddColorRow( t, 11, "Ink Color",   "_HTInkColor",         1);
        AddColorRow( t, 11, "Paper Color", "_HTPaperColor",       5);
        AddFloatRow(t, 11, "Tex Influence","_HTTextureInfluence",  0f,    1f,    0.05f,  0.5f);
        AddFloatRow(t, 11, "Strength",     "_HTStrength",          0f,    1f,    0.01f,  1.0f);

        // ── Hatching parameters (technique 12) ───────────────────────────────
        SectionLabel(t, "Hatching", 12);
        AddFloatRow(t, 12, "Hatch Scale",  "_HatScale",           1f,    100f,  1f,     20f);
        AddFloatRow(t, 12, "Primary Angle","_HatAngle",           0f,    180f,  1f,     45f);
        AddFloatRow(t, 12, "Cross Angle",  "_HatCrossAngle",      0f,    180f,  1f,     135f);
        AddFloatRow(t, 12, "Thickness",    "_HatThickness",       0.01f, 0.5f,  0.01f,  0.15f);
        AddFloatRow(t, 12, "Tone Bias",    "_HatToneBias",       -0.5f,  0.5f,  0.01f,  0f);
        AddColorRow( t, 12, "Ink Color",   "_HatInkColor",        1);
        AddColorRow( t, 12, "Paper Color", "_HatPaperColor",      5);
        AddFloatRow(t, 12, "Tex Influence","_HatTextureInfluence", 0f,    1f,    0.05f,  0.5f);
        AddFloatRow(t, 12, "Strength",     "_HatStrength",         0f,    1f,    0.01f,  1.0f);

        // ── X-Toon 2D Ramp parameters (technique 13) ─────────────────────────────
        // Mirrors NPREffect_XToon.cginc / Avatar-Meta-UGB.shader _XToon* properties.
        // The _XToonRamp texture is set on the material in the Inspector.
        SectionLabel(t, "X-Toon 2D Ramp", 13);
        AddFloatRow(t, 13, "Light Sens",   "_XToonLightSensitivity",   0f,     1f,    0.01f,  1.0f);
        AddFloatRow(t, 13, "Ramp Smooth",  "_XToonRampSmoothing",      0f,     0.1f,  0.005f, 0.01f);
        AddColorRow( t, 13, "Shadow Col",  "_XToonShadowColor",        1);
        AddFloatRow(t, 13, "Shadow Str",   "_XToonShadowStrength",     0f,     1f,    0.01f,  0.6f);
        AddKeywordCycleRow(t, 13, "Detail Mode",
            new[] { "Depth", "Curvature", "Manual" },
            new[] { "_DETAILMODE_DEPTH", "_DETAILMODE_CURVATURE", "_DETAILMODE_MANUAL" });
        AddFloatRow(t, 13, "Detail Bias",  "_XToonDetailBias",         0f,     1f,    0.01f,  0.5f);
        AddFloatRow(t, 13, "Depth Near",   "_XToonDepthNear",          0.1f,   20f,   0.5f,   5.0f);
        AddFloatRow(t, 13, "Depth Far",    "_XToonDepthFar",           1f,     100f,  1f,     50.0f);
        AddFloatRow(t, 13, "Manual Det",   "_XToonManualDetail",       0f,     1f,    0.01f,  0f);
        AddColorRow( t, 13, "Specular Col","_XToonSpecularColor",      5);
        AddFloatRow(t, 13, "Spec Size",    "_XToonSpecularSize",       0f,     1f,    0.005f, 0.03f);
        AddFloatRow(t, 13, "Spec Smooth",  "_XToonSpecularSmoothness", 0.001f, 0.5f,  0.01f,  0.02f);
        AddFloatRow(t, 13, "Spec Str",     "_XToonSpecularStrength",   0f,     1f,    0.01f,  0.5f);
        AddFloatRow(t, 13, "Lighting Str", "_XToonLightingStrength",   0f,     1f,    0.01f,  1.0f);
        AddShaderToggleRow(t, 13, "Enable Rim",   "_XToonEnableRim",    false);
        AddColorRow( t, 13, "Rim Color",   "_XToonRimColor",           5,      "_XToonEnableRim");
        AddFloatRow(t, 13, "Rim Power",    "_XToonRimPower",           0.5f,   10f,   0.1f,   3.0f,  "_XToonEnableRim");
        AddFloatRow(t, 13, "Rim Thresh",   "_XToonRimThreshold",       0f,     1f,    0.01f,  0.1f,  "_XToonEnableRim");
        AddFloatRow(t, 13, "Rim Str",      "_XToonRimStrength",        0f,     1f,    0.01f,  0.3f,  "_XToonEnableRim");
        AddFloatRow(t, 13, "Norm Smooth",  "_XToonNormalSmoothing",    0f,     1f,    0.01f,  0f);
        AddShaderToggleRow(t, 13, "Sobel On",     "_XToonEnableSobel",  false);
        AddColorRow( t, 13, "Sobel Color", "_XToonSobelEdgeColor",     0,      "_XToonEnableSobel");
        AddFloatRow(t, 13, "Sobel Thresh", "_XToonSobelThreshold",     0.001f, 1f,    0.01f,  0.15f, "_XToonEnableSobel");
        AddFloatRow(t, 13, "Sobel Dist",   "_XToonSobelSampleDist",    0.1f,   10f,   0.1f,   1.0f,  "_XToonEnableSobel");
        AddFloatRow(t, 13, "Sobel Str",    "_XToonSobelStrength",      0f,     1f,    0.01f,  1.0f,  "_XToonEnableSobel");

        // ── Inverted Hull Outline (always visible — optional on every technique) ─
        Space(t, 4);
        SectionLabel(t, "Inverted Hull Outline");
        AddShaderToggleRow(t, -1, "Enable Outline", "_OutlineEnabled", false);
        AddFloatRow(t, -1, "Width",         "_OutlineWidth",  0f, 0.05f, 0.001f, 0.003f);
        AddColorRow(t, -1, "Outline Color", "_OutlineColor",  0);

        // ── Color (always visible) ────────────────────────────────────────────
        Space(t, 4);
        SectionLabel(t, "Line Color");
        AddColorRow(t, -1, "Color", "_InnerLineColor", 0);

        ApplyTechniqueVisibility();
    }

    // ── Row builders ──────────────────────────────────────────────────────────

    void AddCompareDefaultRow(Transform parent)
    {
        var (rowGo, hl, valTxt, curTxt, col, _) = MakeRowShell(parent, "Mode [cycle]", hasSlider: false);
        valTxt.text  = "NPR ON";
        valTxt.color = new Color(0.4f, 0.9f, 1f);
        _rows.Add(new Row
        {
            kind = RowKind.CompareDefault, label = "A/B Compare", techniqueFilter = -1,
            currentValue = 1f,
            valueText = valTxt, highlight = hl, cursorText = curTxt,
            collider = col, rowGo = rowGo,
        });
    }

    void AddActionRow(Transform parent, string label, int actionId)
    {
        var (rowGo, hl, valTxt, curTxt, col, _) = MakeRowShell(parent, label, hasSlider: false);
        valTxt.text  = "[ click ]";
        valTxt.color = new Color(0.4f, 0.9f, 1f);
        _rows.Add(new Row
        {
            kind = RowKind.Action, label = label, colorIndex = actionId,
            techniqueFilter = -1,
            valueText = valTxt, highlight = hl, cursorText = curTxt,
            collider = col, rowGo = rowGo,
        });
    }

    void SavePreset(int rowIndex)
    {
        foreach (var row in _rows)
        {
            if (row.kind == RowKind.Float || row.kind == RowKind.ShaderToggle)
                PlayerPrefs.SetFloat("NPR_" + row.propName, row.currentValue);
            else if (row.kind == RowKind.Color)
                PlayerPrefs.SetInt("NPR_ci_" + row.propName, row.colorIndex);
            else if (row.kind == RowKind.KeywordCycle)
                PlayerPrefs.SetInt("NPR_kc_" + row.label, row.colorIndex);
        }
        PlayerPrefs.Save();
        var r = _rows[rowIndex];
        r.valueText.text  = "✓ Saved";
        r.valueText.color = new Color(0.3f, 0.9f, 0.3f);
        _rows[rowIndex] = r;
        Debug.Log("[NPREdgeDetectionUI] Preset saved to PlayerPrefs.");
    }

    void LoadPreset(int rowIndex)
    {
        for (int i = 0; i < _rows.Count; i++)
        {
            var row = _rows[i];
            if (row.kind == RowKind.Float || row.kind == RowKind.ShaderToggle)
            {
                string key = "NPR_" + row.propName;
                if (!PlayerPrefs.HasKey(key)) continue;
                float val = PlayerPrefs.GetFloat(key);
                row.currentValue = val;
                if (row.kind == RowKind.Float)
                {
                    row.valueText.text = val.ToString("F3");
                    if (row.sliderFill != null)
                        row.sliderFill.rectTransform.anchorMax =
                            new Vector2(Mathf.InverseLerp(row.min, row.max, val), 1f);
                }
                else
                {
                    bool on = val > 0.5f;
                    row.valueText.text  = on ? "ON" : "OFF";
                    row.valueText.color = on ? new Color(0.4f, 0.9f, 1f) : new Color(0.5f, 0.5f, 0.5f);
                }
                _rows[i] = row;
                SetShaderFloat(row.propName, val);
            }
            else if (row.kind == RowKind.Color)
            {
                string key = "NPR_ci_" + row.propName;
                if (!PlayerPrefs.HasKey(key)) continue;
                int idx = Mathf.Clamp(PlayerPrefs.GetInt(key), 0, ColorPresets.Length - 1);
                row.colorIndex = idx;
                var (cname, c) = ColorPresets[idx];
                row.valueText.text  = cname;
                row.valueText.color = (c.r + c.g + c.b < 0.3f) ? new Color(0.7f, 0.7f, 0.7f) : c;
                _rows[i] = row;
            }
            else if (row.kind == RowKind.KeywordCycle)
            {
                string key = "NPR_kc_" + row.label;
                if (!PlayerPrefs.HasKey(key)) continue;
                int idx = Mathf.Clamp(PlayerPrefs.GetInt(key), 0, row.cycleLabels.Length - 1);
                row.colorIndex = idx;
                row.valueText.text  = row.cycleLabels[idx];
                row.valueText.color = new Color(0.4f, 0.9f, 1f);
                _rows[i] = row;
                ApplyKeywordCycle(row);
            }
        }
        var r = _rows[rowIndex];
        r.valueText.text  = "✓ Loaded";
        r.valueText.color = new Color(0.3f, 0.9f, 0.3f);
        _rows[rowIndex] = r;
        Debug.Log("[NPREdgeDetectionUI] Preset loaded from PlayerPrefs.");
    }

    void CycleDisplayMode(int rowIndex)
    {
        _displayMode = (_displayMode + 1) % 2;
        ApplyDisplayMode();

        var r = _rows[rowIndex];
        if (_displayMode == 0)
        {
            r.valueText.text  = "NPR ON";
            r.valueText.color = new Color(0.4f, 0.9f, 1f);
        }
        else
        {
            r.valueText.text  = "DEFAULT";
            r.valueText.color = new Color(1f, 0.78f, 0.2f);
        }
        _rows[rowIndex] = r;
    }

    void ApplyDisplayMode()
    {
        if (_displayMode == 0) // NPR ON
        {
            foreach (var mat in _nprMaterials)
                if (mat != null) mat.EnableKeyword("ENABLE_NPR_EDGES");
            // ApplyTechniqueKeywords handles InvertedHull + per-technique keyword
            ApplyTechniqueKeywords();
            // For non-InvertedHull, restore the outline toggle's saved state
            // (DEFAULT mode sets _OutlineEnabled=0 on shader; we need to push it back)
            if (_currentTechnique != Technique.InvertedHull)
                SetShaderFloat("_OutlineEnabled", GetRowValue("_OutlineEnabled", 0f));
        }
        else // DEFAULT — Meta PBR as-is
        {
            foreach (var mat in _nprMaterials)
            {
                if (mat == null) continue;
                mat.DisableKeyword("ENABLE_NPR_EDGES");
                mat.SetFloat("_OutlineEnabled", 0f);
            }
        }
    }

    float GetRowValue(string propName, float fallback)
    {
        foreach (var row in _rows)
            if (row.propName == propName) return row.currentValue;
        return fallback;
    }

    void AddTechSelectorRow(Transform parent)
    {
        // Collapsed header row — trigger opens/closes the dropdown
        var (rowGo, hl, valTxt, curTxt, col, _) = MakeRowShell(parent, "Technique", hasSlider: false);
        valTxt.text  = TechniqueNames[(int)_currentTechnique] + " [+]";
        valTxt.color = new Color(0.4f, 0.9f, 1f);
        _rows.Add(new Row
        {
            kind = RowKind.TechSelector, label = "Technique", techniqueFilter = -1,
            valueText = valTxt, highlight = hl, cursorText = curTxt,
            collider = col, rowGo = rowGo,
        });

        // One option row per technique — hidden until dropdown is opened
        for (int i = 0; i < TechniqueNames.Length; i++)
        {
            var (oGo, oHl, oVal, oCur, oCol, _) = MakeRowShell(parent, TechniqueNames[i], hasSlider: false);
            bool active = i == (int)_currentTechnique;
            oVal.text  = active ? "ACTIVE" : "";
            oVal.color = active ? new Color(0.4f, 0.9f, 1f) : Color.clear;
            if (active) oHl.color = new Color(0.2f, 0.6f, 1f, 0.28f);
            oGo.SetActive(false);
            _rows.Add(new Row
            {
                kind = RowKind.TechOption, label = TechniqueNames[i],
                colorIndex = i, techniqueFilter = -1,
                valueText = oVal, highlight = oHl, cursorText = oCur,
                collider = oCol, rowGo = oGo,
            });
        }
    }

    void AddFloatRow(Transform parent, int techniqueFilter, string label, string propName,
                     float min, float max, float step, float initial, string dependsOn = "")
    {
        var (rowGo, hl, valTxt, curTxt, col, slFill) = MakeRowShell(parent, label, hasSlider: true);
        valTxt.text = initial.ToString("F3");
        if (slFill != null)
            slFill.rectTransform.anchorMax = new Vector2(Mathf.InverseLerp(min, max, initial), 1f);
        _rows.Add(new Row
        {
            kind = RowKind.Float, label = label, propName = propName,
            currentValue = initial, min = min, max = max, step = step,
            techniqueFilter = techniqueFilter, dependsOnProp = dependsOn,
            valueText = valTxt, highlight = hl, cursorText = curTxt,
            collider = col, sliderFill = slFill, rowGo = rowGo,
        });
    }


    void AddShaderToggleRow(Transform parent, int techniqueFilter, string label, string propName, bool initial)
    {
        var (rowGo, hl, valTxt, curTxt, col, _) = MakeRowShell(parent, label, hasSlider: false);
        valTxt.text  = initial ? "ON" : "OFF";
        valTxt.color = initial ? new Color(0.4f, 0.9f, 1f) : new Color(0.5f, 0.5f, 0.5f);
        _rows.Add(new Row
        {
            kind = RowKind.ShaderToggle, label = label, propName = propName,
            currentValue = initial ? 1f : 0f, techniqueFilter = techniqueFilter,
            valueText = valTxt, highlight = hl, cursorText = curTxt,
            collider = col, rowGo = rowGo,
        });
    }

    void AddKeywordCycleRow(Transform parent, int techniqueFilter, string label,
                            string[] cycleLabels, string[] cycleKeywords, int initialIndex = 0)
    {
        var (rowGo, hl, valTxt, curTxt, col, _) = MakeRowShell(parent, label, hasSlider: false);
        valTxt.text  = cycleLabels[initialIndex];
        valTxt.color = new Color(0.4f, 0.9f, 1f);
        _rows.Add(new Row
        {
            kind = RowKind.KeywordCycle, label = label,
            cycleLabels = cycleLabels, cycleKeywords = cycleKeywords,
            colorIndex = initialIndex, techniqueFilter = techniqueFilter,
            valueText = valTxt, highlight = hl, cursorText = curTxt, collider = col, rowGo = rowGo,
        });
    }

    void ApplyKeywordCycle(Row row)
    {
        foreach (var mat in _nprMaterials)
        {
            if (mat == null) continue;
            for (int k = 0; k < row.cycleKeywords.Length; k++)
                if (row.cycleKeywords[k].Length > 0) mat.DisableKeyword(row.cycleKeywords[k]);
            string kw = row.cycleKeywords[row.colorIndex];
            if (kw.Length > 0) mat.EnableKeyword(kw);
        }
    }

    void CycleKeyword(int rowIndex, int direction)
    {
        var row = _rows[rowIndex];
        if (row.kind != RowKind.KeywordCycle) return;
        row.colorIndex = (int)Mathf.Repeat(row.colorIndex + direction, row.cycleLabels.Length);
        row.valueText.text  = row.cycleLabels[row.colorIndex];
        row.valueText.color = new Color(0.4f, 0.9f, 1f);
        _rows[rowIndex] = row;
        ApplyKeywordCycle(row);
    }

    void AddColorRow(Transform parent, int techniqueFilter, string label, string propName, int startIndex, string dependsOn = "")
    {
        var (rowGo, hl, valTxt, curTxt, col, _) = MakeRowShell(parent, label, hasSlider: false);
        valTxt.text  = ColorPresets[startIndex].name;
        valTxt.color = new Color(0.7f, 0.7f, 0.7f);
        _rows.Add(new Row
        {
            kind = RowKind.Color, label = label, propName = propName,
            colorIndex = startIndex, techniqueFilter = techniqueFilter, dependsOnProp = dependsOn,
            valueText = valTxt, highlight = hl, cursorText = curTxt,
            collider = col, rowGo = rowGo,
        });
    }

    (GameObject, Image, Text, Text, BoxCollider, Image)
    MakeRowShell(Transform parent, string label, bool hasSlider)
    {
        const float ROW_H   = 56f;
        const float CHILD_H = 44f;

        var rowGo = Go("Row_" + label, parent);
        rowGo.GetComponent<RectTransform>().sizeDelta = new Vector2(0, ROW_H);

        var hlImg = rowGo.AddComponent<Image>();
        hlImg.color = Color.clear;

        var bc = rowGo.AddComponent<BoxCollider>();
        bc.size   = new Vector3(940f, ROW_H, 100f);
        bc.center = Vector3.zero;

        var hlg = rowGo.AddComponent<HorizontalLayoutGroup>();
        hlg.padding                = new RectOffset(10, 10, 6, 6);
        hlg.spacing                = 8;
        hlg.childAlignment         = TextAnchor.MiddleLeft;
        hlg.childControlHeight     = false;
        hlg.childControlWidth      = false;
        hlg.childForceExpandHeight = false;
        hlg.childForceExpandWidth  = false;

        var cursorGo = Go("Cursor", rowGo.transform);
        var curTxt   = cursorGo.AddComponent<Text>();
        curTxt.text = "►"; curTxt.font = BuiltinFont(); curTxt.fontSize = 22;
        curTxt.color = Color.clear; curTxt.alignment = TextAnchor.MiddleCenter;
        cursorGo.GetComponent<RectTransform>().sizeDelta = new Vector2(28, CHILD_H);

        var lGo  = Go("Lbl", rowGo.transform);
        var lTxt = lGo.AddComponent<Text>();
        lTxt.text = label; lTxt.font = BuiltinFont(); lTxt.fontSize = 22;
        lTxt.color = Color.white; lTxt.alignment = TextAnchor.MiddleLeft;
        lGo.GetComponent<RectTransform>().sizeDelta = new Vector2(220, CHILD_H);

        Image sliderFill = null;
        if (hasSlider)
        {
            var bgGo = Go("SliderBG", rowGo.transform);
            bgGo.AddComponent<Image>().color = new Color(0.18f, 0.18f, 0.18f, 1f);
            bgGo.GetComponent<RectTransform>().sizeDelta = new Vector2(480, CHILD_H);

            var fillGo  = Go("Fill", bgGo.transform);
            var fillImg = fillGo.AddComponent<Image>();
            fillImg.color = new Color(0.20f, 0.75f, 0.45f, 1f);
            var fillRt = fillGo.GetComponent<RectTransform>();
            fillRt.anchorMin = Vector2.zero;
            fillRt.anchorMax = new Vector2(0f, 1f);
            fillRt.offsetMin = fillRt.offsetMax = Vector2.zero;
            sliderFill = fillImg;
        }

        float valW = hasSlider ? 160f : 660f;
        var vGo  = Go("Val", rowGo.transform);
        var vTxt = vGo.AddComponent<Text>();
        vTxt.font = BuiltinFont(); vTxt.fontSize = 22;
        vTxt.color = new Color(1f, 0.85f, 0.35f);
        vTxt.alignment = hasSlider ? TextAnchor.MiddleRight : TextAnchor.MiddleLeft;
        vGo.GetComponent<RectTransform>().sizeDelta = new Vector2(valW, CHILD_H);

        return (rowGo, hlImg, vTxt, curTxt, bc, sliderFill);
    }

    // ── Ray line ──────────────────────────────────────────────────────────────
    void BuildRayLine()
    {
        var go = new GameObject("NPRRayLine");
        go.transform.SetParent(transform, false);
        _lr = go.AddComponent<LineRenderer>();
        _lr.positionCount = 2;
        _lr.startWidth = 0.003f; _lr.endWidth = 0.001f;
        _lr.useWorldSpace = true;
        _lr.material   = new Material(Shader.Find("Sprites/Default"));
        _lr.startColor = new Color(0.4f, 0.9f, 1f, 1f);
        _lr.endColor   = new Color(0.4f, 0.9f, 1f, 0.15f);
        _lr.gameObject.SetActive(false);
    }

    // ── Camera / controller lookup ────────────────────────────────────────────
    void ResolveCamera()
    {
        if (_anchor != null) { _camTransform = _anchor; return; }
        if (Camera.main != null) { _camTransform = Camera.main.transform; return; }
        foreach (var cam in FindObjectsOfType<Camera>())
        {
            string n = cam.gameObject.name;
            if (n.Contains("Eye") || n.Contains("Camera") || n.Contains("camera"))
            { _camTransform = cam.transform; return; }
        }
        var any = FindObjectOfType<Camera>();
        if (any != null) _camTransform = any.transform;
    }

    void ResolveController()
    {
        string[] names = { "RightControllerAnchor", "RightHandAnchor", "RightAnchor", "RightController" };
        foreach (var n in names) { var go = GameObject.Find(n); if (go != null) { _controllerTransform = go.transform; return; } }
        foreach (var go in FindObjectsOfType<GameObject>())
        {
            string n = go.name;
            if ((n.Contains("Right") || n.Contains("right")) && (n.Contains("Controller") || n.Contains("Hand") || n.Contains("Anchor")))
            { _controllerTransform = go.transform; return; }
        }
        _controllerTransform = _camTransform;
        Debug.LogWarning("[NPREdgeDetectionUI] Right controller not found; using camera fallback");
    }

    // ── UI helpers ────────────────────────────────────────────────────────────
    void Label(Transform parent, string text, int size, Color color)
    {
        var go = Go("Label", parent); var txt = go.AddComponent<Text>();
        txt.text = text; txt.font = BuiltinFont(); txt.fontSize = size;
        txt.color = color; txt.fontStyle = FontStyle.Bold; txt.alignment = TextAnchor.MiddleCenter;
        go.GetComponent<RectTransform>().sizeDelta = new Vector2(0, size + 10);
    }

    void SectionLabel(Transform parent, string text, int techniqueFilter = -1)
    {
        var go = Go("Section", parent); var txt = go.AddComponent<Text>();
        txt.text = "— " + text + " —"; txt.font = BuiltinFont(); txt.fontSize = 18;
        txt.color = new Color(0.55f, 0.85f, 0.55f); txt.fontStyle = FontStyle.Bold;
        txt.alignment = TextAnchor.MiddleLeft;
        go.GetComponent<RectTransform>().sizeDelta = new Vector2(0, 28);
        if (techniqueFilter >= 0) _sectionLabels.Add((techniqueFilter, go));
    }

    void Space(Transform parent, float h)
        => Go("Space", parent).GetComponent<RectTransform>().sizeDelta = new Vector2(0, h);

    static GameObject Go(string name, Transform parent)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.AddComponent<RectTransform>();
        return go;
    }

    static void Stretch(GameObject go)
    {
        var rt = go.GetComponent<RectTransform>();
        rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
        rt.offsetMin = rt.offsetMax = Vector2.zero;
    }

    static Font _font;
    static Font BuiltinFont()
    {
        if (_font == null) _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        return _font;
    }
}
