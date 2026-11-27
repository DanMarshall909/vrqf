using Godot;
using System;
using System.Collections.Generic;

namespace Vrqf;

// Desktop controls for the same settings exposed by the VR wrist menu.
public partial class ExplorerPanel : PanelContainer
{
    private FractalController? _fractal;
    private Label? _fractalName, _targetName, _materialName, _paletteName, _colorModeName;
    private Button? _autoMorphButton;
    private HSlider? _roughnessSlider, _metallicSlider;
    private readonly List<(HSlider Slider, Label Value, Func<float> Read, string Format)> _sliders = new();

    public override void _Ready()
    {
        _fractal = GetTree().GetFirstNodeInGroup("fractal_controller") as FractalController;
        Visible = !(XRServer.FindInterface("OpenXR")?.IsInitialized() ?? false);
        BuildControls();
        Refresh();
    }

    private void BuildControls()
    {
        var style = new StyleBoxFlat
        {
            BgColor = new Color(0.05f, 0.06f, 0.09f, 0.9f),
            BorderColor = new Color(0.4f, 0.6f, 1f, 0.9f),
            ContentMarginLeft = 10,
            ContentMarginRight = 10,
            ContentMarginTop = 10,
            ContentMarginBottom = 10,
        };
        style.SetBorderWidthAll(1);
        AddThemeStyleboxOverride("panel", style);

        var tabs = new TabContainer { Name = "Tabs" };
        tabs.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(tabs);

        var materialPage = AddPage(tabs, "Material");
        _materialName = AddSelector(materialPage, "Style", "Previous material", "Next material",
            d => _fractal?.CycleMaterial(d));
        _colorModeName = AddSelector(materialPage, "Colour", "Previous colour source", "Next colour source",
            d => _fractal?.CycleColorMode(d));
        _paletteName = AddSelector(materialPage, "Palette", "Previous palette", "Next palette",
            d => _fractal?.CyclePalette(d));
        AddSlider(materialPage, "Hue cycles", 0.25, 4, 0.01,
            () => _fractal?.RadialHueCyclesValue ?? 1,
            d => _fractal?.AdjustRadialHueCycles(d));
        AddSlider(materialPage, "Hue offset", 0, 1, 0.01,
            () => _fractal?.RadialHueOffsetValue ?? 0,
            d => _fractal?.AdjustRadialHueOffset(d));
        _roughnessSlider = AddSlider(materialPage, "Roughness", 0, 1, 0.01,
            () => _fractal?.MaterialRoughnessValue ?? 0,
            d => _fractal?.AdjustMaterialRoughness(d));
        _metallicSlider = AddSlider(materialPage, "Metalness", 0, 1, 0.01,
            () => _fractal?.MaterialMetallicValue ?? 0,
            d => _fractal?.AdjustMaterialMetallic(d));
        AddSlider(materialPage, "Emission", 0, 2, 0.01,
            () => _fractal?.MaterialEmissionValue ?? 0,
            d => _fractal?.AdjustMaterialEmission(d));

        var fractalPage = AddPage(tabs, "Fractal");
        _fractalName = AddSelector(fractalPage, "Type", "Previous fractal", "Next fractal",
            d => _fractal?.CycleFractal(d));
        _targetName = AddSelector(fractalPage, "Target", "Previous morph target", "Next morph target",
            d => _fractal?.CycleMorphTarget(d));
        _autoMorphButton = new Button { Text = "Auto morph: On", TooltipText = "Toggle automatic morphing" };
        _autoMorphButton.Pressed += () => _fractal?.ToggleAutoMorph();
        fractalPage.AddChild(_autoMorphButton);
        AddSlider(fractalPage, "Morph amount", 0, 1, 0.01,
            () => _fractal?.MorphValue ?? 0,
            d => _fractal?.AdjustMorph(d));
        AddSlider(fractalPage, "Detail", 2, 64, 1,
            () => _fractal?.DetailValue ?? 0,
            d => _fractal?.AdjustDetail(d), "0");
        AddSlider(fractalPage, "Shape", -6.28, 6.28, 0.01,
            () => _fractal?.ShapeValue ?? 0,
            d => _fractal?.AdjustShape(d));
        AddSlider(fractalPage, "Animation speed", 0, 2, 0.01,
            () => _fractal?.SpeedValue ?? 0,
            d => _fractal?.AdjustSpeed(d));
        AddSlider(fractalPage, "Size", 0.3, 3, 0.01,
            () => _fractal?.ZoomValue ?? 0,
            d => _fractal?.AdjustZoom(d));
        AddSlider(fractalPage, "Quality", 16, 256, 1,
            () => _fractal?.QualityValue ?? 0,
            d => _fractal?.AdjustQuality(d), "0");
    }

