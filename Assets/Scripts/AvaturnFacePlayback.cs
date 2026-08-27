// AvaturnFacePlayback.cs
//
// Plays back a Live Link Face CSV recording on all Avaturn avatars under a parent.
// Use this instead of AvaturnFaceCapture when you cannot stream live (e.g. eduroam).
//
// ── SETUP ───────────────────────────────────────────────────────────────────
// 1. On your iPhone, open Live Link Face and record a take.
// 2. After recording: tap the take → Share → Export CSV.
// 3. Copy the .csv file into your Unity project (e.g. Assets/FaceData/).
//    Unity will import it as a TextAsset automatically.
// 4. Attach this component to the AVATARS parent GameObject (the folder that
//    contains all your Avaturn avatars). It drives every avatar under it at once.
// 5. Drag the imported CSV asset into the "Csv File" field in the Inspector.
// 6. Optionally drag the matching audio WAV into the "Audio Clip" field.
// 7. Press Play — all avatars animate together with no network needed.
//
// ── CSV FORMAT ──────────────────────────────────────────────────────────────
// Live Link Face exports rows like:
//   Timecode,BlendShapeCount,EyeBlinkLeft,EyeBlinkRight,...
//   00:00:00:00,61,0.000,0.000,...
// Timecode format is HH:MM:SS:FF (frames, not milliseconds).
// Values are 0–1 floats. This script converts them to Unity's 0–100 range.
// ────────────────────────────────────────────────────────────────────────────

using System;
using System.Collections.Generic;
using UnityEngine;

[AddComponentMenu("Avaturn/Face Playback (CSV) — attach to Avatars parent")]
public class AvaturnFacePlayback : MonoBehaviour
{
    [Header("Data")]
    [Tooltip("CSV exported from Live Link Face (File → Export take → CSV).")]
    [SerializeField] private TextAsset csvFile;

    [Tooltip("Frame rate used when recording the take. Live Link Face defaults to 60.")]
    [SerializeField] private float recordingFps = 60f;

    [SerializeField] private bool loop = true;

    [Header("Animation")]
    [Tooltip("Smoothing between frames. 0 = exact CSV values (recommended for playback).")]
    [Range(0f, 0.95f)]
    [SerializeField] private float smoothing = 0f;

    [Tooltip("Scale all blend shape weights. Match this to the value used during live capture.")]
    [Range(0f, 1f)]
    [SerializeField] private float blendShapeStrength = 0.3f;

    [Header("Audio")]
    [Tooltip("Audio clip recorded alongside the face capture take. Leave empty for face-only playback.")]
    [SerializeField] private AudioClip audioClip;

    [Range(0f, 1f)]
    [SerializeField] private float volume = 1f;

    [Header("Head Rotation")]
    [SerializeField] private bool driveHeadBone = true;
    [SerializeField] private string headBoneName = "Head";
    [Range(0f, 1f)]
    [SerializeField] private float headRotationStrength = 0.5f;

