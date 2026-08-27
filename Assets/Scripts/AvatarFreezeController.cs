using System.Reflection;
using Oculus.Avatar2;
using UnityEngine;
using UnityEngine.InputSystem;

/// Freeze avatar body-tracking pose for NPR shader assessment.
///
/// How it works:
///   The Avatar SDK routes tracking through native CAPI callbacks. Simply swapping
///   _inputTrackingProvider in C# is not enough — each OvrAvatarEntity has a native-side
///   context registered via ovrAvatar2Input_SetInputTrackingContext. To actually freeze we:
///     1. Swap _inputTrackingProvider to our SnapshotTrackingProvider.
///     2. Call entity.SetInputManager(manager, force:true) on every entity, which internally
///        calls SetInputTrackingProvider → CAPI.ovrAvatar2Input_SetInputTrackingContext,
///        re-registering our snapshot's native callback with the runtime.
///   Unfreeze reverses both steps.
///
/// Press A (right) or X (left) controller — or Space in editor — to toggle.
public class AvatarFreezeController : MonoBehaviour
{
    [Header("Assessment Mode")]
    [Tooltip("Leave null to auto-find the first OvrAvatarInputManager in the scene.")]
    [SerializeField] private OvrAvatarInputManager _inputManager;

    private bool _frozen;
    private OvrAvatarInputTrackingProviderBase _originalProvider;
    private SnapshotTrackingProvider           _snapshotProvider;
    private FieldInfo                          _providerField;
    private OvrAvatarEntity[]                  _entities;

    // ── Snapshot provider ─────────────────────────────────────────────────────
    // Its constructor registers a CAPI callback. StoreSnapshot captures a pose;
    // GetInputTrackingState replays it every frame so the native body solver
    // sees a static head/controller configuration.
    private class SnapshotTrackingProvider : OvrAvatarInputTrackingProviderBase
    {
        private OvrAvatarInputTrackingState _snapshot;
        public void StoreSnapshot(OvrAvatarInputTrackingState state) => _snapshot = state;
        public override bool GetInputTrackingState(out OvrAvatarInputTrackingState state)
        {
            state = _snapshot;
            return true;
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    void Start() => TryInit();

    bool TryInit()
    {
        if (_inputManager == null)
            _inputManager = FindObjectOfType<OvrAvatarInputManager>();
        if (_inputManager == null) return false;

        // Create snapshot provider once OvrAvatarManager is ready (its CAPI ctor needs the runtime)
        if (_snapshotProvider == null)
            _snapshotProvider = new SnapshotTrackingProvider();

        if (_entities == null || _entities.Length == 0)
            _entities = FindObjectsOfType<OvrAvatarEntity>();

        if (_providerField == null)
        {
            // Walk up the type hierarchy — field is declared in OvrAvatarInputManager
            var type = _inputManager.GetType();
            while (_providerField == null && type != null)
            {
                _providerField = type.GetField("_inputTrackingProvider",
                    BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly);
                type = type.BaseType;
            }

            if (_providerField != null)
                Debug.Log($"[AvatarFreezeController] Ready — field found in {_providerField.DeclaringType?.Name}, " +
                          $"{_entities.Length} entity/entities. A/X/Space to freeze.");
            else
                Debug.LogWarning("[AvatarFreezeController] _inputTrackingProvider not found via reflection.");
        }

        return _providerField != null && _snapshotProvider != null;
    }

    void Update()
    {
        if (_inputManager == null || _providerField == null || _snapshotProvider == null)
            if (!TryInit()) return;

        // Use explicit controller — Controller.Active fails when activeControllerType is None/wrong side.
        bool toggle = OVRInput.GetDown(OVRInput.RawButton.A, OVRInput.Controller.RTouch)   // A (right)
                   || OVRInput.GetDown(OVRInput.RawButton.X, OVRInput.Controller.LTouch)   // X (left)
                   || (Keyboard.current != null && Keyboard.current.spaceKey.wasPressedThisFrame);

        if (toggle) SetFrozen(!_frozen);
    }

    // ── Public API ────────────────────────────────────────────────────────────
    public bool IsFrozen => _frozen;

    public void SetFrozen(bool freeze)
    {
        if (!TryInit()) return;
        _frozen = freeze;

        if (freeze)
        {
            // Force lazy-init of the provider property so the field is non-null
            _ = _inputManager.InputTrackingProvider;

            // Capture the live provider and snapshot its current tracking state
            _originalProvider = _providerField.GetValue(_inputManager)
                                as OvrAvatarInputTrackingProviderBase;

            OvrAvatarInputTrackingState state = default;
            _originalProvider?.GetInputTrackingState(out state);
            _snapshotProvider.StoreSnapshot(state);

            // 1. Swap the C# field so the InputTrackingProvider property returns snapshot
            _providerField.SetValue(_inputManager, _snapshotProvider);

            // 2. Re-register the snapshot's native CAPI context with every entity
            foreach (var entity in _entities)
                if (entity != null)
                    entity.SetInputManager(_inputManager, force: true);
        }
        else
        {
            // 1. Restore the original provider in the C# field
            _providerField.SetValue(_inputManager, _originalProvider);

            // 2. Re-register the original native CAPI context with every entity
            foreach (var entity in _entities)
                if (entity != null)
                    entity.SetInputManager(_inputManager, force: true);
        }

        Debug.Log($"[AvatarFreezeController] Freeze={freeze}, provider={_providerField.GetValue(_inputManager)?.GetType().Name}");
    }
}
