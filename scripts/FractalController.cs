using Godot;

namespace Vrqf;

// Drives the Cube's fractal shader from the controllers / keyboard.
//
//   Fractal:   VR A/X = next, B/Y = prev              | keyboard F / G
//   Material:  VR right stick-click                   | keyboard T
//   Palette:   VR left stick-click                    | keyboard P
//   Live param select: VR grip (R = next, L = prev)   | keyboard ] / [
//   Scrub live param:  VR right trigger = up,          | keyboard = / -
//                          left trigger = down
//
// The analog triggers continuously dial the currently-selected parameter:
// Detail (iterations), Shape (quaternion-c drift), or Speed (morph rate).
public partial class FractalController : MeshInstance3D
{
    [Export] public NodePath LeftControllerPath { get; set; } = "../XROrigin3D/LeftController";
    [Export] public NodePath RightControllerPath { get; set; } = "../XROrigin3D/RightController";

    public static readonly string[] FractalNames =
    {
        "Quaternion Julia", "Mandelbulb", "Quaternion Mandelbrot",
        "Menger Sponge", "Sierpinski Tetrahedron", "Burning Ship",
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
    private static readonly string[] LiveParamNames = { "Detail", "Shape", "Speed" };

    private const float TriggerDeadzone = 0.1f;

    private ShaderMaterial? _material;
    private XRController3D? _left;
    private XRController3D? _right;
    private readonly Texture2D[] _palettes = new Texture2D[PalettePaths.Length];

    private int _fractal;
    private int _materialMode;
    private int _palette;
    private int _liveParam;

    // Live-edited values (kept as floats so the triggers can scrub smoothly).
    private float _iterations;
    private float _morphSpeed;
    private float _shapePhase;

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
        _iterations = ReadInt("iterations");
        if (_iterations < 2f) _iterations = 8f;
        _morphSpeed = ReadFloat("morph_speed");

        for (int i = 0; i < PalettePaths.Length; i++)
            _palettes[i] = GD.Load<Texture2D>(PalettePaths[i]);

        _left = GetNodeOrNull<XRController3D>(LeftControllerPath);
        _right = GetNodeOrNull<XRController3D>(RightControllerPath);
        if (_left is not null) _left.ButtonPressed += name => OnButtonPressed(name, isLeft: true);
        if (_right is not null) _right.ButtonPressed += name => OnButtonPressed(name, isLeft: false);

        GD.Print($"Fractal: {FractalNames[_fractal]} | Material: {MaterialNames[_materialMode]} | Palette: {PaletteNames[_palette]}");
        GD.Print("Fractal A/X·B/Y (F/G) | Material R-click (T) | Palette L-click (P) | Param grip (] [) | Scrub triggers (= -)");
    }

    public override void _Process(double delta)
    {
        if (_material is null) return;

        float input = TriggerInput() + KeyboardScrub();
        input = Mathf.Clamp(input, -1f, 1f);
        if (Mathf.Abs(input) > 0.001f)
            ScrubLiveParam(input * (float)delta);
    }

    private float TriggerInput()
    {
        float up = _right?.GetFloat("trigger") ?? 0f;
        float down = _left?.GetFloat("trigger") ?? 0f;
        float net = up - down;
        return Mathf.Abs(net) < TriggerDeadzone ? 0f : net;
    }

    private static float KeyboardScrub()
    {
        float k = 0f;
        if (Input.IsKeyPressed(Key.Equal)) k += 1f;
        if (Input.IsKeyPressed(Key.Minus)) k -= 1f;
        return k;
    }

    private void ScrubLiveParam(float step)
    {
        switch (_liveParam)
        {
            case 0: // Detail / iterations
                _iterations = Mathf.Clamp(_iterations + step * 6f, 2f, 20f);
                _material!.SetShaderParameter("iterations", Mathf.RoundToInt(_iterations));
                break;
            case 1: // Shape — sweep the quaternion Julia 'c' through varied forms
                _shapePhase += step * 1.5f;
                _material!.SetShaderParameter("julia_c", ShapeFromPhase(_shapePhase));
                break;
            default: // Speed / morph rate
                _morphSpeed = Mathf.Clamp(_morphSpeed + step * 1.2f, 0f, 2f);
                _material!.SetShaderParameter("morph_speed", _morphSpeed);
                break;
        }
    }

    private static Vector4 ShapeFromPhase(float p) => new(
        0.45f * Mathf.Cos(p),
        0.45f * Mathf.Sin(p * 0.9f),
        0.45f * Mathf.Cos(p * 1.3f),
        0.45f * Mathf.Sin(p * 0.5f));

    private void OnButtonPressed(string name, bool isLeft)
    {
        switch (name)
        {
            case "ax_button": CycleFractal(1); break;
            case "by_button": CycleFractal(-1); break;
            case "primary_click" when isLeft: CyclePalette(1); break;
            case "primary_click": CycleMaterial(1); break;
            case "grip_click" when isLeft: CycleLiveParam(-1); break;
            case "grip_click": CycleLiveParam(1); break;
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
            case Key.Bracketright: CycleLiveParam(1); break;
            case Key.Bracketleft: CycleLiveParam(-1); break;
        }
    }

    private void CycleFractal(int direction)
    {
        _fractal = Wrap(_fractal + direction, FractalNames.Length);
        _material!.SetShaderParameter("fractal_type", _fractal);
        GD.Print($"Fractal {_fractal}: {FractalNames[_fractal]}");
    }

    private void CycleMaterial(int direction)
    {
        _materialMode = Wrap(_materialMode + direction, MaterialNames.Length);
        _material!.SetShaderParameter("material_mode", _materialMode);
        GD.Print($"Material {_materialMode}: {MaterialNames[_materialMode]}");
    }

    private void CyclePalette(int direction)
    {
        _palette = Wrap(_palette + direction, _palettes.Length);
        _material!.SetShaderParameter("palette_tex", _palettes[_palette]);
        GD.Print($"Palette {_palette}: {PaletteNames[_palette]}");
    }

    private void CycleLiveParam(int direction)
    {
        _liveParam = Wrap(_liveParam + direction, LiveParamNames.Length);
        GD.Print($"Live param: {LiveParamNames[_liveParam]} (scrub with triggers / = -)");
    }

    private int ReadInt(string param)
    {
        var value = _material!.GetShaderParameter(param);
        return value.VariantType == Variant.Type.Nil ? 0 : value.As<int>();
    }

    private float ReadFloat(string param)
    {
        var value = _material!.GetShaderParameter(param);
        return value.VariantType == Variant.Type.Nil ? 0f : value.As<float>();
    }

    private static int Wrap(int value, int count) => (value % count + count) % count;
}
