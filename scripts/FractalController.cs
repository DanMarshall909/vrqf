using Godot;
using System;

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
    private bool _autoMorph = true;
    private float _morphHoldSeconds = 2.5f;
    private float _morphTransitionSeconds = 3f;

    [Export]
    public bool AutoMorph
    {
        get => _autoMorph;
        set
        {
            if (_autoMorph == value) return;
            _autoMorph = value;
            NotifyChanged();
        }
    }

    [Export]
    public float MorphHoldSeconds
    {
        get => _morphHoldSeconds;
        set
        {
            float clamped = Mathf.Clamp(value, 0f, 10f);
            if (Mathf.IsEqualApprox(_morphHoldSeconds, clamped)) return;
            _morphHoldSeconds = clamped;
            if (_morphHoldRemaining > _morphHoldSeconds)
                _morphHoldRemaining = _morphHoldSeconds;
            NotifyChanged();
        }
    }

    [Export]
    public float MorphTransitionSeconds
    {
        get => _morphTransitionSeconds;
        set
        {
            float clamped = Mathf.Clamp(value, 0.2f, 10f);
            if (Mathf.IsEqualApprox(_morphTransitionSeconds, clamped)) return;
            _morphTransitionSeconds = clamped;
            NotifyChanged();
        }
    }

    public static string[] FractalNames => FractalSchema.FractalNames;

    public event Action? StateChanged;

    public static readonly string[] MaterialNames =
    {
        "Glow", "Plastic", "Metal", "Glass", "Matcap Chrome", "Matcap Gold", "Matcap Pearl",
        "UVW RGB", "UVW Marble", "UVW Grid", "UVW Contours", "UVW Opal", "UVW Voronoi",
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
    private int _colorMode;
    private int _liveParam;

    private float _iterations;
    private float _morphSpeed;
    private float _shapePhase;
    private float _zoom;     // fractal_extent: larger values enlarge the visible form
    private float _quality;  // max_steps
    private float _radialHueCycles;
    private float _radialHueOffset;
    private float _aoStrength = 0.75f;
    private float _shadowStrength = 0.65f;
    private int _morphTarget = 1;
    private float _morph;    // 0..1 blend toward _morphTarget
    private float _morphLinear;
    private float _morphHoldRemaining;
    private readonly float[,] _formulaParams = new float[FractalSchema.Fractals.Length, FractalSchema.MaxFormulaParams];
    private readonly float[] _roughnessByMaterial = { 1f, 0.35f, 0.08f, 0.02f, 1f, 1f, 1f, 0.25f, 0.18f, 0.45f, 0.30f, 0.10f, 0.20f };
    private readonly float[] _metallicByMaterial = { 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 0.05f, 0.15f, 0.10f, 0.35f, 0.40f };
    private readonly float[] _emissionByMaterial = { 1f, 0.05f, 0f, 0.25f, 1f, 1f, 1f, 0.08f, 0.04f, 0.75f, 0.55f, 0.65f, 0.80f };

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
        _colorMode = ReadInt("color_mode");
        _radialHueCycles = ReadFloat("radial_hue_cycles");
        if (_radialHueCycles <= 0f) _radialHueCycles = 1f;
        _radialHueOffset = ReadFloat("radial_hue_offset");
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
        _aoStrength = ReadFloat("ao_strength");
        _shadowStrength = ReadFloat("shadow_strength");
        _morphLinear = InverseSmoothstep01(Mathf.Clamp(_morph, 0f, 1f));
        _morphHoldRemaining = _morph <= 0.001f ? Mathf.Max(MorphHoldSeconds, 0f) : 0f;
        InitFormulaParamDefaults();
        ApplyFormulaParams();
        ApplyMaterialParameters();

        if (GetNodeOrNull<DirectionalLight3D>("../Sun") is DirectionalLight3D sun)
            _material.SetShaderParameter("shadow_light_dir", sun.GlobalBasis.Z.Normalized());

        for (int i = 0; i < PalettePaths.Length; i++)
            _palettes[i] = GD.Load<Texture2D>(PalettePaths[i]);

        _left = GetNodeOrNull<XRController3D>(LeftControllerPath);
        _right = GetNodeOrNull<XRController3D>(RightControllerPath);
        if (_left is not null) _left.ButtonPressed += name => OnButtonPressed(name, isLeft: true);
        if (_right is not null) _right.ButtonPressed += name => OnButtonPressed(name, isLeft: false);

        GD.Print($"Fractal: {FractalName} | Material: {MaterialName} | Colour: {ColorModeName}");
    }

    // ----- Display accessors (used by the desktop and VR UIs).
    public int FractalTypeIndex => _fractal;
    public FormulaParamSpec[] CurrentFormulaParams => FractalSchema.Fractals[_fractal].Params;
    public string FractalName => FractalNames[_fractal];
    public string MaterialName => MaterialNames[_materialMode];
    public string PaletteName => PaletteNames[_palette];
    public string ColorModeName => _colorMode == 1 ? "Radial hue" : "Orbit palette";
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
    public float RadialHueCyclesValue => _radialHueCycles;
    public float RadialHueOffsetValue => _radialHueOffset;
    public float AoStrengthValue => _aoStrength;
    public float ShadowStrengthValue => _shadowStrength;
    public bool MaterialSupportsSurfaceParams => _materialMode is 1 or 2 or 3 or >= 7;
    public float GetFormulaParam(int index) => _formulaParams[_fractal, index];

    public override void _Process(double delta)
    {
        if (_material is null) return;

        if (AutoMorph)
        {
            float dt = (float)delta;
            if (_morphHoldRemaining > 0f)
            {
                float used = Mathf.Min(_morphHoldRemaining, dt);
                _morphHoldRemaining -= used;
                dt -= used;
            }

            if (dt > 0f && _morphHoldRemaining <= 0f)
            {
                _morphLinear += dt / Mathf.Max(MorphTransitionSeconds, 0.1f);
                if (_morphLinear >= 1f)
                {
                    _fractal = _morphTarget;
                    _morphTarget = Wrap(_morphTarget + 1, FractalNames.Length);
                    _morphLinear = 0f;
                    _morph = 0f;
                    _morphHoldRemaining = Mathf.Max(MorphHoldSeconds, 0f);
                    _material.SetShaderParameter("fractal_type", _fractal);
                    _material.SetShaderParameter("morph_target", _morphTarget);
                    _material.SetShaderParameter("morph", _morph);
                    ApplyFormulaParams();
                    NotifyChanged();
                }
                else
                {
                    _morph = Smoothstep01(_morphLinear);
                    _material.SetShaderParameter("morph", _morph);
                    NotifyChanged();
                }
            }
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

    // ----- Public mutators (controllers, ExplorerPanel & WristMenu all call these).
    public void CycleFractal(int direction)
    {
        _fractal = Wrap(_fractal + direction, FractalNames.Length);
        if (_fractal == _morphTarget)
        {
            _morphTarget = Wrap(_fractal + 1, FractalNames.Length);
            _material?.SetShaderParameter("morph_target", _morphTarget);
        }
        if (_morph <= 0.001f)
            _morphHoldRemaining = Mathf.Max(MorphHoldSeconds, 0f);
        _material?.SetShaderParameter("fractal_type", _fractal);
        ApplyFormulaParams();
        NotifyChanged();
    }

    public void CycleMaterial(int direction)
    {
        _materialMode = Wrap(_materialMode + direction, MaterialNames.Length);
        _material?.SetShaderParameter("material_mode", _materialMode);
        ApplyMaterialParameters();
        NotifyChanged();
    }

    public void AdjustMaterialRoughness(float delta)
    {
        _roughnessByMaterial[_materialMode] = Mathf.Clamp(MaterialRoughnessValue + delta, 0f, 1f);
        _material?.SetShaderParameter("material_roughness", MaterialRoughnessValue);
        NotifyChanged();
    }

    public void AdjustMaterialMetallic(float delta)
    {
        _metallicByMaterial[_materialMode] = Mathf.Clamp(MaterialMetallicValue + delta, 0f, 1f);
        _material?.SetShaderParameter("material_metallic", MaterialMetallicValue);
        NotifyChanged();
    }

    public void AdjustMaterialEmission(float delta)
    {
        _emissionByMaterial[_materialMode] = Mathf.Clamp(MaterialEmissionValue + delta, 0f, 2f);
        _material?.SetShaderParameter("material_emission", MaterialEmissionValue);
        NotifyChanged();
    }

    public void AdjustAoStrength(float delta)
    {
        _aoStrength = Mathf.Clamp(_aoStrength + delta, 0f, 1f);
        _material?.SetShaderParameter("ao_strength", _aoStrength);
        NotifyChanged();
    }

    public void AdjustShadowStrength(float delta)
    {
        _shadowStrength = Mathf.Clamp(_shadowStrength + delta, 0f, 1f);
        _material?.SetShaderParameter("shadow_strength", _shadowStrength);
        NotifyChanged();
    }

    public void AdjustMorphHoldSeconds(float delta) => MorphHoldSeconds += delta;

    public void AdjustMorphTransitionSeconds(float delta) => MorphTransitionSeconds += delta;

    public void AdjustFormulaParam(int index, float delta)
    {
        var specs = CurrentFormulaParams;
        if ((uint)index >= (uint)specs.Length) return;
        var spec = specs[index];
        _formulaParams[_fractal, index] = Mathf.Clamp(_formulaParams[_fractal, index] + delta, spec.Min, spec.Max);
        ApplyFormulaParams();
        NotifyChanged();
    }

    public void ResetCurrentFormulaParams()
    {
        var specs = CurrentFormulaParams;
        for (int i = 0; i < specs.Length; i++)
            _formulaParams[_fractal, i] = specs[i].Default;
        ApplyFormulaParams();
        NotifyChanged();
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
        SetColorMode(0);
    }

    public void CycleColorMode(int direction) => SetColorMode(Wrap(_colorMode + direction, 2));

    public void AdjustRadialHueCycles(float delta)
    {
        _radialHueCycles = Mathf.Clamp(_radialHueCycles + delta, 0.25f, 8f);
        _material?.SetShaderParameter("radial_hue_cycles", _radialHueCycles);
        SetColorMode(1);
    }

    public void AdjustRadialHueOffset(float delta)
    {
        _radialHueOffset = Mathf.Clamp(_radialHueOffset + delta, 0f, 1f);
        _material?.SetShaderParameter("radial_hue_offset", _radialHueOffset);
        SetColorMode(1);
    }

    private void SetColorMode(int mode)
    {
        _colorMode = mode;
        _material?.SetShaderParameter("color_mode", _colorMode);
        NotifyChanged();
    }

    public void CycleLiveParam(int direction)
    {
        _liveParam = Wrap(_liveParam + direction, LiveParamNames.Length);
        NotifyChanged();
    }

    public void AdjustDetail(float delta)
    {
        _iterations = Mathf.Clamp(_iterations + delta, 2f, 64f);
        _material?.SetShaderParameter("iterations", Mathf.RoundToInt(_iterations));
        NotifyChanged();
    }

    public void AdjustShape(float delta)
    {
        _shapePhase += delta;
        _material?.SetShaderParameter("shape", _shapePhase);
        NotifyChanged();
    }

    public void AdjustSpeed(float delta)
    {
        _morphSpeed = Mathf.Clamp(_morphSpeed + delta, 0f, 2f);
        _material?.SetShaderParameter("morph_speed", _morphSpeed);
        NotifyChanged();
    }

    public void AdjustZoom(float delta)
    {
        _zoom = Mathf.Clamp(_zoom + delta, 0.3f, 3f);
        _material?.SetShaderParameter("fractal_extent", _zoom);
        NotifyChanged();
    }

    public void AdjustQuality(float delta)
    {
        _quality = Mathf.Clamp(_quality + delta, 16f, 256f);
        _material?.SetShaderParameter("max_steps", Mathf.RoundToInt(_quality));
        NotifyChanged();
    }

    public void CycleMorphTarget(int direction)
    {
        _morphTarget = Wrap(_morphTarget + direction, FractalNames.Length);
        if (_morphTarget == _fractal)
            _morphTarget = Wrap(_morphTarget + (direction < 0 ? -1 : 1), FractalNames.Length);
        _material?.SetShaderParameter("morph_target", _morphTarget);
        ApplyFormulaParams();
        NotifyChanged();
    }

    public void AdjustMorph(float delta)
    {
        _autoMorph = false;
        _morphHoldRemaining = 0f;
        _morph = Mathf.Clamp(_morph + delta, 0f, 1f);
        _morphLinear = InverseSmoothstep01(_morph);
        _material?.SetShaderParameter("morph", _morph);
        NotifyChanged();
    }

    public void ToggleAutoMorph() => AutoMorph = !AutoMorph;

    public void Randomize()
    {
        _fractal = (int)(GD.Randi() % (uint)FractalNames.Length);
        _materialMode = (int)(GD.Randi() % (uint)MaterialNames.Length);
        _palette = (int)(GD.Randi() % (uint)_palettes.Length);
        _colorMode = (int)(GD.Randi() % 2);
        _radialHueCycles = (float)GD.RandRange(0.5, 2.5);
        _radialHueOffset = (float)GD.Randf();
        _morphTarget = Wrap(_fractal + 1 + (int)(GD.Randi() % (uint)(FractalNames.Length - 1)), FractalNames.Length);
        _shapePhase = (float)GD.RandRange(-3.0, 3.0);
        _morph = (float)GD.RandRange(0.0, 0.6);
        _morphLinear = InverseSmoothstep01(_morph);
        _morphHoldRemaining = _morph <= 0.001f ? Mathf.Max(MorphHoldSeconds, 0f) : 0f;
        _morphSpeed = (float)GD.RandRange(0.0, 0.6);
        _iterations = Mathf.RoundToInt((float)GD.RandRange(6.0, 16.0));
        _zoom = (float)GD.RandRange(0.85, 1.25);
        ApplyAll();
        NotifyChanged();
    }

    private void ApplyAll()
    {
        if (_material is null) return;
        _material.SetShaderParameter("fractal_type", _fractal);
        _material.SetShaderParameter("material_mode", _materialMode);
        ApplyMaterialParameters();
        _material.SetShaderParameter("palette_tex", _palettes[_palette]);
        _material.SetShaderParameter("color_mode", _colorMode);
        _material.SetShaderParameter("radial_hue_cycles", _radialHueCycles);
        _material.SetShaderParameter("radial_hue_offset", _radialHueOffset);
        _material.SetShaderParameter("ao_strength", _aoStrength);
        _material.SetShaderParameter("shadow_strength", _shadowStrength);
        _material.SetShaderParameter("morph_target", _morphTarget);
        _material.SetShaderParameter("morph", _morph);
        _material.SetShaderParameter("shape", _shapePhase);
        _material.SetShaderParameter("morph_speed", _morphSpeed);
        _material.SetShaderParameter("iterations", Mathf.RoundToInt(_iterations));
        _material.SetShaderParameter("fractal_extent", _zoom);
        ApplyFormulaParams();
    }

    private void InitFormulaParamDefaults()
    {
        for (int f = 0; f < FractalSchema.Fractals.Length; f++)
        {
            var specs = FractalSchema.Fractals[f].Params;
            for (int p = 0; p < specs.Length; p++)
                _formulaParams[f, p] = specs[p].Default;
        }
    }

    private void ApplyFormulaParams()
    {
        if (_material is null) return;
        _material.SetShaderParameter("fractal_params_a", PackFormulaVec(_fractal));
        _material.SetShaderParameter("fractal_param4_a", _formulaParams[_fractal, 4]);
        _material.SetShaderParameter("fractal_params_b", PackFormulaVec(_morphTarget));
        _material.SetShaderParameter("fractal_param4_b", _formulaParams[_morphTarget, 4]);
    }

    private Vector4 PackFormulaVec(int fractalIndex) => new(
        _formulaParams[fractalIndex, 0],
        _formulaParams[fractalIndex, 1],
        _formulaParams[fractalIndex, 2],
        _formulaParams[fractalIndex, 3]);

    private void NotifyChanged() => StateChanged?.Invoke();

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
            case Key.C: CycleColorMode(1); break;
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

    private static float Smoothstep01(float u)
    {
        u = Mathf.Clamp(u, 0f, 1f);
        return u * u * (3f - 2f * u);
    }

    private static float InverseSmoothstep01(float y)
    {
        y = Mathf.Clamp(y, 0f, 1f);
        return 0.5f - Mathf.Sin(Mathf.Asin(Mathf.Clamp(1f - 2f * y, -1f, 1f)) / 3f);
    }
}
