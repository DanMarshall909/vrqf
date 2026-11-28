using Godot;

namespace Vrqf;

// Desktop controls for the same unified settings exposed by the VR wrist menu.
public partial class ExplorerPanel : PanelContainer
{
    private FractalController? _fractal;
    private FractalUiView? _view;

    public override void _Ready()
    {
        _fractal = GetTree().GetFirstNodeInGroup("fractal_controller") as FractalController;
        var main = GetTree().CurrentScene as Main;
        Visible = !(XRServer.FindInterface("OpenXR")?.IsInitialized() ?? false);

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

        if (_fractal is not null)
        {
            _view = FractalUiBuilder.Build(tabs, _fractal, main, UiMode.Desktop);
            _fractal.StateChanged += OnStateChanged;
        }
    }

    public override void _ExitTree()
    {
        if (_fractal is not null)
            _fractal.StateChanged -= OnStateChanged;
    }

    private void OnStateChanged()
    {
        _view?.RebuildDynamicTabIfNeeded();
        _view?.Refresh();
    }
}
