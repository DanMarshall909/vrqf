using Godot;

namespace Vrqf;

// Cycles the fractal rendered by the Cube's quaternion_julia shader.
//   VR: A/X button = next, B/Y button = previous (either controller).
//   Flat debug: F = next, G = previous.
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

    private ShaderMaterial? _material;
    private int _type;

    public override void _Ready()
    {
        _material = GetSurfaceOverrideMaterial(0) as ShaderMaterial
            ?? GetActiveMaterial(0) as ShaderMaterial;

        if (_material is null)
        {
            GD.PushWarning("FractalController: Cube has no ShaderMaterial — fractal switching disabled.");
            return;
        }

        var current = _material.GetShaderParameter("fractal_type");
        _type = current.VariantType == Variant.Type.Nil ? 0 : current.As<int>();

        ConnectController(LeftControllerPath);
        ConnectController(RightControllerPath);

        GD.Print($"Fractal: {FractalNames[_type]}  (VR: A/X next, B/Y prev | keyboard: F / G)");
    }

    private void ConnectController(NodePath path)
    {
        var controller = GetNodeOrNull<XRController3D>(path);
        if (controller is not null)
            controller.ButtonPressed += OnButtonPressed;
    }

    private void OnButtonPressed(string name)
    {
        if (name == "ax_button") Cycle(1);
        else if (name == "by_button") Cycle(-1);
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventKey { Pressed: true, Echo: false } key)
        {
            if (key.Keycode == Key.F) Cycle(1);
            else if (key.Keycode == Key.G) Cycle(-1);
        }
    }

    private void Cycle(int direction)
    {
        if (_material is null) return;

        int count = FractalNames.Length;
        _type = ((_type + direction) % count + count) % count;
        _material.SetShaderParameter("fractal_type", _type);
        GD.Print($"Fractal {_type}: {FractalNames[_type]}");
    }
}
