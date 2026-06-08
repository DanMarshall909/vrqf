using Godot;

namespace Vrqf;

// Simple on-screen FPS / frame-time readout. Shows on the desktop window and
// (as a head-locked overlay) in the headset — handy when cranking iterations.
public partial class FpsLabel : Label
{
    private double _accum;

    public override void _Process(double delta)
    {
        // Refresh a few times a second so the number is readable.
        _accum += delta;
        if (_accum < 0.25) return;
        _accum = 0.0;

        double fps = Engine.GetFramesPerSecond();
        double ms = fps > 0.0 ? 1000.0 / fps : 0.0;
        Text = $"{fps:0} FPS  ({ms:0.0} ms)";
    }
}
