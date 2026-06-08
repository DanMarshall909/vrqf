using Godot;
using System.Collections.Generic;

namespace Vrqf;

// Arranges 8 fractals in a 2x2x2 grid. The interactive fractal (the
// FractalController's mesh, driven by the wrist menu) is moved to the corner
// nearest the player; the other 7 corners get distinct static fractals.
public partial class Gallery : Node3D
{
    [Export] public Vector3 Center { get; set; } = new(0, 1.3f, -0.4f);
    [Export] public float Half { get; set; } = 0.45f;
    [Export] public float SphereRadius { get; set; } = 0.15f;

    // The 7 static fractals (the interactive one is the 8th).
    private static readonly int[] Types = { 1, 3, 4, 6, 9, 12, 10 };

    private static readonly string[] PalettePaths =
    {
        "res://textures/palette_fire.tres",
        "res://textures/palette_ice.tres",
        "res://textures/palette_rainbow.tres",
        "res://textures/palette_viridis.tres",
    };

    public override void _Ready()
    {
        var corners = new List<Vector3>();
        for (int sx = -1; sx <= 1; sx += 2)
            for (int sy = -1; sy <= 1; sy += 2)
                for (int sz = -1; sz <= 1; sz += 2)
                    corners.Add(Center + new Vector3(sx * Half, sy * Half, sz * Half));

        // Interactive fractal -> the front-top corner (highest y + z, nearest the player).
        int home = 0;
        for (int i = 1; i < corners.Count; i++)
            if (corners[i].Y + corners[i].Z > corners[home].Y + corners[home].Z) home = i;

        if (GetTree().GetFirstNodeInGroup("fractal_controller") is Node3D active)
            active.GlobalPosition = corners[home];

        var shader = GD.Load<Shader>("res://shaders/quaternion_julia.gdshader");
        var palettes = new Texture2D[PalettePaths.Length];
        for (int i = 0; i < PalettePaths.Length; i++)
            palettes[i] = GD.Load<Texture2D>(PalettePaths[i]);

        int t = 0;
        for (int i = 0; i < corners.Count; i++)
        {
            if (i == home) continue;
            SpawnFractal(corners[i], Types[t], t, shader, palettes);
            t++;
        }
    }

    private void SpawnFractal(Vector3 pos, int fractalType, int index, Shader shader, Texture2D[] palettes)
    {
        var mesh = new MeshInstance3D
        {
            Mesh = new SphereMesh { Radius = SphereRadius, Height = SphereRadius * 2f },
            Position = pos,
            Layers = 2, // excluded from the ReflectionProbe, like the interactive one
        };

        var mat = new ShaderMaterial { Shader = shader };
        mat.SetShaderParameter("fractal_type", fractalType);
        mat.SetShaderParameter("material_mode", index % 7); // vary the look across the grid
        mat.SetShaderParameter("palette_tex", palettes[index % palettes.Length]);
        mat.SetShaderParameter("morph_speed", 0.12f);
        mat.SetShaderParameter("shape", index * 0.8f);
        mat.SetShaderParameter("iterations", 7);
        mat.SetShaderParameter("max_steps", 64); // lighter than the interactive one (8 on screen at once)
        mat.SetShaderParameter("mesh_half", SphereRadius);
        mat.SetShaderParameter("fractal_extent", 1.0f);
        mesh.MaterialOverride = mat;

        AddChild(mesh);
    }
}
