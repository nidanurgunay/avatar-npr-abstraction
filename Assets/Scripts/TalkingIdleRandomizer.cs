// TalkingIdleRandomizer.cs
// Attach to the Avatars parent alongside AvaturnAnimationPrepare.
// Randomly switches all child animators between Arguing and Idle states.

using System.Collections;
using UnityEngine;

public class TalkingIdleRandomizer : MonoBehaviour
{
    [Header("Arguing duration range (seconds)")]
    [SerializeField] private float arguingMin = 3f;
    [SerializeField] private float arguingMax = 6f;

    [Header("Idle duration range (seconds)")]
    [SerializeField] private float idleMin = 2f;
    [SerializeField] private float idleMax = 4f;

    private Animator[] _animators;

    private void Start()
    {
        _animators = GetComponentsInChildren<Animator>(true);
        StartCoroutine(SwitchLoop());
    }

    private IEnumerator SwitchLoop()
    {
        while (true)
        {
            // Play arguing
            SetIdle(false);
            yield return new WaitForSeconds(Random.Range(arguingMin, arguingMax));

            // Switch to idle
            SetIdle(true);
            yield return new WaitForSeconds(Random.Range(idleMin, idleMax));
        }
    }

    private void SetIdle(bool idle)
    {
        foreach (var a in _animators)
            if (a != null) a.SetBool("IsIdle", idle);
    }
}
