using Godot;
using System;
using System.Collections.Generic;

namespace Vrqf;

public enum UiMode
{
    Desktop,
    VrWrist,
}

public interface IUiItem { }

public sealed record SelectorItem(
    string Label,
    string? VrLabel,
    string PrevTooltip,
    string NextTooltip,
    Func<string> ReadText,
    Action<int> Cycle) : IUiItem;

public sealed record RangeItem(
    string Label,
    string? VrLabel,
    float Min,
    float Max,
    float DesktopStep,
    float VrStep,
    string Format,
    Func<float> Read,
    Action<float> Adjust,
    Func<bool>? IsEnabled = null) : IUiItem;

public sealed record ActionItem(
    string TooltipText,
    Func<string> ReadText,
    Action OnPressed) : IUiItem;

public readonly record struct ButtonSpec(
    string TooltipText,
    Func<string> ReadText,
    Action OnPressed,
    bool ToggleMode = false,
    Func<bool>? IsPressed = null);

public sealed record ButtonRowItem(ButtonSpec[] Buttons) : IUiItem;

public sealed record HeaderItem(Func<string> ReadText) : IUiItem;

public sealed class FractalUiView
{
    private readonly FractalController _fc;
    private readonly UiMode _mode;
    private readonly VBoxContainer _paramsPage;
    private readonly List<(Action Update, bool IsDynamic)> _updaters = new();
    private int _builtFractalType = -1;
    private bool _builtEditingTarget;

    public TabContainer Tabs { get; }

    internal FractalUiView(TabContainer tabs, FractalController fc, UiMode mode, VBoxContainer paramsPage)
    {
        Tabs = tabs;
        _fc = fc;
        _mode = mode;
        _paramsPage = paramsPage;
    }

    internal void RegisterUpdater(Action update, bool isDynamic) => _updaters.Add((update, isDynamic));

    public void RebuildDynamicTabIfNeeded()
    {
        int editedFractal = _fc.EditedFormulaFractalIndex;
        bool editingTarget = _fc.EditingMorphTarget;
        if (_builtFractalType == editedFractal && _builtEditingTarget == editingTarget) return;
        _builtFractalType = editedFractal;
        _builtEditingTarget = editingTarget;

        _updaters.RemoveAll(u => u.IsDynamic);
        foreach (Node child in _paramsPage.GetChildren())
        {
            _paramsPage.RemoveChild(child);
            child.QueueFree();
        }

        foreach (var item in FractalUiBuilder.BuildParamsItems(_fc))
            FractalUiBuilder.AddItem(_paramsPage, item, _mode, this, isDynamic: true);
    }

    public void Refresh()
    {
        foreach (var (update, _) in _updaters)
            update();
    }
}

public static class FractalUiBuilder
{
    public static FractalUiView Build(TabContainer tabs, FractalController fc, Main? main, UiMode mode)
    {
        var materialPage = AddPage(tabs, "Material", mode);
        var fractalPage = AddPage(tabs, "Fractal", mode);
        var paramsPage = AddPage(tabs, "Params", mode);
        var morphPage = AddPage(tabs, "Morph", mode);

        var view = new FractalUiView(tabs, fc, mode, paramsPage);

        foreach (var item in BuildMaterialItems(fc))
            AddItem(materialPage, item, mode, view, isDynamic: false);

        foreach (var item in BuildFractalItems(fc))
            AddItem(fractalPage, item, mode, view, isDynamic: false);

        foreach (var item in BuildMorphItems(fc, main, includeArToggle: mode == UiMode.VrWrist))
            AddItem(morphPage, item, mode, view, isDynamic: false);

        view.RebuildDynamicTabIfNeeded();
        view.Refresh();
        return view;
    }

