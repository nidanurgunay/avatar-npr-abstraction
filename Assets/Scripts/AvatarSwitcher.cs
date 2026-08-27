using Oculus.Avatar2;
using UnityEngine;
using UnityEngine.UI;

/// Cycles through preset Meta avatars for NPR shader assessment.
///
/// Button layout:
///   Y  (left top)   — toggle avatar-selection mode ON / OFF
///   Left stick ←    — previous preset  (while selection mode is ON)
///   Left stick →    — next     preset  (while selection mode is ON)
///
/// Filter console logs with:  [AVSWITCH]
public class AvatarSwitcher : MonoBehaviour
{
    [Header("Presets to cycle (index 0, 1, 2 …)")]
    public int[] presetIndices = new int[] { 0, 1, 2, 3, 4, 5 };

    [Header("HUD placement")]
    [SerializeField] private float _hudDistance = 1.2f;
    [SerializeField] private float _hudYOffset  = -0.15f;

    // ── State ─────────────────────────────────────────────────────────────────
    private bool _selectionMode;
    private int  _currentIndex;
    private bool _isLoading;

    // ── Scene refs ────────────────────────────────────────────────────────────
    private SampleAvatarEntity[]  _entities;
    private SampleSceneLocomotion _locomotion;

    // ── Floating HUD ──────────────────────────────────────────────────────────
    private GameObject _hud;
    private Text       _hudText;

    // ── Stick repeat ─────────────────────────────────────────────────────────
    private float _stickCooldown;
    private bool  _stickWasInDeadzone = true;
    private const float FIRST_REPEAT = 0.45f;
    private const float HOLD_REPEAT  = 0.22f;
    private const float DEAD         = 0.55f;

    // ── Debug heartbeat ───────────────────────────────────────────────────────
    private float _debugTimer;
    private const float DEBUG_INTERVAL = 3f;

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    void Start()
    {
        var allEntities = FindObjectsOfType<SampleAvatarEntity>();
        _entities = allEntities.Length > 0 ? new SampleAvatarEntity[] { allEntities[0] } : new SampleAvatarEntity[0];
        _locomotion = FindObjectOfType<SampleSceneLocomotion>();
        BuildHUD();

        Debug.Log($"[AVSWITCH] Start: {_entities.Length} avatar entity/entities found. " +
                  $"Locomotion={((_locomotion != null) ? _locomotion.gameObject.name : "NOT FOUND")}. " +
                  $"HUD built={(_hud != null)}. Camera={(Camera.main != null ? Camera.main.name : "NOT FOUND")}");
        Debug.Log("[AVSWITCH] Heartbeat logs every 3 s. Press Y (left controller) to toggle avatar selection.");
    }

    void OnDestroy()
    {
        UnsubscribeLoadedEvent();
    }

    private Transform CamTransform
    {
        get
        {
            if (Camera.main != null) return Camera.main.transform;
            var cam = FindObjectOfType<Camera>();
            return cam != null ? cam.transform : null;
        }
    }

    void Update()
    {
        // Re-find the primary entity if not yet found (SDK spawns avatars asynchronously).
        if (_entities == null || _entities.Length == 0)
        {
            var all = FindObjectsOfType<SampleAvatarEntity>();
            if (all.Length > 0)
            {
                _entities = new SampleAvatarEntity[] { all[0] };
                Debug.Log($"[AVSWITCH] Entity found late: {all[0].name}");
            }
        }

        // ── Debug heartbeat — filter with [AVSWITCH] in the console ──────────
        _debugTimer += Time.deltaTime;
        if (_debugTimer >= DEBUG_INTERVAL)
        {
            _debugTimer = 0f;

            bool yLTouch  = OVRInput.Get(OVRInput.RawButton.Y, OVRInput.Controller.LTouch);
            bool yTouch   = OVRInput.Get(OVRInput.RawButton.Y, OVRInput.Controller.Touch);
            bool yActive  = OVRInput.Get(OVRInput.RawButton.Y, OVRInput.Controller.Active);
            bool btn4     = OVRInput.Get(OVRInput.Button.Four);

            OVRInput.Controller active    = OVRInput.GetActiveController();
            OVRInput.Controller connected = OVRInput.GetConnectedControllers();

            Debug.Log($"[AVSWITCH] Heartbeat | selectionMode={_selectionMode} loading={_isLoading} entities={_entities?.Length ?? 0} " +
                      $"| Y(LTouch)={yLTouch} Y(Touch)={yTouch} Y(Active)={yActive} Btn4={btn4} " +
                      $"| Active ctrl={active} Connected={connected}");
        }

        // ── Y button — explicitly read from left controller ───────────────────
        bool yDown_LTouch = OVRInput.GetDown(OVRInput.RawButton.Y, OVRInput.Controller.LTouch);
        bool yDown_Touch  = OVRInput.GetDown(OVRInput.RawButton.Y, OVRInput.Controller.Touch);

        if (yDown_LTouch || yDown_Touch)
        {
            Debug.Log($"[AVSWITCH] Y DETECTED — LTouch={yDown_LTouch} Touch={yDown_Touch} → toggling selection mode");
            SetSelectionMode(!_selectionMode);
        }

        if (!_selectionMode) return;

        UpdateHUDPosition();

        // Block input while the previous switch is still loading.
        if (_isLoading) return;

        float x = OVRInput.Get(OVRInput.Axis2D.PrimaryThumbstick, OVRInput.Controller.LTouch).x;
        bool inDeadzone = Mathf.Abs(x) < DEAD;

        if (inDeadzone)
        {
            _stickWasInDeadzone = true;
            _stickCooldown      = 0f;
            return;
        }

        if (_stickWasInDeadzone)
        {
            _stickWasInDeadzone = false;
            _stickCooldown      = FIRST_REPEAT;
            Step(x > 0 ? +1 : -1);
            return;
        }

        _stickCooldown -= Time.deltaTime;
        if (_stickCooldown <= 0f)
        {
            _stickCooldown = HOLD_REPEAT;
            Step(x > 0 ? +1 : -1);
        }
    }

