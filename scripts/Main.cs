using Godot;

namespace Vrqf;

public partial class Main : Node3D
{
    [Export] public NodePath FlatCameraPath { get; set; } = "FlatCamera";
    [Export] public NodePath XrOriginPath { get; set; } = "XROrigin3D";

    public override void _Ready()
    {
        var xr = XRServer.FindInterface("OpenXR");

        if (xr is not null && xr.IsInitialized())
        {
            GetViewport().UseXR = true;
            DisplayServer.WindowSetVsyncMode(DisplayServer.VSyncMode.Disabled);
            GD.Print("vrqf M1 — OpenXR ready");
        }
        else
        {
            GetNode<Node3D>(XrOriginPath).Visible = false;
            GetNode<Camera3D>(FlatCameraPath).Current = true;
            GD.Print("vrqf M1 — OpenXR unavailable, flat debug mode");
        }
    }
}
