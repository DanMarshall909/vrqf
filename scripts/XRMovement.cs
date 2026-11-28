using Godot;

namespace Vrqf;

public partial class XRMovement : XROrigin3D
{
    [Export] public NodePath CameraPath { get; set; } = "XRCamera3D";
    [Export] public NodePath LeftControllerPath { get; set; } = "LeftController";
    [Export] public NodePath RightControllerPath { get; set; } = "RightController";
    [Export] public float MoveSpeed { get; set; } = 2.0f;
    [Export] public float SnapTurnDegrees { get; set; } = 35.0f;
    [Export] public float SnapTurnDeadzone { get; set; } = 0.7f;
    [Export] public float MoveDeadzone { get; set; } = 0.1f;
    [Export] public bool DebugLogging { get; set; } = false;

    private XRCamera3D? _camera;
    private XRController3D? _leftController;
    private XRController3D? _rightController;
    private bool _snapTurnLatched;
    private ulong _diagFrames;

    public override void _Ready()
    {
        _camera = GetNodeOrNull<XRCamera3D>(CameraPath);
        _leftController = GetNodeOrNull<XRController3D>(LeftControllerPath);
        _rightController = GetNodeOrNull<XRController3D>(RightControllerPath);
        GD.Print($"XRMovement._Ready: Camera={(_camera?.Name.ToString() ?? "NULL")} Left={(_leftController?.Name.ToString() ?? "NULL")} Right={(_rightController?.Name.ToString() ?? "NULL")}");
    }

    public override void _Process(double delta)
    {
        if (_camera is null || _leftController is null || _rightController is null) return;

        if (DebugLogging && _diagFrames++ % 60 == 0)
        {
            var lStick = _leftController.GetVector2("primary");
            var rStick = _rightController.GetVector2("primary");
            GD.Print($"L pos={_leftController.GlobalPosition.Snapped(0.01f)} stick={lStick.Snapped(0.01f)} | R pos={_rightController.GlobalPosition.Snapped(0.01f)} stick={rStick.Snapped(0.01f)}");
        }

        SmoothLocomotion((float)delta);
        SnapTurn();
    }

    private void SmoothLocomotion(float delta)
    {
        var stick = _leftController!.GetVector2("primary");
        if (stick.LengthSquared() < MoveDeadzone * MoveDeadzone) return;

        var basis = _camera!.GlobalBasis;
        var forward = new Vector3(-basis.Z.X, 0, -basis.Z.Z).Normalized();
        var right = new Vector3(basis.X.X, 0, basis.X.Z).Normalized();
        var motion = (right * stick.X + forward * stick.Y) * MoveSpeed * delta;
        GlobalPosition += motion;
    }

    private void SnapTurn()
    {
        var turnX = _rightController!.GetVector2("primary").X;

        if (Mathf.Abs(turnX) < SnapTurnDeadzone)
        {
            _snapTurnLatched = false;
            return;
        }

        if (_snapTurnLatched) return;
        _snapTurnLatched = true;

        var angle = -Mathf.Sign(turnX) * Mathf.DegToRad(SnapTurnDegrees);
        var pivot = _camera!.GlobalPosition;
        var offset = GlobalPosition - pivot;
        offset = offset.Rotated(Vector3.Up, angle);
        GlobalPosition = pivot + offset;
        RotateY(angle);
    }
}