    private static VBoxContainer AddPage(TabContainer tabs, string title)
    {
        var scroll = new ScrollContainer
        {
            Name = title,
            HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
        };
        tabs.AddChild(scroll);
        var content = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        content.AddThemeConstantOverride("separation", 8);
        scroll.AddChild(content);
        return content;
    }

    private static Label AddSelector(VBoxContainer parent, string title, string previousHint,
        string nextHint, Action<int> cycle)
    {
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", 4);
        parent.AddChild(row);
        row.AddChild(new Label { Text = title, CustomMinimumSize = new Vector2(55, 0) });
        var previous = new Button { Text = "<", TooltipText = previousHint, CustomMinimumSize = new Vector2(34, 32) };
        previous.Pressed += () => cycle(-1);
        row.AddChild(previous);
        var value = new Label { Text = "-", SizeFlagsHorizontal = SizeFlags.ExpandFill,
            HorizontalAlignment = HorizontalAlignment.Center };
        row.AddChild(value);
        var next = new Button { Text = ">", TooltipText = nextHint, CustomMinimumSize = new Vector2(34, 32) };
        next.Pressed += () => cycle(1);
        row.AddChild(next);
        return value;
    }

    private HSlider AddSlider(VBoxContainer parent, string title, double min, double max, double step,
        Func<float> read, Action<float> adjust, string format = "0.00")
    {
        var block = new VBoxContainer
        {
            CustomMinimumSize = new Vector2(260, 0),
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
        };
        block.AddThemeConstantOverride("separation", 2);
        parent.AddChild(block);
        var heading = new HBoxContainer();
        block.AddChild(heading);
        heading.AddChild(new Label { Text = title, SizeFlagsHorizontal = SizeFlags.ExpandFill });
        var value = new Label { Text = "-", CustomMinimumSize = new Vector2(48, 0),
            HorizontalAlignment = HorizontalAlignment.Right };
        heading.AddChild(value);
        var slider = new HSlider { MinValue = min, MaxValue = max, Step = step,
            TooltipText = title, SizeFlagsHorizontal = SizeFlags.ExpandFill };
        slider.ValueChanged += newValue => { adjust((float)newValue - read()); Refresh(); };
        block.AddChild(slider);
        _sliders.Add((slider, value, read, format));
        return slider;
    }

    public override void _Process(double _delta) => Refresh();

    private void Refresh()
    {
        if (_fractal is null) return;
        if (_fractalName is not null) _fractalName.Text = _fractal.FractalName;
        if (_targetName is not null) _targetName.Text = _fractal.MorphTargetName;
        if (_materialName is not null) _materialName.Text = _fractal.MaterialName;
        if (_colorModeName is not null) _colorModeName.Text = _fractal.ColorModeName;
        if (_paletteName is not null) _paletteName.Text = _fractal.PaletteName;
        if (_autoMorphButton is not null)
            _autoMorphButton.Text = _fractal.AutoMorph ? "Auto morph: On" : "Auto morph: Off";
        if (_roughnessSlider is not null) _roughnessSlider.Editable = _fractal.MaterialSupportsSurfaceParams;
        if (_metallicSlider is not null) _metallicSlider.Editable = _fractal.MaterialSupportsSurfaceParams;
        foreach (var (slider, value, read, format) in _sliders)
        {
            float current = read();
            slider.SetValueNoSignal(current);
            value.Text = current.ToString(format);
        }
    }
}
