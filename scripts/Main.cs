using Godot;

namespace Vrqf;

public partial class Main : Node3D
{
    [Export] public NodePath FlatCameraPath { get; set; } = "FlatCamera";
    [Export] public NodePath XrOriginPath { get; set; } = "XROrigin3D";

    // Start in AR (passthrough) when the headset is present.
    [Export] public bool StartInAr { get; set; } = true;

    private XRInterface? _xr;
    private bool _passthroughSupported;
    private bool _ar;

    public override void _Ready()
    {
        _xr = XRServer.FindInterface("OpenXR");

        if (_xr is not null && _xr.IsInitialized())
        {
            GetViewport().UseXR = true;
            DisplayServer.WindowSetVsyncMode(DisplayServer.VSyncMode.Disabled);
            GD.Print("vrqf M1 — OpenXR ready");

            _passthroughSupported = ProbePassthrough();
            ConnectToggle("XROrigin3D/LeftController");
            ConnectToggle("XROrigin3D/RightController");
            SetAr(StartInAr && _passthroughSupported);
        }
        else
        {
            GetNode<Node3D>(XrOriginPath).Visible = false;
            GetNode<Camera3D>(FlatCameraPath).Current = true;
            GD.Print("vrqf M1 — OpenXR unavailable, flat debug mode");
        }
    }

    // Returns true if the runtime accepts alpha-blend (passthrough) compositing.
    private bool ProbePassthrough()
    {
        GD.Print("vrqf AR — supported blend modes: ", _xr!.GetSupportedEnvironmentBlendModes());
        var alpha = XRInterface.EnvironmentBlendModeEnum.AlphaBlend;
        _xr.EnvironmentBlendMode = alpha;
        bool ok = _xr.EnvironmentBlendMode == alpha;
        _xr.EnvironmentBlendMode = XRInterface.EnvironmentBlendModeEnum.Opaque;
        if (!ok)
            GD.Print("vrqf AR — runtime offers no alpha-blend passthrough (enable passthrough in Virtual Desktop / use Meta runtime). Staying VR.");
        return ok;
    }

    private void ConnectToggle(string path)
    {
        if (GetNodeOrNull<XRController3D>(path) is XRController3D c)
            c.ButtonPressed += name => { if (name == "menu_button") ToggleAr(); };
    }

    private void ToggleAr()
    {
        if (_passthroughSupported) SetAr(!_ar);
    }

    // Switch between VR (opaque sky) and AR (passthrough): the real room shows
    // wherever the frame is transparent, so the fractal floats in your space.
    private void SetAr(bool on)
    {
        if (_xr is null) return;
        _ar = on;

        _xr.EnvironmentBlendMode = on
            ? XRInterface.EnvironmentBlendModeEnum.AlphaBlend
            : XRInterface.EnvironmentBlendModeEnum.Opaque;
        GetViewport().TransparentBg = on;

        if (GetNodeOrNull<Node3D>("Floor") is Node3D floor)
            floor.Visible = !on; // the real floor replaces the virtual one in AR

        if (GetNodeOrNull<WorldEnvironment>("WorldEnvironment")?.Environment is Environment env)
            env.BackgroundMode = on ? Environment.BGMode.ClearColor : Environment.BGMode.Sky;

        GD.Print(on ? "vrqf AR — passthrough ON" : "vrqf AR — passthrough OFF (VR)");
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventKey { Pressed: true, Echo: false, Keycode: Key.V })
            ToggleAr();
    }
}