    // ── Selection mode ────────────────────────────────────────────────────────
    void SetSelectionMode(bool on)
    {
        _selectionMode = on;
        if (_locomotion != null) _locomotion.enabled = !on;
        if (_hud != null) _hud.SetActive(on);
        if (on) UpdateHUDText();
        UpdateHUDPosition();
        Debug.Log($"[AVSWITCH] Selection mode {(on ? "ON" : "OFF")} | " +
                  $"HUD active={_hud?.activeSelf} entities={_entities?.Length ?? 0}");
    }

    // ── Cycle ─────────────────────────────────────────────────────────────────
    void Step(int dir)
    {
        if (presetIndices == null || presetIndices.Length == 0) return;
        _currentIndex = (_currentIndex + dir + presetIndices.Length) % presetIndices.Length;
        int preset = presetIndices[_currentIndex];

        var entity = (_entities != null && _entities.Length > 0) ? _entities[0] : null;
        if (entity == null) return;

        // Unsubscribe previous listener before registering a new one.
        UnsubscribeLoadedEvent();
        entity.OnUserAvatarLoadedEvent.AddListener(OnAvatarLoaded);

        _isLoading = true;
        UpdateHUDText();
        entity.SwitchPreset(preset);
        Debug.Log($"[AVSWITCH] SwitchPreset {preset} ({_currentIndex + 1}/{presetIndices.Length}) entities={_entities.Length}");
    }

    // ── Avatar load callback ──────────────────────────────────────────────────
    void OnAvatarLoaded(OvrAvatarEntity entity)
    {
        _isLoading = false;
        UnsubscribeLoadedEvent();
        Debug.Log($"[AVSWITCH] Avatar loaded — preset {presetIndices[_currentIndex]} ready");
        UpdateHUDText();
    }

    void UnsubscribeLoadedEvent()
    {
        if (_entities == null || _entities.Length == 0 || _entities[0] == null) return;
        _entities[0].OnUserAvatarLoadedEvent.RemoveListener(OnAvatarLoaded);
    }

    // ── HUD ───────────────────────────────────────────────────────────────────
    void BuildHUD()
    {
        _hud = new GameObject("AvatarSwitcherHUD");
        _hud.transform.SetParent(null, false);

        var canvas = _hud.AddComponent<Canvas>();
        canvas.renderMode  = RenderMode.WorldSpace;
        canvas.worldCamera = Camera.main;

        var rt = _hud.GetComponent<RectTransform>();
        rt.sizeDelta  = new Vector2(700f, 100f);
        rt.localScale = Vector3.one * 0.002f;

        var bg   = new GameObject("BG", typeof(RectTransform));
        bg.transform.SetParent(_hud.transform, false);
        var bgImg = bg.AddComponent<Image>();
        bgImg.color = new Color(0.06f, 0.06f, 0.06f, 0.88f);
        var bgRt = bg.GetComponent<RectTransform>();
        bgRt.anchorMin = Vector2.zero; bgRt.anchorMax = Vector2.one;
        bgRt.offsetMin = bgRt.offsetMax = Vector2.zero;

        var txtGo = new GameObject("Text", typeof(RectTransform));
        txtGo.transform.SetParent(_hud.transform, false);
        _hudText = txtGo.AddComponent<Text>();
        _hudText.font      = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        _hudText.fontSize  = 28;
        _hudText.alignment = TextAnchor.MiddleCenter;
        _hudText.color     = new Color(0.4f, 0.9f, 1f);
        var tRt = txtGo.GetComponent<RectTransform>();
        tRt.anchorMin = Vector2.zero; tRt.anchorMax = Vector2.one;
        tRt.offsetMin = tRt.offsetMax = Vector2.zero;

        _hud.SetActive(false);
    }

    void UpdateHUDText()
    {
        if (_hudText == null) return;
        int total  = presetIndices?.Length ?? 0;
        int preset = (total > 0) ? presetIndices[_currentIndex] : 0;

        if (_isLoading)
        {
            _hudText.text  = $"Loading preset {preset}…   ( {_currentIndex + 1} / {total} )\nPlease wait";
            _hudText.color = new Color(1f, 0.85f, 0.2f);
        }
        else
        {
            _hudText.text  = $"AVATAR SELECT   Preset {preset}   ( {_currentIndex + 1} / {total} )\n" +
                             "◄  left stick  ►     Y = exit";
            _hudText.color = new Color(0.4f, 0.9f, 1f);
        }
    }

    void UpdateHUDPosition()
    {
        if (_hud == null) return;
        var cam = CamTransform;
        if (cam == null) return;

        Vector3 fwd = cam.forward; fwd.y = 0f;
        if (fwd.sqrMagnitude < 0.001f) fwd = Vector3.forward;
        fwd.Normalize();
        _hud.transform.position = cam.position + fwd * _hudDistance + Vector3.up * _hudYOffset;
        _hud.transform.rotation = Quaternion.LookRotation(fwd, Vector3.up);
    }
}
