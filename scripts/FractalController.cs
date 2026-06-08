using Godot;

namespace Vrqf;

// Cycles the fractal, material look, and colour palette of the Cube's shader.
//   Fractal:  VR A/X = next, B/Y = prev          | keyboard F / G
//   Material: VR right thumbstick-click = next    | keyboard T
//   Palette:  VR left thumbstick-click = next     | keyboard P
public partial class FractalController : MeshInstance3D
{
    [Export] public NodePath LeftControllerPath { get; set; } = "../XROrigin3D/LeftController";
    [Export] public NodePath RightControllerPath { get; set; } = "../XROrigin3D/RightController";

    public static readonly string[] FractalNames =
    {
        "Quaternion Julia",
        "Mandelbulb",
        "Quaternion Mandelbrot",
        "Menger Sponge",
        "Sierpinski Tetrahedron",
        "Burning Ship",
    };

    public static readonly string[] MaterialNames =
    {
        "Glow", "Plastic", "Metal", "Glass", "Matcap Chrome", "Matcap Gold", "Matcap Pearl",
    };

    private static readonly string[] PalettePaths =
    {
        "res://textures/palette_fire.tres",
        "res://textures/palette_ice.tres",
        "res://textures/palette_rainbow.tres",
        "res://textures/palette_viridis.tres",
    };

    private static readonly string[] PaletteNames = { "Fire", "Ice", "Rainbow", "Viridis" };

    private ShaderMaterial? _material;
    private readonly Texture2D[] _palettes = new Texture2D[PalettePaths.Length];
    private int _fractal;
    private int _materialMode;
    private int _palette;

    public override void _Ready()
    {
        _material = GetSurfaceOverrideMaterial(0) as ShaderMaterial
            ?? GetActiveMaterial(0) as ShaderMaterial;

        if (_material is null)
        {
            GD.PushWarning("FractalController: Cube has no ShaderMaterial — switching disabled.");
            return;
        }

        _fractal = ReadInt("fractal_type");
        _materialMode = ReadInt("material_mode");

        for (int i = 0; i < PalettePaths.Length; i++)
            _palettes[i] = GD.Load<Texture2D>(PalettePaths[i]);

        ConnectController(LeftControllerPath, isLeft: true);
        ConnectController(RightControllerPath, isLeft: false);

        GD.Print($"Fractal: {FractalNames[_fractal]} | Material: {MaterialNames[_materialMode]} | Palette: {PaletteNames[_palette]}");
        GD.Print("Switch — Fractal: A/X / B/Y (F/G)  Material: R-stick click (T)  Palette: L-stick click (P)");
    }

    private int ReadInt(string param)
    {
        var value = _material!.GetShaderParameter(param);
        return value.VariantType == Variant.Type.Nil ? 0 : value.As<int>();
    }

    private void ConnectController(NodePath path, bool isLeft)
    {
        var controller = GetNodeOrNull<XRController3D>(path);
        if (controller is not null)
            controller.ButtonPressed += name => OnButtonPressed(name, isLeft);
    }

    private void OnButtonPressed(string name, bool isLeft)
    {
        switch (name)
        {
            case "ax_button": CycleFractal(1); break;
            case "by_button": CycleFractal(-1); break;
            case "primary_click" when isLeft: CyclePalette(1); break;
            case "primary_click": CycleMaterial(1); break;
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is not InputEventKey { Pressed: true, Echo: false } key) return;

        switch (key.Keycode)
        {
            case Key.F: CycleFractal(1); break;
            case Key.G: CycleFractal(-1); break;
            case Key.T: CycleMaterial(1); break;
            case Key.P: CyclePalette(1); break;
        }
    }

    private void CycleFractal(int direction)
    {
        if (_material is null) return;
        _fractal = Wrap(_fractal + direction, FractalNames.Length);
        _material.SetShaderParameter("fractal_type", _fractal);
        GD.Print($"Fractal {_fractal}: {FractalNames[_fractal]}");
    }

    private void CycleMaterial(int direction)
    {
        if (_material is null) return;
        _materialMode = Wrap(_materialMode + direction, MaterialNames.Length);
        _material.SetShaderParameter("material_mode", _materialMode);
        GD.Print($"Material {_materialMode}: {MaterialNames[_materialMode]}");
    }

    private void CyclePalette(int direction)
    {
        if (_material is null) return;
        _palette = Wrap(_palette + direction, _palettes.Length);
        _material.SetShaderParameter("palette_tex", _palettes[_palette]);
        GD.Print($"Palette {_palette}: {PaletteNames[_palette]}");
    }

    private static int Wrap(int value, int count) => (value % count + count) % count;
}
