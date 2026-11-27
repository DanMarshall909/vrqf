using Godot;

namespace Vrqf;

// Owns all of the fractal shader's tweakable settings and applies them to the
// fractal mesh's ShaderMaterial. Driven by the controllers/keyboard (here) and
// the desktop and wrist panels (which call the public Cycle*/Adjust* methods).
// All controls update the same ShaderMaterial.
//
//   Fractal:   VR A/X = next, B/Y = prev              | keyboard F / G
//   Material:  VR right stick-click                   | keyboard T
//   Palette:   VR left stick-click                    | keyboard P
//   Live param select: VR grip (R = next, L = prev)   | keyboard ] / [
//   Scrub live param:  triggers (right = up)          | keyboard = / -
public partial class FractalController : MeshInstance3D
{
    [Export] public NodePath LeftControllerPath { get; set; } = "../XROrigin3D/LeftController";
    [Export] public NodePath RightControllerPath { get; set; } = "../XROrigin3D/RightController";
    [Export] public bool AutoMorph { get; set; } = true;
    [Export] public float MorphTransitionSeconds { get; set; } = 3f;

    public static readonly string[] FractalNames =
    {
        "Quaternion Julia", "Mandelbulb", "Quaternion Mandelbrot",
        "Menger Sponge", "Sierpinski Tetrahedron", "Burning Ship",
        "Mandelbox", "Tricorn", "Nova",
        "Apollonian", "Kaleidoscopic IFS", "Octahedral IFS",
        "Gyroid", "Schwarz P", "Mandelbulb P3", "Cubic Julia",
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

    private float _iterations;
    private float _morphSpeed;
    private float _shapePhase;
    private float _zoom;     // fractal_extent
    private float _quality;  // max_steps
    private int _morphTarget = 1;
    private float _morph;    // 0..1 blend toward _morphTarget
    private readonly float[] _roughnessByMaterial = { 1f, 0.35f, 0.08f, 0.02f, 1f, 1f, 1f };
    private readonly float[] _metallicByMaterial = { 0f, 0f, 1f, 0f, 0f, 0f, 0f };
    private readonly float[] _emissionByMaterial = { 1f, 0.05f, 0f, 0.25f, 1f, 1f, 1f };

    public override void _Ready()
    {
        AddToGroup("fractal_controller");

        _material = GetSurfaceOverrideMaterial(0) as ShaderMaterial
            ?? GetActiveMaterial(0) as ShaderMaterial;

        if (_material is null)
        {
            GD.PushWarning("FractalController: fractal mesh has no ShaderMaterial — switching disabled.");
            return;
        }

        _fractal = ReadInt("fractal_type");
        _materialMode = ReadInt("material_mode");
        _iterations = ReadInt("iterations");
        if (_iterations < 2f) _iterations = 8f;
        _morphSpeed = ReadFloat("morph_speed");
        _shapePhase = ReadFloat("shape");
        _zoom = ReadFloat("fractal_extent");
        if (_zoom <= 0f) _zoom = 1f;
        _quality = ReadInt("max_steps");
        if (_quality < 16f) _quality = 96f;
        _morphTarget = ReadInt("morph_target");
        _morph = ReadFloat("morph");
        ApplyMaterialParameters();

        for (int i = 0; i < PalettePaths.Length; i++)
            _palettes[i] = GD.Load<Texture2D>(PalettePaths[i]);

        _left = GetNodeOrNull<XRController3D>(LeftControllerPath);
        _right = GetNodeOrNull<XRController3D>(RightControllerPath);
        if (_left is not null) _left.ButtonPressed += name => OnButtonPressed(name, isLeft: true);
        if (_right is not null) _right.ButtonPressed += name => OnButtonPressed(name, isLeft: false);

        GD.Print($"Fractal: {FractalName} | Material: {MaterialName} | Palette: {PaletteName}");
    }

    // ----- Display accessors (used by the WristMenu labels).
    public string FractalName => FractalNames[_fractal];
    public string MaterialName => MaterialNames[_materialMode];
    public string PaletteName => PaletteNames[_palette];
    public string LiveParamName => LiveParamNames[_liveParam];
    public string DetailText => Mathf.RoundToInt(_iterations).ToString();
    public string ShapeText => _shapePhase.ToString("0.0");
    public string SpeedText => _morphSpeed.ToString("0.00");
    public string ZoomText => _zoom.ToString("0.00");
    public string QualityText => Mathf.RoundToInt(_quality).ToString();
    public string MorphTargetName => FractalNames[_morphTarget];
    public string MorphText => _morph.ToString("0.00");
    public float DetailValue => _iterations;
    public float ShapeValue => _shapePhase;
    public float SpeedValue => _morphSpeed;
    public float ZoomValue => _zoom;
    public float QualityValue => _quality;
    public float MorphValue => _morph;
    public float MaterialRoughnessValue => _roughnessByMaterial[_materialMode];
    public float MaterialMetallicValue => _metallicByMaterial[_materialMode];
    public float MaterialEmissionValue => _emissionByMaterial[_materialMode];
    public bool MaterialSupportsSurfaceParams => _materialMode is 1 or 2 or 3;

    public override void _Process(double delta)
    {
        if (_material is null) return;

        if (AutoMorph)
        {
            _morph += (float)delta / Mathf.Max(MorphTransitionSeconds, 0.1f);
            while (_morph >= 1f)
            {
                _morph -= 1f;
                _fractal = _morphTarget;
                _morphTarget = Wrap(_morphTarget + 1, FractalNames.Length);
                _material.SetShaderParameter("fractal_type", _fractal);
                _material.SetShaderParameter("morph_target", _morphTarget);
            }
            _material.SetShaderParameter("morph", _morph);
        }

        float input = Mathf.Clamp(TriggerInput() + KeyboardScrub(), -1f, 1f);
        if (Mathf.Abs(input) <= 0.001f) return;

        float step = input * (float)delta;
        switch (_liveParam)
        {
            case 0: AdjustDetail(step * 14f); break;
            case 1: AdjustShape(step * 1.5f); break;
            default: AdjustSpeed(step * 1.2f); break;
        }
    }

    private float TriggerInput()
    {
        // While aiming the laser at the wrist menu, the right trigger is a
        // click, not a scrub.
        float up = WristMenu.PointerOverPanel ? 0f : (_right?.GetFloat("trigger") ?? 0f);
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

    // ----- Public mutators (controllers + WristMenu both call these).
    public void CycleFractal(int direction)
    {
        _fractal = Wrap(_fractal + direction, FractalNames.Length);
        if (_fractal == _morphTarget)
        {
            _morphTarget = Wrap(_fractal + 1, FractalNames.Length);
            _material?.SetShaderParameter("morph_target", _morphTarget);
        }
        _material?.SetShaderParameter("fractal_type", _fractal);
    }

    public void CycleMaterial(int direction)
    {
        _materialMode = Wrap(_materialMode + direction, MaterialNames.Length);
        _material?.SetShaderParameter("material_mode", _materialMode);
        ApplyMaterialParameters();
    }

    public void AdjustMaterialRoughness(float delta)
    {
        _roughnessByMaterial[_materialMode] = Mathf.Clamp(MaterialRoughnessValue + delta, 0f, 1f);
        _material?.SetShaderParameter("material_roughness", MaterialRoughnessValue);
    }

    public void AdjustMaterialMetallic(float delta)
    {
        _metallicByMaterial[_materialMode] = Mathf.Clamp(MaterialMetallicValue + delta, 0f, 1f);
        _material?.SetShaderParameter("material_metallic", MaterialMetallicValue);
    }

    public void AdjustMaterialEmission(float delta)
    {
        _emissionByMaterial[_materialMode] = Mathf.Clamp(MaterialEmissionValue + delta, 0f, 2f);
        _material?.SetShaderParameter("material_emission", MaterialEmissionValue);
    }

    private void ApplyMaterialParameters()
    {
        _material?.SetShaderParameter("material_roughness", MaterialRoughnessValue);
        _material?.SetShaderParameter("material_metallic", MaterialMetallicValue);
        _material?.SetShaderParameter("material_emission", MaterialEmissionValue);
    }

    public void CyclePalette(int direction)
    {
        _palette = Wrap(_palette + direction, _palettes.Length);
        _material?.SetShaderParameter("palette_tex", _palettes[_palette]);
    }

    public void CycleLiveParam(int direction) =>
        _liveParam = Wrap(_liveParam + direction, LiveParamNames.Length);

    public void AdjustDetail(float delta)
    {
        _iterations = Mathf.Clamp(_iterations + delta, 2f, 64f);
        _material?.SetShaderParameter("iterations", Mathf.RoundToInt(_iterations));
    }

    public void AdjustShape(float delta)
    {
        _shapePhase += delta;
        _material?.SetShaderParameter("shape", _shapePhase);
    }

    public void AdjustSpeed(float delta)
    {
        _morphSpeed = Mathf.Clamp(_morphSpeed + delta, 0f, 2f);
        _material?.SetShaderParameter("morph_speed", _morphSpeed);
    }

    public void AdjustZoom(float delta)
    {
        _zoom = Mathf.Clamp(_zoom + delta, 0.3f, 3f);
        _material?.SetShaderParameter("fractal_extent", _zoom);
    }

    public void AdjustQuality(float delta)
    {
        _quality = Mathf.Clamp(_quality + delta, 16f, 256f);
        _material?.SetShaderParameter("max_steps", Mathf.RoundToInt(_quality));
    }

    public void CycleMorphTarget(int direction)
    {
        _morphTarget = Wrap(_morphTarget + direction, FractalNames.Length);
        if (_morphTarget == _fractal)
            _morphTarget = Wrap(_morphTarget + (direction < 0 ? -1 : 1), FractalNames.Length);
        _material?.SetShaderParameter("morph_target", _morphTarget);
    }

    public void AdjustMorph(float delta)
    {
        AutoMorph = false;
        _morph = Mathf.Clamp(_morph + delta, 0f, 1f);
        _material?.SetShaderParameter("morph", _morph);
    }

    public void ToggleAutoMorph() => AutoMorph = !AutoMorph;

    public void Randomize()
    {
        _fractal = (int)(GD.Randi() % (uint)FractalNames.Length);
        _materialMode = (int)(GD.Randi() % (uint)MaterialNames.Length);
        _palette = (int)(GD.Randi() % (uint)_palettes.Length);
        _morphTarget = Wrap(_fractal + 1 + (int)(GD.Randi() % (uint)(FractalNames.Length - 1)), FractalNames.Length);
        _shapePhase = (float)GD.RandRange(-3.0, 3.0);
        _morph = (float)GD.RandRange(0.0, 0.6);
        _morphSpeed = (float)GD.RandRange(0.0, 0.6);
        _iterations = Mathf.RoundToInt((float)GD.RandRange(6.0, 16.0));
        _zoom = (float)GD.RandRange(0.85, 1.25);
        ApplyAll();
    }

    private void ApplyAll()
    {
        if (_material is null) return;
        _material.SetShaderParameter("fractal_type", _fractal);
        _material.SetShaderParameter("material_mode", _materialMode);
        ApplyMaterialParameters();
        _material.SetShaderParameter("palette_tex", _palettes[_palette]);
        _material.SetShaderParameter("morph_target", _morphTarget);
        _material.SetShaderParameter("morph", _morph);
        _material.SetShaderParameter("shape", _shapePhase);
        _material.SetShaderParameter("morph_speed", _morphSpeed);
        _material.SetShaderParameter("iterations", Mathf.RoundToInt(_iterations));
        _material.SetShaderParameter("fractal_extent", _zoom);
    }

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
            case Key.M: CycleMorphTarget(1); break;
            case Key.Period: AdjustMorph(0.1f); break;
            case Key.Comma: AdjustMorph(-0.1f); break;
            case Key.Space: ToggleAutoMorph(); break;
            case Key.R: Randomize(); break;
        }
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
