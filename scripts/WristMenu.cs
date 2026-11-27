using Godot;

namespace Vrqf;

// A settings panel anchored above the left controller, rendered via a
// SubViewport onto a quad. The right controller aims a ray at the panel;
// pulling the trigger injects a click into the SubViewport. All edits go
// through the FractalController (and Main
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

    private Label? _fracVal, _matVal, _palVal, _colorVal, _detailVal, _shapeVal, _speedVal, _zoomVal, _qualVal;
    private Label? _morphTgtVal, _morphVal, _roughVal, _metalVal, _emissionVal, _hueCyclesVal, _hueOffsetVal;
    private Button? _autoMorphBtn, _arBtn;
    private Button? _roughMinus, _roughPlus, _metalMinus, _metalPlus;

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

        var tabs = new TabContainer { Name = "WristTabs" };
        margin.AddChild(tabs);

        var fractalTab = AddTab(tabs, "Fractal");
        _fracVal = SelectorRow(fractalTab, "Fractal", d => _fc?.CycleFractal(d));
        _detailVal = StepRow(fractalTab, "Detail", d => _fc?.AdjustDetail(d), 1f);
        _shapeVal = StepRow(fractalTab, "Shape", d => _fc?.AdjustShape(d), 0.3f);
        _speedVal = StepRow(fractalTab, "Speed", d => _fc?.AdjustSpeed(d), 0.05f);
        _zoomVal = StepRow(fractalTab, "Zoom", d => _fc?.AdjustZoom(d), 0.1f);
        _qualVal = StepRow(fractalTab, "Quality", d => _fc?.AdjustQuality(d), 8f);

        var rnd = new Button { Text = "Randomize", CustomMinimumSize = new Vector2(0, 60) };
        rnd.AddThemeFontSizeOverride("font_size", 24);
        rnd.Pressed += () => _fc?.Randomize();
        fractalTab.AddChild(rnd);

        var morphTab = AddTab(tabs, "Morph");
        _autoMorphBtn = new Button { Text = "Auto morph: On", CustomMinimumSize = new Vector2(0, 56) };
        _autoMorphBtn.AddThemeFontSizeOverride("font_size", 22);
        _autoMorphBtn.Pressed += () => _fc?.ToggleAutoMorph();
        morphTab.AddChild(_autoMorphBtn);
        _morphTgtVal = SelectorRow(morphTab, "Target", d => _fc?.CycleMorphTarget(d));
        _morphVal = StepRow(morphTab, "Morph", d => _fc?.AdjustMorph(d), 0.1f);

        _arBtn = new Button { Text = "AR / VR", CustomMinimumSize = new Vector2(0, 60) };
        _arBtn.AddThemeFontSizeOverride("font_size", 24);
        _arBtn.Pressed += () => _main?.ToggleAr();
        morphTab.AddChild(_arBtn);

        var materialTab = AddTab(tabs, "Material");
        _matVal = SelectorRow(materialTab, "Material", d => _fc?.CycleMaterial(d));
        _colorVal = SelectorRow(materialTab, "Colour", d => _fc?.CycleColorMode(d));
        _palVal = SelectorRow(materialTab, "Palette", d => _fc?.CyclePalette(d));
        _hueCyclesVal = StepRow(materialTab, "Hue cycles", d => _fc?.AdjustRadialHueCycles(d), 0.1f);
        _hueOffsetVal = StepRow(materialTab, "Hue offset", d => _fc?.AdjustRadialHueOffset(d), 0.05f);
        var rough = StepRowControls(materialTab, "Roughness", d => _fc?.AdjustMaterialRoughness(d), 0.1f);
        _roughVal = rough.Value;
        _roughMinus = rough.Minus;
        _roughPlus = rough.Plus;
        var metal = StepRowControls(materialTab, "Metalness", d => _fc?.AdjustMaterialMetallic(d), 0.1f);
        _metalVal = metal.Value;
        _metalMinus = metal.Minus;
        _metalPlus = metal.Plus;
        _emissionVal = StepRow(materialTab, "Emission", d => _fc?.AdjustMaterialEmission(d), 0.1f);
    }

    private static VBoxContainer AddTab(TabContainer tabs, string name)
    {
        var page = new VBoxContainer { Name = name };
        page.AddThemeConstantOverride("separation", 8);
        tabs.AddChild(page);
        return page;
    }

    private Label SelectorRow(VBoxContainer parent, string name, System.Action<int> cycle)
    {
        var (row, value) = RowBase(name);
        row.AddChild(StepButton("<", () => cycle(-1), 52));
        row.AddChild(value);
        row.AddChild(StepButton(">", () => cycle(1), 52));
        parent.AddChild(row);
        return value;
    }

    private Label StepRow(VBoxContainer parent, string name, System.Action<float> adjust, float step) =>
        StepRowControls(parent, name, adjust, step).Value;

    private (Label Value, Button Minus, Button Plus) StepRowControls(
        VBoxContainer parent, string name, System.Action<float> adjust, float step)
    {
        var (row, value) = RowBase(name);
        var minus = StepButton("-", () => adjust(-step));
        minus.TooltipText = $"Decrease {name.ToLowerInvariant()}";
        row.AddChild(minus);
        row.AddChild(value);
        var plus = StepButton("+", () => adjust(step));
        plus.TooltipText = $"Increase {name.ToLowerInvariant()}";
        row.AddChild(plus);
        parent.AddChild(row);
        return (value, minus, plus);
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
        value.AddThemeFontSizeOverride("font_size", 18);
        value.AddThemeColorOverride("font_color", new Color(0.95f, 0.85f, 0.4f));
        return (row, value);
    }

    private static Button StepButton(string text, System.Action onPressed, float width = 64)
    {
        var b = new Button { Text = text, CustomMinimumSize = new Vector2(width, 56) };
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
        if (_colorVal is not null) _colorVal.Text = _fc.ColorModeName;
        if (_palVal is not null) _palVal.Text = _fc.PaletteName;
        if (_hueCyclesVal is not null) _hueCyclesVal.Text = _fc.RadialHueCyclesValue.ToString("0.00");
        if (_hueOffsetVal is not null) _hueOffsetVal.Text = _fc.RadialHueOffsetValue.ToString("0.00");
        if (_detailVal is not null) _detailVal.Text = _fc.DetailText;
        if (_shapeVal is not null) _shapeVal.Text = _fc.ShapeText;
        if (_speedVal is not null) _speedVal.Text = _fc.SpeedText;
        if (_zoomVal is not null) _zoomVal.Text = _fc.ZoomText;
        if (_qualVal is not null) _qualVal.Text = _fc.QualityText;
        if (_morphTgtVal is not null) _morphTgtVal.Text = _fc.MorphTargetName;
        if (_morphVal is not null) _morphVal.Text = _fc.MorphText;
        if (_autoMorphBtn is not null) _autoMorphBtn.Text = _fc.AutoMorph ? "Auto morph: On" : "Auto morph: Off";
        if (_roughVal is not null) _roughVal.Text = _fc.MaterialRoughnessValue.ToString("0.00");
        if (_metalVal is not null) _metalVal.Text = _fc.MaterialMetallicValue.ToString("0.00");
        if (_emissionVal is not null) _emissionVal.Text = _fc.MaterialEmissionValue.ToString("0.00");
        bool surface = _fc.MaterialSupportsSurfaceParams;
        if (_roughMinus is not null) _roughMinus.Disabled = !surface;
        if (_roughPlus is not null) _roughPlus.Disabled = !surface;
        if (_metalMinus is not null) _metalMinus.Disabled = !surface;
        if (_metalPlus is not null) _metalPlus.Disabled = !surface;
        if (_arBtn is not null && _main is not null)
            _arBtn.Text = _main.ArAvailable ? (_main.IsAr ? "Switch to VR" : "Switch to AR") : "AR unavailable";
    }
}