    private static ButtonRowItem BuildPlaybackRow(FractalController fc, bool useAutoMorphLabel) => new(new[]
    {
        useAutoMorphLabel
            ? new ButtonSpec("Toggle automatic morphing", () => fc.AutoMorph ? "Auto morph: On" : "Auto morph: Off", () => fc.ToggleAutoMorph())
            : new ButtonSpec("Pause or resume automatic morphing", () => fc.AutoMorph ? "Pause morph" : "Resume morph", () => fc.ToggleAutoMorph()),
        new ButtonSpec("Pause or resume fractal shape animation", () => fc.AnimationPaused ? "Resume anim" : "Pause anim", () => fc.ToggleAnimationPaused()),
    });

    private static IEnumerable<IUiItem> BuildMaterialItems(FractalController fc)
    {
        yield return BuildPlaybackRow(fc, useAutoMorphLabel: false);
        yield return new SelectorItem("Style", "Material", "Previous material", "Next material",
            () => fc.MaterialName, d => fc.CycleMaterial(d));
        yield return new SelectorItem("Colour", "Colour", "Previous colour source", "Next colour source",
            () => fc.ColorModeName, d => fc.CycleColorMode(d));
        yield return new SelectorItem("Palette", "Palette", "Previous palette", "Next palette",
            () => fc.PaletteName, d => fc.CyclePalette(d));
        yield return new RangeItem("Hue cycles", null, 0.25f, 8f, 0.01f, 0.1f, "0.00",
            () => fc.RadialHueCyclesValue, d => fc.AdjustRadialHueCycles(d));
        yield return new RangeItem("Hue offset", null, 0f, 1f, 0.01f, 0.05f, "0.00",
            () => fc.RadialHueOffsetValue, d => fc.AdjustRadialHueOffset(d));
        yield return new RangeItem("Roughness", null, 0f, 1f, 0.01f, 0.1f, "0.00",
            () => fc.MaterialRoughnessValue, d => fc.AdjustMaterialRoughness(d),
            () => fc.MaterialSupportsSurfaceParams);
        yield return new RangeItem("Metalness", null, 0f, 1f, 0.01f, 0.1f, "0.00",
            () => fc.MaterialMetallicValue, d => fc.AdjustMaterialMetallic(d),
            () => fc.MaterialSupportsSurfaceParams);
        yield return new RangeItem("Emission", null, 0f, 2f, 0.01f, 0.1f, "0.00",
            () => fc.MaterialEmissionValue, d => fc.AdjustMaterialEmission(d));
        yield return new RangeItem("AO", null, 0f, 1f, 0.01f, 0.1f, "0.00",
            () => fc.AoStrengthValue, d => fc.AdjustAoStrength(d));
        yield return new RangeItem("Shadows", null, 0f, 1f, 0.01f, 0.1f, "0.00",
            () => fc.ShadowStrengthValue, d => fc.AdjustShadowStrength(d));
    }

    private static IEnumerable<IUiItem> BuildFractalItems(FractalController fc)
    {
        yield return BuildPlaybackRow(fc, useAutoMorphLabel: false);
        yield return new SelectorItem("Type", "Fractal", "Previous fractal", "Next fractal",
            () => fc.FractalName, d => fc.CycleFractal(d));
        yield return new RangeItem("Detail", null, 2f, 64f, 1f, 1f, "0",
            () => fc.DetailValue, d => fc.AdjustDetail(d));
        yield return new RangeItem("Shape", null, -6.28f, 6.28f, 0.01f, 0.3f, "0.00",
            () => fc.ShapeValue, d => fc.AdjustShape(d));
        yield return new RangeItem("Animation speed", "Speed", 0f, 2f, 0.01f, 0.05f, "0.00",
            () => fc.SpeedValue, d => fc.AdjustSpeed(d));
        yield return new RangeItem("Size", "Zoom", 0.3f, 3f, 0.01f, 0.1f, "0.00",
            () => fc.ZoomValue, d => fc.AdjustZoom(d));
        yield return new RangeItem("Quality", null, 16f, 256f, 1f, 8f, "0",
            () => fc.QualityValue, d => fc.AdjustQuality(d));
        yield return new ActionItem("Randomize fractal and material settings", () => "Randomize",
            () => fc.Randomize());
    }

