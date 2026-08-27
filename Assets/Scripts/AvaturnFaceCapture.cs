// AvaturnFaceCapture.cs
//
// Drives all SkinnedMeshRenderers on this Avaturn avatar with ARKit blend shape
// data streamed live from the "Live Link Face" iPhone app over UDP.
// All 52 ARKit blend shapes + head rotation are supported.
//
// ── SETUP ───────────────────────────────────────────────────────────────────
// 1. iPhone requirement: iPhone X or later (TrueDepth / Face ID camera).
// 2. Install "Live Link Face" by Epic Games — free on the App Store.
// 3. Connect iPhone and this PC to the same Wi-Fi network.
// 4. Find your PC's local IP:
//      Mac  → System Preferences › Network, or run: ipconfig getifaddr en0
//      Win  → run: ipconfig   (look for IPv4 under your Wi-Fi adapter)
// 5. In Live Link Face: tap ⊕ → enter PC IP, port 11111 → enable the target.
// 6. Attach this component to the ROOT GameObject of your Avaturn avatar.
// 7. Press Play in Unity first, then press the red Record button in the app.
//    The Console will print "Face capture is live" when data arrives.
//
// ── RECORDING WORKFLOW ──────────────────────────────────────────────────────
// Use Unity Recorder (Window › General › Recorder) to capture the Game View
// while streaming. The avatar's lips, brows, cheeks, and eyes all animate live.
// ────────────────────────────────────────────────────────────────────────────

using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using UnityEngine;

[AddComponentMenu("Avaturn/Face Capture (Live Link)")]
public class AvaturnFaceCapture : MonoBehaviour
{
    [Header("Network")]
    [Tooltip("UDP port Live Link Face streams to. Default is 11111.")]
    [SerializeField] private int _port = 11111;

    [Header("Animation")]
    [Tooltip("Higher smoothing = softer but slightly delayed response. 0 = raw input.")]
    [Range(0f, 0.95f)]
    [SerializeField] private float _smoothing = 0.5f;

    [Tooltip("Scale the blend shape weights. 1 = full expression (0–100), 0.3 = subtle.")]
    [Range(0f, 1f)]
    [SerializeField] private float _blendShapeStrength = 0.3f;

    [Header("Head Rotation")]
    [Tooltip("Rotate the head bone to match your live head orientation.")]
    [SerializeField] private bool _driveHeadBone = true;
    [SerializeField] private string _headBoneName = "Head";
    [Range(0f, 1f)]
    [Tooltip("Scale down the head rotation so the avatar does not over-rotate.")]
    [SerializeField] private float _headRotationStrength = 0.5f;

    // ── ARKit blend shape names in the order Live Link Face sends them ────────
    // Matches Unreal Engine's EARFaceBlendShape enum (indices 0–51).
    // Indices 52–60 carry head and eye pose — handled separately below.
    private static readonly string[] k_ARKitNames =
    {
        "eyeBlinkLeft",        "eyeLookDownLeft",     "eyeLookInLeft",      "eyeLookOutLeft",
        "eyeLookUpLeft",       "eyeSquintLeft",       "eyeWideLeft",
        "eyeBlinkRight",       "eyeLookDownRight",    "eyeLookInRight",     "eyeLookOutRight",
        "eyeLookUpRight",      "eyeSquintRight",      "eyeWideRight",
        "jawForward",          "jawLeft",             "jawRight",           "jawOpen",
        "mouthClose",          "mouthFunnel",         "mouthPucker",        "mouthLeft",
        "mouthRight",          "mouthSmileLeft",      "mouthSmileRight",    "mouthFrownLeft",
        "mouthFrownRight",     "mouthDimpleLeft",     "mouthDimpleRight",   "mouthStretchLeft",
        "mouthStretchRight",   "mouthRollLower",      "mouthRollUpper",     "mouthShrugLower",
        "mouthShrugUpper",     "mouthPressLeft",      "mouthPressRight",    "mouthLowerDownLeft",
        "mouthLowerDownRight", "mouthUpperUpLeft",    "mouthUpperUpRight",
        "browDownLeft",        "browDownRight",       "browInnerUp",
        "browOuterUpLeft",     "browOuterUpRight",
        "cheekPuff",           "cheekSquintLeft",     "cheekSquintRight",
        "noseSneerLeft",       "noseSneerRight",      "tongueOut",
    };

