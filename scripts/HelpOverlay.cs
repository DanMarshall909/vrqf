using Godot;

namespace Vrqf;

// A controls cheat-sheet overlay, hidden by default. Toggle with `?` on the
// keyboard or the controller menu button (wired in Main). Renders on the
// desktop window and as a head-locked overlay in the headset.
public partial class HelpOverlay : CanvasLayer
{
    private const string HelpText =
        "[b]CONTROLS[/b]\n\n" +
        "Fractal        A/X next · B/Y prev        (F / G)\n" +
        "Material       right stick-click          (T)\n" +
        "Palette        left stick-click           (P)\n" +
        "Colour mode    wrist menu                 (C)\n" +
        "Live param     grip  R next · L prev      (] / [)\n" +
        "Scrub param    triggers  R up · L down    (= / -)\n" +
        "Wrist menu     aim right controller; trigger to click\n" +
        "Morph target   wrist menu                 (M)\n" +
        "Morph amount   wrist menu · pauses auto   (, / .)\n" +
        "Auto morph     wrist-menu button          (Space)\n" +
        "Pause anim     panel / wrist button       (K)\n" +
        "Randomize      wrist-menu button          (R)\n" +
        "AR / VR        wrist-menu button          (V)\n" +
        "Help           menu button                (?)";

    private Control? _root;

    public override void _Ready()
    {
        Layer = 20;

        _root = new CenterContainer();
        _root.SetAnchorsPreset(Control.LayoutPreset.FullRect);
        _root.MouseFilter = Control.MouseFilterEnum.Ignore;
        AddChild(_root);

        var panel = new PanelContainer();
        var style = new StyleBoxFlat
        {
            BgColor = new Color(0.05f, 0.06f, 0.09f, 0.94f),
            BorderColor = new Color(0.4f, 0.6f, 1f, 0.9f),
            ContentMarginLeft = 28,
            ContentMarginRight = 28,
            ContentMarginTop = 22,
            ContentMarginBottom = 22,
            CornerRadiusTopLeft = 10,
            CornerRadiusTopRight = 10,
            CornerRadiusBottomLeft = 10,
            CornerRadiusBottomRight = 10,
        };
        style.SetBorderWidthAll(2);
        panel.AddThemeStyleboxOverride("panel", style);
        _root.AddChild(panel);

        var label = new RichTextLabel
        {
            BbcodeEnabled = true,
            FitContent = true,
            ScrollActive = false,
            AutowrapMode = TextServer.AutowrapMode.Off,
            Text = HelpText,
        };
        label.AddThemeFontSizeOverride("normal_font_size", 22);
        label.AddThemeFontSizeOverride("bold_font_size", 26);
        panel.AddChild(label);

        _root.Visible = false;
    }

    public void Toggle()
    {
        if (_root is not null) _root.Visible = !_root.Visible;
    }
}
