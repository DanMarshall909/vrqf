using Godot;

namespace Vrqf;

// A settings panel anchored above the left controller, rendered via a
// SubViewport onto a quad. You "poke" the buttons with the right controller:
// when its position enters a button's area on the panel, a click is injected
// into the SubViewport. All edits go through the FractalController (and Main
// for the AR toggle), so the menu, triggers, and shader stay in sync.
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
    private XRController3D? _right;
    private SubViewport? _vp;
    private MeshInstance3D? _quad;
    private MeshInstance3D? _laser;
    private MeshInstance3D? _cursor;
    private float _panelHeight;
    private float _prevTrigger;

    private Label? _fracVal, _matVal, _palVal, _detailVal, _shapeVal, _speedVal, _zoomVal, _qualVal;
    private Label? _morphTgtVal, _morphVal;
    private Button? _arBtn;

    public override void _Ready()
    {
        _fc = GetTree().GetFirstNodeInGroup("fractal_controller") as FractalController;
        _main = GetTree().CurrentScene as Main;
        _right = GetNodeOrNull<XRController3D>(RightControllerPath);
        _panelHeight = PanelWidth * Resolution.Y / Resolution.X;

        BuildViewport();
        BuildQuad();
    }

    private void BuildViewport()
    {
        _vp = new SubViewport
        {
            Size = Resolution,
            TransparentBg = true,
            Disable3D = true,
            RenderTargetUpdateMode = SubViewport.UpdateMode.Always,
            GuiDisableInput = false,
        };
        AddChild(_vp);

        var bg = new ColorRect { Color = new Color(0.07f, 0.08f, 0.11f, 0.92f) };
        bg.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        _vp.AddChild(bg);

        var margin = new MarginContainer();
        margin.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        foreach (var side in new[] { "margin_left", "margin_top", "margin_right", "margin_bottom" })
            margin.AddThemeConstantOverride(side, 14);
        _vp.AddChild(margin);

        var col = new VBoxContainer();
        col.AddThemeConstantOverride("separation", 8);
        margin.AddChild(col);

        col.AddChild(Header("FRACTAL"));
        _fracVal = SelectorRow(col, "Fractal", d => _fc?.CycleFractal(d));
        _matVal = SelectorRow(col, "Material", d => _fc?.CycleMaterial(d));
        _palVal = SelectorRow(col, "Palette", d => _fc?.CyclePalette(d));

        col.AddChild(Header("PARAMETERS"));
        _detailVal = StepRow(col, "Detail", d => _fc?.AdjustDetail(d), 1f);
        _shapeVal = StepRow(col, "Shape", d => _fc?.AdjustShape(d), 0.3f);
        _speedVal = StepRow(col, "Speed", d => _fc?.AdjustSpeed(d), 0.05f);
        _zoomVal = StepRow(col, "Zoom", d => _fc?.AdjustZoom(d), 0.1f);
        _qualVal = StepRow(col, "Quality", d => _fc?.AdjustQuality(d), 8f);

        col.AddChild(Header("MORPH"));
        _morphTgtVal = SelectorRow(col, "Target", d => _fc?.CycleMorphTarget(d));
        _morphVal = StepRow(col, "Morph", d => _fc?.AdjustMorph(d), 0.1f);

        var rnd = new Button { Text = "Randomize", CustomMinimumSize = new Vector2(0, 60) };
        rnd.AddThemeFontSizeOverride("font_size", 24);
        rnd.Pressed += () => _fc?.Randomize();
        col.AddChild(rnd);

        _arBtn = new Button { Text = "AR / VR", CustomMinimumSize = new Vector2(0, 60) };
        _arBtn.AddThemeFontSizeOverride("font_size", 24);
        _arBtn.Pressed += () => _main?.ToggleAr();
        col.AddChild(_arBtn);
    }

    private static Label Header(string text)
    {
        var l = new Label { Text = text };
        l.AddThemeFontSizeOverride("font_size", 20);
        l.AddThemeColorOverride("font_color", new Color(0.55f, 0.75f, 1f));
        return l;
    }

    private Label SelectorRow(VBoxContainer parent, string name, System.Action<int> cycle)
    {
        var (row, value) = RowBase(name);
        row.AddChild(StepButton("<", () => cycle(-1)));
        row.AddChild(value);
        row.AddChild(StepButton(">", () => cycle(1)));
        parent.AddChild(row);
        return value;
    }

    private Label StepRow(VBoxContainer parent, string name, System.Action<float> adjust, float step)
    {
        var (row, value) = RowBase(name);
        row.AddChild(StepButton("-", () => adjust(-step)));
        row.AddChild(value);
        row.AddChild(StepButton("+", () => adjust(step)));
        parent.AddChild(row);
        return value;
    }

    private (HBoxContainer, Label) RowBase(string name)
    {
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", 8);
        var label = new Label { Text = name, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        label.AddThemeFontSizeOverride("font_size", 22);
        row.AddChild(label);
        var value = new Label
        {
            Text = "-",
            CustomMinimumSize = new Vector2(96, 0),
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        value.AddThemeFontSizeOverride("font_size", 22);
        value.AddThemeColorOverride("font_color", new Color(0.95f, 0.85f, 0.4f));
        return (row, value);
    }

    private static Button StepButton(string text, System.Action onPressed)
    {
        var b = new Button { Text = text, CustomMinimumSize = new Vector2(64, 56) };
        b.AddThemeFontSizeOverride("font_size", 26);
        b.Pressed += () => onPressed();
        return b;
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

    public override void _Process(double _delta)
    {
        RefreshValues();
        PollPointer();
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
    }

    private void RefreshValues()
    {
        if (_fc is null) return;
        if (_fracVal is not null) _fracVal.Text = _fc.FractalName;
        if (_matVal is not null) _matVal.Text = _fc.MaterialName;
        if (_palVal is not null) _palVal.Text = _fc.PaletteName;
        if (_detailVal is not null) _detailVal.Text = _fc.DetailText;
        if (_shapeVal is not null) _shapeVal.Text = _fc.ShapeText;
        if (_speedVal is not null) _speedVal.Text = _fc.SpeedText;
        if (_zoomVal is not null) _zoomVal.Text = _fc.ZoomText;
        if (_qualVal is not null) _qualVal.Text = _fc.QualityText;
        if (_morphTgtVal is not null) _morphTgtVal.Text = _fc.MorphTargetName;
        if (_morphVal is not null) _morphVal.Text = _fc.MorphText;
        if (_arBtn is not null && _main is not null)
            _arBtn.Text = _main.ArAvailable ? (_main.IsAr ? "Switch to VR" : "Switch to AR") : "AR unavailable";
    }
}