    private struct BlendTarget
    {
        public SkinnedMeshRenderer Renderer;
        public int Index;
    }

    // name → every (renderer, blendShapeIndex) pair that has it
    private Dictionary<string, List<BlendTarget>> _targetMap;
    private float[] _current = new float[52];

    private Transform _headBone;
    private Quaternion _headRestRotation;

    private UdpClient _udp;
    private Thread _thread;
    private readonly object _dataLock = new object();
    private float[] _pending;

    // ── Unity lifecycle ──────────────────────────────────────────────────────

    private void Start()
    {
        BuildTargetMap();
        CacheHeadBone();
        StartNetwork();
    }

    private void Update()
    {
        float[] incoming;
        lock (_dataLock)
        {
            incoming = _pending;
            _pending = null;
        }
        if (incoming == null) return;

        float step = 1f - Mathf.Clamp01(_smoothing);

        // Apply the 52 ARKit blend shapes
        int limit = Mathf.Min(k_ARKitNames.Length, incoming.Length);
        for (int i = 0; i < limit; i++)
        {
            // Live Link Face sends 0–1; Unity blend shapes use 0–100
            float target = incoming[i] * 100f * _blendShapeStrength;
            _current[i] = Mathf.Lerp(_current[i], target, step);

            if (_targetMap.TryGetValue(k_ARKitNames[i], out var targets))
                foreach (var bt in targets)
                    bt.Renderer.SetBlendShapeWeight(bt.Index, _current[i]);
        }

        // Drive the symmetric mouthSmile as the average of the left/right values so
        // that Avaturn meshes carrying only the unified shape still animate.
        DriveSymmetricAverage("mouthSmile", "mouthSmileLeft", "mouthSmileRight");

        // Head bone rotation — indices 52 = yaw, 53 = pitch, 54 = roll (degrees)
        if (_driveHeadBone && _headBone != null && incoming.Length > 54)
        {
            var euler = new Vector3(incoming[53], incoming[52], -incoming[54])
                        * _headRotationStrength;
            _headBone.localRotation = Quaternion.Slerp(
                _headBone.localRotation,
                _headRestRotation * Quaternion.Euler(euler),
                step);
        }
    }

    private void OnDestroy()
    {
        _udp?.Close(); // causes Receive() to throw and exits the background thread
        _udp = null;
    }

    // ── Initialisation helpers ────────────────────────────────────────────────

    private void BuildTargetMap()
    {
        _targetMap = new Dictionary<string, List<BlendTarget>>();
        int meshCount = 0;
        foreach (var smr in GetComponentsInChildren<SkinnedMeshRenderer>(true))
        {
            var mesh = smr.sharedMesh;
            if (mesh == null) continue;
            meshCount++;
            for (int i = 0; i < mesh.blendShapeCount; i++)
            {
                string bsName = mesh.GetBlendShapeName(i);
                if (!_targetMap.TryGetValue(bsName, out var list))
                    _targetMap[bsName] = list = new List<BlendTarget>();
                list.Add(new BlendTarget { Renderer = smr, Index = i });
            }
        }
        Debug.Log($"[FaceCapture] Mapped {_targetMap.Count} blend shape names across {meshCount} meshes.");
    }

    private void CacheHeadBone()
    {
        if (!_driveHeadBone) return;
        foreach (var t in GetComponentsInChildren<Transform>(true))
        {
            if (t.name != _headBoneName) continue;
            _headBone = t;
            _headRestRotation = t.localRotation;
            return;
        }
        Debug.LogWarning($"[FaceCapture] Head bone '{_headBoneName}' not found — head rotation disabled.");
    }

    private void DriveSymmetricAverage(string sym, string left, string right)
    {
        if (!_targetMap.ContainsKey(sym)) return;
        float lw = ReadFirstWeight(left);
        float rw = ReadFirstWeight(right);
        float avg = (lw + rw) * 0.5f;
        foreach (var bt in _targetMap[sym])
            bt.Renderer.SetBlendShapeWeight(bt.Index, avg);
    }

