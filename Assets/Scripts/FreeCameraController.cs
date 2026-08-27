using UnityEngine;
using UnityEngine.InputSystem; // New Input System — replaces the old UnityEngine.Input class

// This script lets you fly the camera around the scene using the keyboard and mouse.
// Attach it to your Main Camera GameObject.
public class FreeCameraController : MonoBehaviour
{
    [Header("Movement Speed")]
    [Tooltip("How fast the camera moves normally.")]
    public float moveSpeed = 5f;

    [Tooltip("Hold Left Shift to move this much faster.")]
    public float fastSpeed = 15f;

    [Header("Mouse Look")]
    // The new Input System gives raw pixel delta (e.g. 10 pixels/frame at normal speed),
    // so 0.1 here is equivalent to ~3 in the old system.
    [Tooltip("How sensitive the mouse rotation is.")]
    public float mouseSensitivity = 0.1f;

    // We store the current rotation angles ourselves so we can add to them smoothly.
    // Unity works with Euler angles (pitch = up/down, yaw = left/right).
    private float _pitch = 0f; // up / down rotation
    private float _yaw   = 0f; // left / right rotation

    // Called once when the game starts. We read the camera's starting rotation
    // so it doesn't snap when you first move the mouse.
    private void Start()
    {
        _pitch = transform.eulerAngles.x;
        _yaw   = transform.eulerAngles.y;
    }

    // Called every frame — this is where all the movement happens.
    private void Update()
    {
        HandleMouseLook();
        HandleMovement();
    }

    // ── Mouse look (only while right mouse button is held) ───────────────────
    private void HandleMouseLook()
    {
        // Mouse.current is the active mouse device detected by the Input System.
        // rightButton.isPressed is true while the RIGHT mouse button is held down.
        if (Mouse.current == null || !Mouse.current.rightButton.isPressed)
            return;

        // Mouse.current.delta.ReadValue() returns how many pixels the mouse moved this frame
        // as a Vector2 (x = horizontal, y = vertical).
        Vector2 mouseDelta = Mouse.current.delta.ReadValue();

        _yaw   += mouseDelta.x * mouseSensitivity;

        // Mouse Y is inverted by convention: moving the mouse up should tilt the camera up,
        // but Unity's X rotation increases downward, so we subtract instead of add.
        _pitch -= mouseDelta.y * mouseSensitivity;

        // Clamp pitch so you can't flip the camera upside-down (limited to -89 / +89 degrees).
        _pitch = Mathf.Clamp(_pitch, -89f, 89f);

        // Apply the rotation to the camera.
        // Quaternion.Euler builds a rotation from three angle values.
        transform.rotation = Quaternion.Euler(_pitch, _yaw, 0f);
    }

    // ── Keyboard movement ────────────────────────────────────────────────────
    private void HandleMovement()
    {
        // Keyboard.current is the active keyboard device.
        // If no keyboard is connected (e.g. on a device without one), we exit early.
        var kb = Keyboard.current;
        if (kb == null) return;

        // Choose speed: hold Left Shift for fast mode, otherwise normal speed.
        float speed = kb.leftShiftKey.isPressed ? fastSpeed : moveSpeed;

        // Build a direction from WASD / arrow keys.
        // We check each key individually and add +1 or -1 to get a -1..0..1 direction value.
        float horizontal = 0f;
        float vertical   = 0f;

        if (kb.dKey.isPressed || kb.rightArrowKey.isPressed) horizontal += 1f; // strafe right
        if (kb.aKey.isPressed || kb.leftArrowKey.isPressed)  horizontal -= 1f; // strafe left
        if (kb.wKey.isPressed || kb.upArrowKey.isPressed)    vertical   += 1f; // move forward
        if (kb.sKey.isPressed || kb.downArrowKey.isPressed)  vertical   -= 1f; // move backward

        // transform.right   = the camera's local X axis (pointing sideways)
        // transform.forward = the camera's local Z axis (pointing where the camera looks)
        Vector3 move = transform.right   * horizontal
                     + transform.forward * vertical;

        // Q moves the camera straight down, E moves it straight up (world Y axis).
        if (kb.eKey.isPressed) move += Vector3.up;
        if (kb.qKey.isPressed) move += Vector3.down;

        // Actually move the camera.
        // Time.deltaTime is the time since last frame (in seconds).
        // Multiplying by it makes movement frame-rate independent — same speed on any computer.
        transform.position += move * speed * Time.deltaTime;
    }
}
