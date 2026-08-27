// HOW TO USE
// Attach this component to ANY ancestor of your Avaturn GLB(s):
//   • One avatar  → attach to that avatar's root GameObject.
//   • Many avatars under one parent → attach once to the parent.
//     The script finds every skeleton under it and sets them all up.
//
// Assign your RuntimeAnimatorController in the Inspector.
// If a child avatar already has an Animator with a controller assigned,
// that controller is kept automatically (no need to reassign).
//
// No external packages required — uses Unity's built-in AvatarBuilder.

using System.Collections.Generic;
using UnityEngine;

[DisallowMultipleComponent]
public class AvaturnAnimationPrepare : MonoBehaviour
{
    [SerializeField] public RuntimeAnimatorController animatorController;

    // Maps Unity's Humanoid bone names to the two naming schemes Avaturn GLBs use.
    private static readonly Dictionary<string, string[]> k_HumanBoneMap = new()
    {
        { "Hips",                          new[] { "Hips",              "mixamorig:Hips"              } },
        { "LeftUpperLeg",                  new[] { "LeftUpLeg",         "mixamorig:LeftUpLeg"         } },
        { "RightUpperLeg",                 new[] { "RightUpLeg",        "mixamorig:RightUpLeg"        } },
        { "LeftLowerLeg",                  new[] { "LeftLeg",           "mixamorig:LeftLeg"           } },
        { "RightLowerLeg",                 new[] { "RightLeg",          "mixamorig:RightLeg"          } },
        { "LeftFoot",                      new[] { "LeftFoot",          "mixamorig:LeftFoot"          } },
        { "RightFoot",                     new[] { "RightFoot",         "mixamorig:RightFoot"         } },
        { "Spine",                         new[] { "Spine",             "mixamorig:Spine"             } },
        { "Chest",                         new[] { "Spine1",            "mixamorig:Spine1"            } },
        { "UpperChest",                    new[] { "Spine2",            "mixamorig:Spine2"            } },
        { "Neck",                          new[] { "Neck",              "mixamorig:Neck"              } },
        { "Head",                          new[] { "Head",              "mixamorig:Head"              } },
        { "LeftShoulder",                  new[] { "LeftShoulder",      "mixamorig:LeftShoulder"      } },
        { "RightShoulder",                 new[] { "RightShoulder",     "mixamorig:RightShoulder"     } },
        { "LeftUpperArm",                  new[] { "LeftArm",           "mixamorig:LeftArm"           } },
        { "RightUpperArm",                 new[] { "RightArm",          "mixamorig:RightArm"          } },
        { "LeftLowerArm",                  new[] { "LeftForeArm",       "mixamorig:LeftForeArm"       } },
        { "RightLowerArm",                 new[] { "RightForeArm",      "mixamorig:RightForeArm"      } },
        { "LeftHand",                      new[] { "LeftHand",          "mixamorig:LeftHand"          } },
        { "RightHand",                     new[] { "RightHand",         "mixamorig:RightHand"         } },
        { "LeftToes",                      new[] { "LeftToeBase",       "mixamorig:LeftToeBase"       } },
        { "RightToes",                     new[] { "RightToeBase",      "mixamorig:RightToeBase"      } },
        { "Left Thumb Proximal",           new[] { "LeftHandThumb1",    "mixamorig:LeftHandThumb1"    } },
        { "Left Thumb Intermediate",       new[] { "LeftHandThumb2",    "mixamorig:LeftHandThumb2"    } },
        { "Left Thumb Distal",             new[] { "LeftHandThumb3",    "mixamorig:LeftHandThumb3"    } },
        { "Left Index Proximal",           new[] { "LeftHandIndex1",    "mixamorig:LeftHandIndex1"    } },
        { "Left Index Intermediate",       new[] { "LeftHandIndex2",    "mixamorig:LeftHandIndex2"    } },
        { "Left Index Distal",             new[] { "LeftHandIndex3",    "mixamorig:LeftHandIndex3"    } },
        { "Left Middle Proximal",          new[] { "LeftHandMiddle1",   "mixamorig:LeftHandMiddle1"   } },
        { "Left Middle Intermediate",      new[] { "LeftHandMiddle2",   "mixamorig:LeftHandMiddle2"   } },
        { "Left Middle Distal",            new[] { "LeftHandMiddle3",   "mixamorig:LeftHandMiddle3"   } },
        { "Left Ring Proximal",            new[] { "LeftHandRing1",     "mixamorig:LeftHandRing1"     } },
        { "Left Ring Intermediate",        new[] { "LeftHandRing2",     "mixamorig:LeftHandRing2"     } },
        { "Left Ring Distal",              new[] { "LeftHandRing3",     "mixamorig:LeftHandRing3"     } },
        { "Left Little Proximal",          new[] { "LeftHandPinky1",    "mixamorig:LeftHandPinky1"    } },
        { "Left Little Intermediate",      new[] { "LeftHandPinky2",    "mixamorig:LeftHandPinky2"    } },
        { "Left Little Distal",            new[] { "LeftHandPinky3",    "mixamorig:LeftHandPinky3"    } },
        { "Right Thumb Proximal",          new[] { "RightHandThumb1",   "mixamorig:RightHandThumb1"   } },
        { "Right Thumb Intermediate",      new[] { "RightHandThumb2",   "mixamorig:RightHandThumb2"   } },
        { "Right Thumb Distal",            new[] { "RightHandThumb3",   "mixamorig:RightHandThumb3"   } },
        { "Right Index Proximal",          new[] { "RightHandIndex1",   "mixamorig:RightHandIndex1"   } },
        { "Right Index Intermediate",      new[] { "RightHandIndex2",   "mixamorig:RightHandIndex2"   } },
        { "Right Index Distal",            new[] { "RightHandIndex3",   "mixamorig:RightHandIndex3"   } },
        { "Right Middle Proximal",         new[] { "RightHandMiddle1",  "mixamorig:RightHandMiddle1"  } },
        { "Right Middle Intermediate",     new[] { "RightHandMiddle2",  "mixamorig:RightHandMiddle2"  } },
        { "Right Middle Distal",           new[] { "RightHandMiddle3",  "mixamorig:RightHandMiddle3"  } },
        { "Right Ring Proximal",           new[] { "RightHandRing1",    "mixamorig:RightHandRing1"    } },
        { "Right Ring Intermediate",       new[] { "RightHandRing2",    "mixamorig:RightHandRing2"    } },
        { "Right Ring Distal",             new[] { "RightHandRing3",    "mixamorig:RightHandRing3"    } },
        { "Right Little Proximal",         new[] { "RightHandPinky1",   "mixamorig:RightHandPinky1"   } },
        { "Right Little Intermediate",     new[] { "RightHandPinky2",   "mixamorig:RightHandPinky2"   } },
        { "Right Little Distal",           new[] { "RightHandPinky3",   "mixamorig:RightHandPinky3"   } },
    };