    private float ReadFirstWeight(string name)
    {
        if (_targetMap.TryGetValue(name, out var list) && list.Count > 0)
            return list[0].Renderer.GetBlendShapeWeight(list[0].Index);
        return 0f;
    }

    // ── Network ───────────────────────────────────────────────────────────────

    private void StartNetwork()
    {
        try
        {
            _udp = new UdpClient(_port);
            _thread = new Thread(ReceiveLoop)
            {
                IsBackground = true,
                Name = "AvaturnFaceCaptureUDP"
            };
            _thread.Start();
            Debug.Log($"[FaceCapture] Listening on UDP port {_port}. " +
                      "In Live Link Face: tap ⊕ → enter this machine's local IP, port 11111.");
        }
        catch (Exception e)
        {
            Debug.LogError($"[FaceCapture] Cannot open UDP port {_port}: {e.Message}");
        }
    }

    private void ReceiveLoop()
    {
        var endpoint = new IPEndPoint(IPAddress.Any, 0);
        bool firstReceived = false;
        while (_udp != null)
        {
            try
            {
                byte[] data = _udp.Receive(ref endpoint);
                float[] values = ParsePacket(data);

                if (!firstReceived)
                {
                    firstReceived = true;
                    if (values != null)
                    {
                        Debug.Log($"[FaceCapture] Face capture is live — streaming from {endpoint.Address} ({values.Length} blend shapes).");
                    }
                    else
                    {
                        int len = data.Length;
                        // Show bytes [60..72] where the count field should be, and the last 8 bytes
                        string mid = (len > 72) ? BitConverter.ToString(data, 60, 13) : "N/A";
                        string tail = BitConverter.ToString(data, Mathf.Max(0, len - 8), Mathf.Min(8, len));
                        int b65val = (len > 68) ? BitConverter.ToInt32(data, len - 4 - 61 * 4) : -1;
                        Debug.LogWarning($"[FaceCapture] Parse failed. len={len}  bytes[60..72]={mid}  last8={tail}  value@countPos={b65val}");
                    }
                }

                lock (_dataLock) { _pending = values; }
            }
            catch (SocketException) { break; }   // socket closed in OnDestroy
            catch (ObjectDisposedException) { break; }
            catch (Exception e) { Debug.LogWarning($"[FaceCapture] Packet error: {e.Message}"); }
        }
    }

    // ── Packet parser ─────────────────────────────────────────────────────────
    //
    // Confirmed packet layout (from hex diagnostic on 313-byte packet):
    //   count field : 1 byte (uint8) at position d.Length - 1 - count*4
    //                 value = 61 (0x3D), confirmed at byte 68
    //   float data  : count × 4 bytes, BIG-ENDIAN, immediately after the count byte
    //                 last 8 bytes confirmed to decode as valid [0,1] floats when
    //                 read big-endian
    //
    // We read from the tail so the variable-length header never needs parsing.
    private static float[] ParsePacket(byte[] d)
    {
        if (d == null) return null;
        if (TryExtract(d, 61, out var v61)) return v61;
        if (TryExtract(d, 52, out var v52)) return v52;
        return null;
    }

    private static bool TryExtract(byte[] d, int expected, out float[] values)
    {
        values = null;
        // count is a uint8 at: d.Length - 1(count byte) - expected*4(float bytes)
        int countPos = d.Length - 1 - expected * 4;
        if (countPos < 0 || d[countPos] != (byte)expected) return false;

        values = new float[expected];
        int o = countPos + 1;
        for (int i = 0; i < expected; i++, o += 4)
            values[i] = ReadBigEndianFloat(d, o);
        return true;
    }

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Explicit)]
    private struct FloatIntUnion
    {
        [System.Runtime.InteropServices.FieldOffset(0)] public int   I;
        [System.Runtime.InteropServices.FieldOffset(0)] public float F;
    }

    private static float ReadBigEndianFloat(byte[] d, int o)
    {
        var u = new FloatIntUnion();
        u.I = (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
        return u.F;
    }
}