    internal static IEnumerable<IUiItem> BuildParamsItems(FractalController fc)
    {
        yield return BuildPlaybackRow(fc, useAutoMorphLabel: false);
        yield return new ButtonRowItem(new[]
        {
            new ButtonSpec("Edit source fractal (A) parameters", () => "A · Source",
                () => fc.EditingMorphTarget = false, ToggleMode: true, IsPressed: () => !fc.EditingMorphTarget),
            new ButtonSpec("Edit target fractal (B) parameters", () => "B · Target",
                () => fc.EditingMorphTarget = true, ToggleMode: true, IsPressed: () => fc.EditingMorphTarget),
        });
        yield return new HeaderItem(() => $"{(fc.EditingMorphTarget ? "B" : "A")}: {fc.EditedFormulaFractalName}");

        var specs = fc.EditedFormulaParams;
        for (int i = 0; i < specs.Length; i++)
        {
            int idx = i;
            var spec = specs[i];
            yield return new RangeItem(spec.Label, null, spec.Min, spec.Max,
                spec.DesktopStep, spec.VrStep, spec.Format,
                () => fc.GetEditedFormulaParam(idx), d => fc.AdjustEditedFormulaParam(idx, d));
        }
        yield return new ActionItem("Reset current formula parameters to defaults", () => "Reset formula",
            () => fc.ResetEditedFormulaParams());
    }

    private static IEnumerable<IUiItem> BuildMorphItems(FractalController fc, Main? main, bool includeArToggle)
    {
        yield return BuildPlaybackRow(fc, useAutoMorphLabel: true);
        yield return new SelectorItem("Target", "Target", "Previous morph target", "Next morph target",
            () => fc.MorphTargetName, d => fc.CycleMorphTarget(d));
        yield return new RangeItem("Morph amount", "Morph", 0f, 1f, 0.01f, 0.1f, "0.00",
            () => fc.MorphValue, d => fc.AdjustMorph(d));
        yield return new RangeItem("Hold (s)", null, 0f, 10f, 0.1f, 0.5f, "0.0",
            () => fc.MorphHoldSeconds, d => fc.AdjustMorphHoldSeconds(d));
        yield return new RangeItem("Transition (s)", null, 0.2f, 10f, 0.1f, 0.5f, "0.0",
            () => fc.MorphTransitionSeconds, d => fc.AdjustMorphTransitionSeconds(d));
        if (includeArToggle)
        {
            yield return new ActionItem("Toggle AR passthrough / VR sky",
                () => main is null ? "AR / VR" : (main.ArAvailable ? (main.IsAr ? "Switch to VR" : "Switch to AR") : "AR unavailable"),
                () => main?.ToggleAr());
        }
    }

    private static VBoxContainer AddPage(TabContainer tabs, string title, UiMode mode)
    {
        if (mode == UiMode.Desktop)
        {
            var scroll = new ScrollContainer
            {
                Name = title,
                HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
            };
            tabs.AddChild(scroll);
            var content = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
            content.AddThemeConstantOverride("separation", 8);
            scroll.AddChild(content);
            return content;
        }

        var page = new VBoxContainer { Name = title };
        page.AddThemeConstantOverride("separation", 4);
        tabs.AddChild(page);
        return page;
    }

    internal static void AddItem(VBoxContainer parent, IUiItem item, UiMode mode, FractalUiView view, bool isDynamic)
    {
        switch (item)
        {
            case SelectorItem sel:
                AddSelector(parent, sel, mode, view, isDynamic);
                break;
            case RangeItem range:
                if (mode == UiMode.Desktop)
                    AddDesktopSlider(parent, range, view, isDynamic);
                else
                    AddVrStepper(parent, range, view, isDynamic);
                break;
            case ActionItem act:
                AddActionButton(parent, act, mode, view, isDynamic);
                break;
            case ButtonRowItem row:
                AddButtonRow(parent, row, mode, view, isDynamic);
                break;
            case HeaderItem hdr:
                AddHeader(parent, hdr, mode, view, isDynamic);
                break;
        }
    }