    private void Start()
    {
        var skeletonRoots = new List<Transform>();
        CollectSkeletonRoots(transform, skeletonRoots);

        if (skeletonRoots.Count == 0)
        {
            Debug.LogError("[AvaturnPrepare] No skeleton (Hips bone) found under '" + name +
                           "'. Check the avatar hierarchy.", this);
            return;
        }

        int ok = 0;
        foreach (var root in skeletonRoots)
            if (PrepareOne(root)) ok++;

        Debug.Log($"[AvaturnPrepare] Animated {ok}/{skeletonRoots.Count} avatar(s) under '{name}'.", this);
    }

    // ── Per-skeleton setup ────────────────────────────────────────────────────

    private bool PrepareOne(Transform skeletonRoot)
    {
        // Remove the legacy Animation component GLTFast sometimes adds.
        if (skeletonRoot.TryGetComponent<Animation>(out var legacyAnim))
            Destroy(legacyAnim);

        // Reuse an existing Animator between this component's root and skeletonRoot
        // (top-down preference). This picks up prefab-instance Animators that already
        // have a controller, so you don't have to reassign it per-avatar.
        var animator = FindAnimatorOnPath(transform, skeletonRoot);

        // Build a Humanoid Avatar from the T-pose so Mixamo clips retarget correctly.
        var avatar = BuildHumanoidAvatar(skeletonRoot);
        if (avatar != null && avatar.isValid)
        {
            animator.avatar = avatar;
        }
        else
        {
            Debug.LogWarning("[AvaturnPrepare] AvatarBuilder failed on '" + skeletonRoot.name +
                             "' — check the skeleton is in T-pose.", this);
            return false;
        }

        // Explicitly assigned controller wins; otherwise keep whatever is already set.
        if (animatorController != null)
            animator.runtimeAnimatorController = animatorController;
        else if (animator.runtimeAnimatorController == null)
            Debug.LogWarning("[AvaturnPrepare] No RuntimeAnimatorController for '" +
                             skeletonRoot.name + "' — assign one in the Inspector.", this);

        animator.applyRootMotion = false;
        return true;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Recursively collects every Transform whose direct child is named Hips/mixamorig:Hips.
    private static void CollectSkeletonRoots(Transform t, List<Transform> result)
    {
        for (int i = 0; i < t.childCount; i++)
        {
            var child = t.GetChild(i);
            string n = child.name;
            if (n == "Hips" || n == "mixamorig:Hips")
            {
                result.Add(t);
                return; // don't recurse further into this avatar's subtree
            }
        }
        for (int i = 0; i < t.childCount; i++)
            CollectSkeletonRoots(t.GetChild(i), result);
    }

    // Walks bottom-up from skeletonRoot toward scriptRoot (exclusive) and returns the
    // first Animator found. Excludes scriptRoot itself so a shared parent Animator
    // (e.g. on the Avatars container) is never used by multiple independent avatars.
    // Falls back to creating one on skeletonRoot if none exists in the subtree.
    private static Animator FindAnimatorOnPath(Transform scriptRoot, Transform skeletonRoot)
    {
        for (var t = skeletonRoot; t != null && t != scriptRoot; t = t.parent)
        {
            if (t.TryGetComponent<Animator>(out var a))
                return a;
        }
        return skeletonRoot.gameObject.AddComponent<Animator>();
    }

    // Builds a runtime Humanoid Avatar from the skeleton's current (T-pose) transforms.
    private static Avatar BuildHumanoidAvatar(Transform skeletonRoot)
    {
        var allTransforms = skeletonRoot.GetComponentsInChildren<Transform>(true);

        var byName = new Dictionary<string, Transform>(allTransforms.Length);
        foreach (var t in allTransforms)
            if (!byName.ContainsKey(t.name))
                byName[t.name] = t;

        var humanBones = new List<HumanBone>();
        foreach (var kvp in k_HumanBoneMap)
        {
            foreach (var candidate in kvp.Value)
            {
                if (!byName.ContainsKey(candidate)) continue;
                humanBones.Add(new HumanBone
                {
                    humanName = kvp.Key,
                    boneName  = candidate,
                    limit     = new HumanLimit { useDefaultValues = true }
                });
                break;
            }
        }

        var skeletonBones = new SkeletonBone[allTransforms.Length];
        for (int i = 0; i < allTransforms.Length; i++)
        {
            var t = allTransforms[i];
            skeletonBones[i] = new SkeletonBone
            {
                name     = t.name,
                position = t.localPosition,
                rotation = t.localRotation,
                scale    = t.localScale,
            };
        }

        var desc = new HumanDescription
        {
            human             = humanBones.ToArray(),
            skeleton          = skeletonBones,
            upperArmTwist     = 0.5f,
            lowerArmTwist     = 0.5f,
            upperLegTwist     = 0.5f,
            lowerLegTwist     = 0.5f,
            armStretch        = 0.05f,
            legStretch        = 0.05f,
            feetSpacing       = 0f,
            hasTranslationDoF = false,
        };

        return AvatarBuilder.BuildHumanAvatar(skeletonRoot.gameObject, desc);
    }
}
