using UnityEngine;

public class VRAvatarAnimationTrigger : MonoBehaviour
{
    [Header("Animation Settings")]
    public Animator animator;
    
    [Header("Trigger Settings")]
    [Tooltip("Trigger animation on Select (point and click)")]
    public bool triggerOnSelect = true;
    
    [Tooltip("Trigger animation on Activate (button press while hovering)")]
    public bool triggerOnActivate = true;
    
    [Header("Animation Triggers")]
    public string[] animationTriggers = new string[] { 
        "Arm",
        // "Capoeira", 
         
        // "Rumba", 
        // "HipHop", 
        // "Samba"
         };
    public bool randomAnimation = true;
    
    private int currentAnimationIndex = 0;

    void Awake()
    {
        if (animator == null)
        {
            animator = GetComponent<Animator>();
        }
    }
    void Start()
    {
        if (animator == null)
            return;

        // On device, animators can appear "stuck" due to culling or disabled state.
        animator.enabled = true;
        animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
        animator.updateMode = AnimatorUpdateMode.Normal;

        if (animator.runtimeAnimatorController == null)
        {
            Debug.LogError("[ANIMATORSCRIPT] Animator has no controller assigned.");
            return;
        }

        // Reset all triggers
        foreach (var trigger in animationTriggers)
            animator.ResetTrigger(trigger);

        // Ensure a clean initial state, then enter Idle.
        animator.Rebind();
        animator.Update(0f);
        animator.Play("Idle", 0, 0f);

        Debug.Log("[ANIMATORSCRIPT] Animator initialized and forced to Idle state on start");
    }
    
    void TriggerRandomAnimation()
    {
        if (animator == null)
        {
            Debug.LogError("[ANIMATORSCRIPT] Animator is null!");
            return;
        }
        
        if (animationTriggers.Length == 0)
        {
            Debug.LogError("[ANIMATORSCRIPT] No animation triggers defined!");
            return;
        }
        
        string triggerName;
        
        if (randomAnimation)
        {
            int randomIndex = Random.Range(0, animationTriggers.Length);
            triggerName = animationTriggers[randomIndex];
        }
        else
        {
            triggerName = animationTriggers[currentAnimationIndex];
            currentAnimationIndex = (currentAnimationIndex + 1) % animationTriggers.Length;
        }
        
        Debug.Log($"[ANIMATORSCRIPT] Setting animator trigger: {triggerName}");
        animator.SetTrigger(triggerName);
    }
    
    // For mouse click testing in editor
    void OnMouseDown()
    {
        Debug.Log("[ANIMATORSCRIPT] Mouse clicked on avatar");
        TriggerRandomAnimation();
    }
}
