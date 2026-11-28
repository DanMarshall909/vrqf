using System.Linq;

namespace Vrqf;

public readonly record struct FormulaParamSpec(
    string Label,
    float Default,
    float Min,
    float Max,
    float DesktopStep,
    float VrStep,
    string Format = "0.00");

public readonly record struct FractalDefinition(string Name, FormulaParamSpec[] Params);

public static class FractalSchema
{
    public const int MaxFormulaParams = 5;

    public static readonly FractalDefinition[] Fractals =
    {
        new("Quaternion Julia", new[]
        {
            new FormulaParamSpec("C real (w)", 0.50f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("C i (x)", 0.00f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("C j (y)", 0.50f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("C k (z)", 0.00f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("4D slice (w)", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
        }),
        new("Mandelbulb", new[]
        {
            new FormulaParamSpec("Power", 8.00f, 2.00f, 16.00f, 0.05f, 0.50f),
            new FormulaParamSpec("Phase theta", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
            new FormulaParamSpec("Phase phi", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
        }),
        new("Quaternion Mandelbrot", new[]
        {
            new FormulaParamSpec("Offset w", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset x", 0.18f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset y", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset z", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("4D slice (w)", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
        }),
        new("Menger Sponge", new[]
        {
            new FormulaParamSpec("Ratio", 3.00f, 2.00f, 4.50f, 0.01f, 0.10f),
            new FormulaParamSpec("Twist", 0.00f, -1.50f, 1.50f, 0.01f, 0.10f),
            new FormulaParamSpec("Hole size", 1.00f, 0.50f, 1.60f, 0.01f, 0.05f),
        }),
        new("Sierpinski Tetrahedron", new[]
        {
            new FormulaParamSpec("Scale", 2.00f, 1.50f, 3.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset", 1.00f, 0.40f, 1.80f, 0.01f, 0.05f),
            new FormulaParamSpec("Rotation", 0.00f, -1.57f, 1.57f, 0.01f, 0.10f),
        }),
        new("Burning Ship", new[]
        {
            new FormulaParamSpec("Power", 8.00f, 2.00f, 16.00f, 0.05f, 0.50f),
            new FormulaParamSpec("Phase theta", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
            new FormulaParamSpec("Phase phi", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
        }),
        new("Mandelbox", new[]
        {
            new FormulaParamSpec("Scale", 2.00f, -3.00f, 3.00f, 0.01f, 0.10f),
            new FormulaParamSpec("Box fold", 1.00f, 0.40f, 2.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Min radius", 0.50f, 0.15f, 0.95f, 0.01f, 0.05f),
        }),
        new("Tricorn", new[]
        {
            new FormulaParamSpec("Power", 8.00f, 2.00f, 16.00f, 0.05f, 0.50f),
            new FormulaParamSpec("Phase theta", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
            new FormulaParamSpec("Phase phi", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
        }),
        new("Nova", new[]
        {
            new FormulaParamSpec("Offset X", 0.30f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset Y", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset Z", 0.30f, -1.00f, 1.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Relaxation", 1.00f, 0.30f, 1.80f, 0.01f, 0.05f),
        }),
        new("Apollonian", new[]
        {
            new FormulaParamSpec("Inversion k", 1.00f, 0.50f, 2.20f, 0.01f, 0.05f),
            new FormulaParamSpec("Cell shift", 0.00f, -0.50f, 0.50f, 0.01f, 0.05f),
        }),
        new("Kaleidoscopic IFS", new[]
        {
            new FormulaParamSpec("Angle XY", 0.40f, -3.14f, 3.14f, 0.01f, 0.10f),
            new FormulaParamSpec("Angle YZ", 0.28f, -3.14f, 3.14f, 0.01f, 0.10f),
            new FormulaParamSpec("Scale", 2.00f, 1.50f, 3.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset", 1.00f, 0.40f, 1.80f, 0.01f, 0.05f),
        }),
        new("Octahedral IFS", new[]
        {
            new FormulaParamSpec("Scale", 2.00f, 1.50f, 3.00f, 0.01f, 0.05f),
            new FormulaParamSpec("Offset", 1.00f, 0.40f, 1.80f, 0.01f, 0.05f),
            new FormulaParamSpec("Rotation", 0.00f, -1.57f, 1.57f, 0.01f, 0.10f),
        }),
        new("Gyroid", new[]
        {
            new FormulaParamSpec("Frequency", 3.00f, 1.00f, 8.00f, 0.02f, 0.25f),
            new FormulaParamSpec("Thickness", 0.20f, 0.03f, 0.80f, 0.01f, 0.05f),
            new FormulaParamSpec("Phase", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
        }),
        new("Schwarz P", new[]
        {
            new FormulaParamSpec("Frequency", 3.00f, 1.00f, 8.00f, 0.02f, 0.25f),
            new FormulaParamSpec("Thickness", 0.20f, 0.03f, 0.80f, 0.01f, 0.05f),
            new FormulaParamSpec("Phase", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
        }),
        new("Mandelbulb P3", new[]
        {
            new FormulaParamSpec("Power", 3.00f, 2.00f, 12.00f, 0.05f, 0.25f),
            new FormulaParamSpec("Phase theta", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
            new FormulaParamSpec("Phase phi", 0.00f, -3.14f, 3.14f, 0.01f, 0.15f),
        }),
        new("Cubic Julia", new[]
        {
            new FormulaParamSpec("C real (w)", 0.40f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("C i (x)", 0.00f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("C j (y)", 0.40f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("C k (z)", 0.00f, -1.50f, 1.50f, 0.01f, 0.05f),
            new FormulaParamSpec("4D slice (w)", 0.00f, -1.00f, 1.00f, 0.01f, 0.05f),
        }),
    };

    public static readonly string[] FractalNames = Fractals.Select(f => f.Name).ToArray();
}