    private static void AddSelector(VBoxContainer parent, SelectorItem sel, UiMode mode, FractalUiView view, bool isDynamic)
    {
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", mode == UiMode.Desktop ? 4 : 6);
        parent.AddChild(row);

        string titleText = mode == UiMode.Desktop ? sel.Label : (sel.VrLabel ?? sel.Label);
        var title = new Label
        {
            Text = titleText,
            CustomMinimumSize = new Vector2(mode == UiMode.Desktop ? 55 : 74, 0),
        };
        if (mode == UiMode.VrWrist)
            title.AddThemeFontSizeOverride("font_size", 17);
        row.AddChild(title);

        var prev = MakeCycleButton("<", sel.PrevTooltip, mode, () => sel.Cycle(-1));
        row.AddChild(prev);

        var value = new Label
        {
            Text = "-",
            SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        if (mode == UiMode.VrWrist)
        {
            value.AddThemeFontSizeOverride("font_size", 15);
            value.AddThemeColorOverride("font_color", new Color(0.95f, 0.85f, 0.4f));
        }
        row.AddChild(value);

        var next = MakeCycleButton(">", sel.NextTooltip, mode, () => sel.Cycle(1));
        row.AddChild(next);

        view.RegisterUpdater(() => value.Text = sel.ReadText(), isDynamic);
    }

    private static void AddDesktopSlider(VBoxContainer parent, RangeItem range, FractalUiView view, bool isDynamic)
    {
        var block = new VBoxContainer
        {
            CustomMinimumSize = new Vector2(260, 0),
            SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
        };
        block.AddThemeConstantOverride("separation", 2);
        parent.AddChild(block);

        var heading = new HBoxContainer();
        block.AddChild(heading);
        heading.AddChild(new Label { Text = range.Label, SizeFlagsHorizontal = Control.SizeFlags.ExpandFill });
        var value = new Label
        {
            Text = "-",
            CustomMinimumSize = new Vector2(48, 0),
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        heading.AddChild(value);

        var slider = new HSlider
        {
            MinValue = range.Min,
            MaxValue = range.Max,
            Step = range.DesktopStep,
            TooltipText = range.Label,
            SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
        };
        slider.ValueChanged += newValue => range.Adjust((float)newValue - range.Read());
        block.AddChild(slider);

        view.RegisterUpdater(() =>
        {
            float current = range.Read();
            slider.SetValueNoSignal(current);
            value.Text = current.ToString(range.Format);
            if (range.IsEnabled is not null)
                slider.Editable = range.IsEnabled();
        }, isDynamic);
    }

    private static void AddVrStepper(VBoxContainer parent, RangeItem range, FractalUiView view, bool isDynamic)
    {
        string labelText = range.VrLabel ?? range.Label;
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", 6);
        parent.AddChild(row);

        var label = new Label
        {
            Text = labelText,
            SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
        };
        label.AddThemeFontSizeOverride("font_size", 17);
        row.AddChild(label);

        var minus = MakeStepButton("-", $"Decrease {labelText.ToLowerInvariant()}", () => range.Adjust(-range.VrStep));
        row.AddChild(minus);

        var value = new Label
        {
            Text = "-",
            CustomMinimumSize = new Vector2(74, 0),
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        value.AddThemeFontSizeOverride("font_size", 15);
        value.AddThemeColorOverride("font_color", new Color(0.95f, 0.85f, 0.4f));
        row.AddChild(value);

        var plus = MakeStepButton("+", $"Increase {labelText.ToLowerInvariant()}", () => range.Adjust(range.VrStep));
        row.AddChild(plus);

        view.RegisterUpdater(() =>
        {
            value.Text = range.Read().ToString(range.Format);
            if (range.IsEnabled is not null)
            {
                bool enabled = range.IsEnabled();
                minus.Disabled = !enabled;
                plus.Disabled = !enabled;
            }
        }, isDynamic);
    }

    private static void AddActionButton(VBoxContainer parent, ActionItem act, UiMode mode, FractalUiView view, bool isDynamic)
    {
        var btn = new Button
        {
            Text = act.ReadText(),
            TooltipText = act.TooltipText,
            CustomMinimumSize = new Vector2(0, mode == UiMode.Desktop ? 32 : 38),
        };
        if (mode == UiMode.VrWrist)
            btn.AddThemeFontSizeOverride("font_size", 18);
        btn.Pressed += () => act.OnPressed();
        parent.AddChild(btn);

        view.RegisterUpdater(() => btn.Text = act.ReadText(), isDynamic);
    }

    private static void AddButtonRow(VBoxContainer parent, ButtonRowItem rowItem, UiMode mode, FractalUiView view, bool isDynamic)
    {
        var row = new HBoxContainer();
        row.AddThemeConstantOverride("separation", 6);
        parent.AddChild(row);

        ButtonGroup? group = null;
        foreach (var spec in rowItem.Buttons)
        {
            if (spec.ToggleMode)
            {
                group ??= new ButtonGroup { AllowUnpress = false };
            }
        }

        foreach (var spec in rowItem.Buttons)
        {
            var s = spec;
            var btn = new Button
            {
                Text = s.ReadText(),
                TooltipText = s.TooltipText,
                ToggleMode = s.ToggleMode,
                ButtonGroup = s.ToggleMode ? group : null,
                SizeFlagsHorizontal = Control.SizeFlags.ExpandFill,
                CustomMinimumSize = new Vector2(0, mode == UiMode.Desktop ? 30 : 36),
            };
            if (mode == UiMode.VrWrist)
                btn.AddThemeFontSizeOverride("font_size", 17);
            if (s.ToggleMode && s.IsPressed is not null)
                btn.SetPressedNoSignal(s.IsPressed());
            btn.Pressed += () =>
            {
                s.OnPressed();
                if (s.ToggleMode && s.IsPressed is not null)
                    btn.SetPressedNoSignal(s.IsPressed());
            };
            row.AddChild(btn);

            view.RegisterUpdater(() =>
            {
                btn.Text = s.ReadText();
                if (s.ToggleMode && s.IsPressed is not null)
                    btn.SetPressedNoSignal(s.IsPressed());
            }, isDynamic);
        }
    }

    private static void AddHeader(VBoxContainer parent, HeaderItem hdr, UiMode mode, FractalUiView view, bool isDynamic)
    {
        var label = new Label
        {
            Text = hdr.ReadText(),
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        label.AddThemeFontSizeOverride("font_size", mode == UiMode.Desktop ? 15 : 17);
        label.AddThemeColorOverride("font_color", new Color(0.75f, 0.88f, 1f));
        parent.AddChild(label);

        view.RegisterUpdater(() => label.Text = hdr.ReadText(), isDynamic);
    }

    private static Button MakeCycleButton(string text, string tooltip, UiMode mode, Action onPressed)
    {
        var b = new Button
        {
            Text = text,
            TooltipText = tooltip,
            CustomMinimumSize = mode == UiMode.Desktop ? new Vector2(34, 32) : new Vector2(46, 40),
        };
        if (mode == UiMode.VrWrist)
            b.AddThemeFontSizeOverride("font_size", 19);
        b.Pressed += () => onPressed();
        return b;
    }

    private static Button MakeStepButton(string text, string tooltip, Action onPressed)
    {
        var b = new Button
        {
            Text = text,
            TooltipText = tooltip,
            CustomMinimumSize = new Vector2(46, 40),
        };
        b.AddThemeFontSizeOverride("font_size", 19);
        b.Pressed += () => onPressed();
        return b;
    }
}
