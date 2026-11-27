using Godot;

namespace Vrqf;

public partial class FreeLookCamera : Camera3D
{
    [Export] public float MoveSpeed { get; set; } = 2.0f;
    [Export] public float MouseSensitivity { get; set; } = 0.0025f;

    private float _yaw;
    private float _pitch;

    public override void _Ready()
    {
        // Leave the pointer available for the desktop explorer controls.
        // Clicking the scene captures it for free look; Esc releases it again.
        Input.MouseMode = Input.MouseModeEnum.Visible;
        var euler = GlobalTransform.Basis.GetEuler();
        _yaw = euler.Y;
        _pitch = euler.X;
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventMouseMotion motion && Input.MouseMode == Input.MouseModeEnum.Captured)
        {
            _yaw -= motion.Relative.X * MouseSensitivity;
            _pitch = Mathf.Clamp(_pitch - motion.Relative.Y * MouseSensitivity, -Mathf.Pi / 2 + 0.01f, Mathf.Pi / 2 - 0.01f);
            Rotation = new Vector3(_pitch, _yaw, 0);
        }
        else if (@event.IsActionPressed("toggle_mouse_capture"))
        {
            Input.MouseMode = Input.MouseMode == Input.MouseModeEnum.Captured
                ? Input.MouseModeEnum.Visible
                : Input.MouseModeEnum.Captured;
        }
        else if (@event is InputEventMouseButton { Pressed: true } && Input.MouseMode == Input.MouseModeEnum.Visible)
        {
            Input.MouseMode = Input.MouseModeEnum.Captured;
        }
    }

    public override void _Process(double delta)
    {
        var input = new Vector3(
            Input.GetActionStrength("move_right") - Input.GetActionStrength("move_left"),
            Input.GetActionStrength("move_up") - Input.GetActionStrength("move_down"),
            Input.GetActionStrength("move_back") - Input.GetActionStrength("move_forward"));

        if (input == Vector3.Zero) return;

        var basis = Transform.Basis;
        var motion = (basis.X * input.X + Vector3.Up * input.Y + basis.Z * input.Z) * MoveSpeed * (float)delta;
        Position += motion;
    }
}