    // ARKit blend shape names — must stay in sync with AvaturnFaceCapture.cs
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
        "browDownLeft",        "browDownRight",        "browInnerUp",
        "browOuterUpLeft",     "browOuterUpRight",
        "cheekPuff",           "cheekSquintLeft",     "cheekSquintRight",
        "noseSneerLeft",       "noseSneerRight",      "tongueOut",
    };

    private struct BlendTarget
    {
        public SkinnedMeshRenderer Renderer;
        public int Index;
    }

    private struct Frame
    {
        public float time;
        public float[] values; // 52 or 61 floats, 0-1 range
    }

    private List<Frame> _frames = new();
    private Dictionary<string, List<BlendTarget>> _targetMap;
    private float[] _current = new float[52];
    private Transform _headBone;
    private Quaternion _headRestRotation;
    private float _playTime;
    private float _duration;
    private AudioSource _audioSource;

    private void Start()
    {
        BuildTargetMap();
        CacheHeadBone();
        ParseCSV();

        if (_frames.Count > 0)
            Debug.Log($"[FacePlayback] Loaded {_frames.Count} frames, duration {_duration:F2}s from '{csvFile.name}'.");
        else
            Debug.LogError("[FacePlayback] CSV parse produced no frames. Check the file format.");

        SetupAudio();
    }

    private void SetupAudio()
    {
        if (audioClip == null)
        {
            Debug.LogWarning("[FacePlayback] No AudioClip assigned — assign the WAV in the Inspector.");
            return;
        }

        _audioSource = GetComponent<AudioSource>();
        if (_audioSource == null)
            _audioSource = gameObject.AddComponent<AudioSource>();

        _audioSource.enabled = true;
        _audioSource.clip = audioClip;
        _audioSource.loop = loop;
        _audioSource.volume = volume;
        _audioSource.spatialBlend = 0f;
        _audioSource.playOnAwake = false;
        _audioSource.Play();

        var listener = FindFirstObjectByType<AudioListener>();
        Debug.Log($"[FacePlayback] Audio: clip='{audioClip.name}' length={audioClip.length:F2}s " +
                  $"volume={volume} playing={_audioSource.isPlaying} " +
                  $"listener={(listener != null ? listener.gameObject.name : "MISSING — add AudioListener to scene")}");
    }

    private void Update()
    {
        if (_frames.Count == 0) return;

        // If audio is playing, use its position as the clock so they never drift.
        // Otherwise fall back to manual time accumulation.
        if (_audioSource != null && _audioSource.isPlaying)
        {
            _playTime = _audioSource.time;
        }
        else
        {
            _playTime += Time.deltaTime;
            if (loop && _playTime > _duration)
                _playTime -= _duration;
            _playTime = Mathf.Clamp(_playTime, 0f, _duration);
        }

        int idx = FindFrameIndex(_playTime);
        ApplyFrame(_frames[idx].values);
    }

    // ── CSV parsing ───────────────────────────────────────────────────────────

    private void ParseCSV()
    {
        if (csvFile == null) { Debug.LogError("[FacePlayback] No CSV file assigned."); return; }

        string[] lines = csvFile.text.Split('\n');
        if (lines.Length < 2) return;

        // Header row — build column index map (case-insensitive)
        string[] headers = lines[0].Trim().Split(',');
        var colMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < headers.Length; i++)
            colMap[headers[i].Trim()] = i;

        // Find per-ARKit-name column indices. -1 = not present in this CSV.
        int[] arkitCols = new int[k_ARKitNames.Length];
        for (int i = 0; i < k_ARKitNames.Length; i++)
            arkitCols[i] = colMap.TryGetValue(k_ARKitNames[i], out int c) ? c : -1;

        // Find head rotation columns (indices 52-54 in the 61-value packet)
        colMap.TryGetValue("HeadYaw",   out int colYaw);
        colMap.TryGetValue("HeadPitch", out int colPitch);
        colMap.TryGetValue("HeadRoll",  out int colRoll);

        for (int r = 1; r < lines.Length; r++)
        {
            string line = lines[r].Trim();
            if (string.IsNullOrEmpty(line)) continue;

            string[] cols = line.Split(',');
            if (cols.Length < 3) continue;

            float t = ParseTimecode(cols[0].Trim());

            float[] vals = new float[61]; // 52 blendshapes + 9 pose values
            for (int i = 0; i < k_ARKitNames.Length; i++)
            {
                if (arkitCols[i] >= 0 && arkitCols[i] < cols.Length)
                    float.TryParse(cols[arkitCols[i]], System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out vals[i]);
            }

            // Pack head rotation into slots 52-54 matching the UDP packet layout
            if (colYaw   > 0 && colYaw   < cols.Length) float.TryParse(cols[colYaw],   System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out vals[52]);
            if (colPitch > 0 && colPitch < cols.Length) float.TryParse(cols[colPitch],  System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out vals[53]);
            if (colRoll  > 0 && colRoll  < cols.Length) float.TryParse(cols[colRoll],   System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out vals[54]);

            _frames.Add(new Frame { time = t, values = vals });
        }

        // Live Link Face records wall-clock time of day, not elapsed time.
        // Subtract the first frame's time so playback always starts at t = 0.
        if (_frames.Count > 0)
        {
            float startTime = _frames[0].time;
            for (int i = 0; i < _frames.Count; i++)
            {
                var f = _frames[i];
                f.time -= startTime;
                _frames[i] = f;
            }
        }

        _duration = _frames.Count > 0 ? _frames[_frames.Count - 1].time : 0f;
    }

    // Parses HH:MM:SS:FF or HH:MM:SS:FF.subfraction (Live Link Face format)
    private float ParseTimecode(string tc)
    {
        // Try simple float first (some exports use seconds directly)
        if (float.TryParse(tc, System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out float direct))
            return direct;

        string[] parts = tc.Split(':');
        if (parts.Length < 4) return 0f;
        int.TryParse(parts[0], out int hh);
        int.TryParse(parts[1], out int mm);
        int.TryParse(parts[2], out int ss);
        // FF may have a decimal sub-frame suffix (e.g. "20.131") — parse as float
        float.TryParse(parts[3], System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture, out float ff);
        return hh * 3600f + mm * 60f + ss + ff / recordingFps;
    }

    // Binary search for the frame at or just before playTime
    private int FindFrameIndex(float t)
    {
        int lo = 0, hi = _frames.Count - 1;
        while (lo < hi)
        {
            int mid = (lo + hi + 1) / 2;
            if (_frames[mid].time <= t) lo = mid;
            else hi = mid - 1;
        }
        return lo;
    }

    // ── Blend shape application ───────────────────────────────────────────────

    private void ApplyFrame(float[] incoming)
    {
        float step = 1f - Mathf.Clamp01(smoothing);
        int limit = Mathf.Min(k_ARKitNames.Length, incoming.Length);

        for (int i = 0; i < limit; i++)
        {
            float target = incoming[i] * 100f * blendShapeStrength;
            _current[i] = Mathf.Lerp(_current[i], target, step);

            if (_targetMap.TryGetValue(k_ARKitNames[i], out var targets))
                foreach (var bt in targets)
                    bt.Renderer.SetBlendShapeWeight(bt.Index, _current[i]);
        }

        DriveSymmetricAverage("mouthSmile", "mouthSmileLeft", "mouthSmileRight");

        // Head rotation — slots 52 = yaw, 53 = pitch, 54 = roll (degrees)
        if (driveHeadBone && _headBone != null && incoming.Length > 54)
        {
            var euler = new Vector3(incoming[53], incoming[52], -incoming[54]) * headRotationStrength;
            _headBone.localRotation = Quaternion.Slerp(
                _headBone.localRotation,
                _headRestRotation * Quaternion.Euler(euler),
                step > 0f ? step : 1f);
        }
    }

    // ── Setup helpers — identical logic to AvaturnFaceCapture ────────────────

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
        Debug.Log($"[FacePlayback] Mapped {_targetMap.Count} blend shape names across {meshCount} meshes.");
    }

    private void CacheHeadBone()
    {
        if (!driveHeadBone) return;
        foreach (var t in GetComponentsInChildren<Transform>(true))
        {
            if (t.name != headBoneName) continue;
            _headBone = t;
            _headRestRotation = t.localRotation;
            return;
        }
        Debug.LogWarning($"[FacePlayback] Head bone '{headBoneName}' not found — head rotation disabled.");
    }

    private void DriveSymmetricAverage(string sym, string left, string right)
    {
        if (!_targetMap.ContainsKey(sym)) return;
        float avg = (ReadFirstWeight(left) + ReadFirstWeight(right)) * 0.5f;
        foreach (var bt in _targetMap[sym])
            bt.Renderer.SetBlendShapeWeight(bt.Index, avg);
    }

    private float ReadFirstWeight(string name)
    {
        if (_targetMap.TryGetValue(name, out var list) && list.Count > 0)
            return list[0].Renderer.GetBlendShapeWeight(list[0].Index);
        return 0f;
    }
}
