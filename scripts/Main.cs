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

            // The project sets environment_blend_mode=2 (alpha blend); with the
            // godot_openxr_vendors plugin emulating passthrough, the interface
            // comes up in AlphaBlend if passthrough was created successfully.
            // Just check it (don't toggle the mode — that can disrupt the
            // plugin's passthrough setup). Mirrors the official sample.
            _passthroughSupported =
                _xr.EnvironmentBlendMode == XRInterface.EnvironmentBlendModeEnum.AlphaBlend;
            GD.Print($"vrqf AR — blend mode at startup: {_xr.EnvironmentBlendMode} (passthrough {(_passthroughSupported ? "available" : "unavailable — staying VR")})");

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

    private void ConnectToggle(string path)
    {
        if (GetNodeOrNull<XRController3D>(path) is XRController3D c)
            c.ButtonPressed += name => { if (name == "menu_button") ToggleHelp(); };
    }

    private void ToggleHelp() => GetNodeOrNull<HelpOverlay>("Help")?.Toggle();

    public event System.Action? ArModeChanged;

    public bool ArAvailable => _passthroughSupported;
    public bool IsAr => _ar;

    public void ToggleAr()
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

        if (GetNodeOrNull<ReflectionProbe>("ReflectionProbe") is ReflectionProbe probe)
        {
            probe.UpdateMode = ReflectionProbe.UpdateModeEnum.Always;
            probe.SetDeferred(ReflectionProbe.PropertyName.UpdateMode, (int)ReflectionProbe.UpdateModeEnum.Once);
        }

        GD.Print(on ? "vrqf AR — passthrough ON" : "vrqf AR — passthrough OFF (VR)");
        ArModeChanged?.Invoke();
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == Key.V) ToggleAr();
        else if (key.Unicode == '?' || key.Keycode == Key.Help) ToggleHelp();
    }
}
