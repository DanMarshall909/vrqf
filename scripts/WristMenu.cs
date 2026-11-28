using Godot;

namespace Vrqf;

// A settings panel anchored above the left controller, rendered via a
// SubViewport onto a quad. The right controller aims a ray at the panel;
// pulling the trigger injects a click into the SubViewport. All edits go
// through the shared FractalUiBuilder -> FractalController (and Main for AR),
// keeping desktop and VR controls unified and in sync.
public partial class WristMenu : Node3D
{
    [Export] public NodePath RightControllerPath { get; set; } = "../../RightController";
    [Export] public Vector2I Resolution { get; set; } = new(440, 640);
    [Export] public float PanelWidth { get; set; } = 0.16f;   // metres
    [Export] public float ClickThreshold { get; set; } = 0.6f; // trigger value that counts as a click

    // True while the right-controller ray is over the panel, so the
    // FractalController suppresses trigger-scrub (the trigger is the click).
    public static bool PointerOverPanel;

    private FractalController? _fc;
    private Main? _main;
    private FractalUiView? _view;
    private XRController3D? _right;
    private SubViewport? _vp;
    private MeshInstance3D? _quad;
    private MeshInstance3D? _laser;
    private MeshInstance3D? _cursor;
    private float _panelHeight;
    private float _prevTrigger;
    private bool _wasOnPanel;

    public override void _Ready()
    {
        _fc = GetTree().GetFirstNodeInGroup("fractal_controller") as FractalController;
        _main = GetTree().CurrentScene as Main;
        _right = GetNodeOrNull<XRController3D>(RightControllerPath);
        _panelHeight = PanelWidth * Resolution.Y / Resolution.X;

        BuildViewport();
        BuildQuad();

        if (_fc is not null)
            _fc.StateChanged += OnStateChanged;
        if (_main is not null)
            _main.ArModeChanged += OnStateChanged;

        RequestViewportUpdate();
    }

    public override void _ExitTree()
    {
        if (_fc is not null)
            _fc.StateChanged -= OnStateChanged;
        if (_main is not null)
            _main.ArModeChanged -= OnStateChanged;
    }

    private void BuildViewport()
    {
        _vp = new SubViewport
        {
            Size = Resolution,
            TransparentBg = true,
            Disable3D = true,
            RenderTargetUpdateMode = SubViewport.UpdateMode.Once,
            GuiDisableInput = false,
        };
        AddChild(_vp);

        var bg = new ColorRect { Color = new Color(0.07f, 0.08f, 0.11f, 0.92f) };
        bg.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        _vp.AddChild(bg);

        var margin = new MarginContainer();
        margin.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        foreach (var side in new[] { "margin_left", "margin_top", "margin_right", "margin_bottom" })
            margin.AddThemeConstantOverride(side, 8);
        _vp.AddChild(margin);

        var tabs = new TabContainer { Name = "WristTabs" };
        tabs.TabChanged += _ => RequestViewportUpdate();
        margin.AddChild(tabs);

        if (_fc is not null)
            _view = FractalUiBuilder.Build(tabs, _fc, _main, UiMode.VrWrist);
    }

    private void BuildQuad()
    {
        _quad = new MeshInstance3D
        {
            Mesh = new QuadMesh { Size = new Vector2(PanelWidth, _panelHeight) },
        };
        var mat = new StandardMaterial3D
        {
            ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
            Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
            CullMode = BaseMaterial3D.CullModeEnum.Disabled,
            AlbedoTexture = _vp!.GetTexture(),
            TextureFilter = BaseMaterial3D.TextureFilterEnum.Linear,
        };
        _quad.MaterialOverride = mat;
        AddChild(_quad);

        // Cursor dot, shown on the panel where the ray lands (child of the quad).
        _cursor = new MeshInstance3D { Mesh = new SphereMesh { Radius = 0.004f, Height = 0.008f } };
        _cursor.MaterialOverride = Emissive(new Color(0.4f, 1f, 0.7f));
        _cursor.Visible = false;
        _quad.AddChild(_cursor);

        // Laser from the right controller, pointing forward (-Z).
        if (_right is not null)
        {
            _laser = new MeshInstance3D
            {
                Mesh = new BoxMesh { Size = new Vector3(0.003f, 0.003f, 1.2f) },
                Position = new Vector3(0, 0, -0.6f),
            };
            _laser.MaterialOverride = Emissive(new Color(0.3f, 0.8f, 1f));
            _right.AddChild(_laser);
        }
    }

    private static StandardMaterial3D Emissive(Color c) => new()
    {
        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
        AlbedoColor = c,
    };

    public override void _Process(double _delta) => PollPointer();

    private void OnStateChanged()
    {
        _view?.RebuildDynamicTabIfNeeded();
        _view?.Refresh();
        RequestViewportUpdate();
    }

    private void RequestViewportUpdate()
    {
        if (_vp is not null)
            _vp.RenderTargetUpdateMode = SubViewport.UpdateMode.Once;
    }

    // Ray-cast the right controller forward onto the panel plane and inject
    // mouse motion / clicks (trigger) into the SubViewport — a laser pointer.
    private void PollPointer()
    {
        if (_right is null || _quad is null || _vp is null) return;

        Transform3D qt = _quad.GlobalTransform;
        Vector3 normal = qt.Basis.Z.Normalized();           // panel faces +Z
        Vector3 ro = _right.GlobalPosition;
        Vector3 rd = -_right.GlobalTransform.Basis.Z.Normalized(); // controller forward

        float denom = rd.Dot(normal);
        bool onPanel = false;
        var px = Vector2.Zero;

        if (Mathf.Abs(denom) > 1e-5f)
        {
            float t = (qt.Origin - ro).Dot(normal) / denom;
            if (t > 0f)
            {
                Vector3 local = qt.AffineInverse() * (ro + rd * t);
                float hw = PanelWidth * 0.5f, hh = _panelHeight * 0.5f;
                if (Mathf.Abs(local.X) <= hw && Mathf.Abs(local.Y) <= hh)
                {
                    onPanel = true;
                    if (_cursor is not null)
                    {
                        _cursor.Position = new Vector3(local.X, local.Y, 0.002f);
                        _cursor.Visible = true;
                    }
                    px = new Vector2(
                        (local.X / PanelWidth + 0.5f) * Resolution.X,
                        (0.5f - local.Y / _panelHeight) * Resolution.Y);
                    _vp.PushInput(new InputEventMouseMotion { Position = px });
                }
            }
        }

        PointerOverPanel = onPanel;
        if (!onPanel && _cursor is not null) _cursor.Visible = false;

        // Trigger rising edge = click (only while pointing at the panel).
        float trigger = _right.GetFloat("trigger");
        if (onPanel && trigger >= ClickThreshold && _prevTrigger < ClickThreshold)
        {
            _vp.PushInput(new InputEventMouseButton { Position = px, ButtonIndex = MouseButton.Left, Pressed = true });
            _vp.PushInput(new InputEventMouseButton { Position = px, ButtonIndex = MouseButton.Left, Pressed = false });
        }
        _prevTrigger = trigger;

        if (onPanel || _wasOnPanel)
            RequestViewportUpdate();
        _wasOnPanel = onPanel;
    }
}
