# vrqf

<img width="4996" height="2820" alt="image" src="https://github.com/user-attachments/assets/5d45b070-5d4b-4e5d-be66-0f4429f09ea5" />

**vrqf** is an experimental VR quaternion fractal explorer built with **Godot**, **C#**, **OpenXR**, and custom GPU shaders.

The project renders animated 3D fractals inside a VR scene, allowing the viewer to explore mathematical forms as spatial objects rather than flat images. It includes quaternion Julia-style fractals, Mandelbulb variants, iterated function systems, procedural materials, palette switching, morphing, and live parameter control.

## What it does

`vrqf` renders raymarched 3D fractals in real time and places them inside an interactive VR environment.

The project includes:

* A VR fractal viewer using Godot and OpenXR
* A custom spatial shader for raymarched 3D fractals
* Quaternion-based fractal formulas
* Multiple fractal types
* Morphing between fractal formulas
* Palette and material switching
* Live parameter adjustment from VR controllers or keyboard
* A small gallery layout showing several fractals at once
* Experimental reflective, emissive, plastic, metal, glass, and matcap-style materials

## Fractals included

The shader currently supports a range of fractal and procedural distance-estimated forms:

* Quaternion Julia
* Mandelbulb
* Quaternion Mandelbrot
* Menger Sponge
* Sierpinski Tetrahedron
* Burning Ship
* Mandelbox
* Tricorn
* Nova
* Apollonian
* Kaleidoscopic IFS
* Octahedral IFS
* Gyroid
* Schwarz P
* Mandelbulb P3
* Cubic Julia

## Why this exists

This project is a graphics and spatial-maths experiment.

The goal is to explore how abstract mathematical structures can be represented as navigable 3D objects in VR. It combines several areas of interest:

* computational geometry
* raymarching
* fractal distance estimation
* quaternion maths
* procedural rendering
* real-time shader programming
* VR spatial interaction

It is not intended to be a polished product. It is a technical and visual experiment.

## Technology

* Godot 4.x
* C#
* OpenXR
* Godot spatial shaders
* GPU raymarching
* VR controller input
* Procedural material rendering

## Controls

The project supports both VR controller input and keyboard input.

### VR controls

| Action                | Control           |
| --------------------- | ----------------- |
| Next fractal          | A / X             |
| Previous fractal      | B / Y             |
| Change material       | Right stick click |
| Change palette        | Left stick click  |
| Select live parameter | Grip              |
| Adjust live parameter | Triggers          |

### Keyboard controls

| Action                      | Key |
| --------------------------- | --- |
| Next fractal                | `F` |
| Previous fractal            | `G` |
| Change material             | `T` |
| Change palette              | `P` |
| Next live parameter         | `]` |
| Previous live parameter     | `[` |
| Increase selected parameter | `=` |
| Decrease selected parameter | `-` |
| Change morph target         | `M` |
| Increase morph amount       | `.` |
| Decrease morph amount       | `,` |
| Randomise                   | `R` |

Movement uses the standard WASD-style bindings:

| Action               | Key   |
| -------------------- | ----- |
| Move forward         | `W`   |
| Move back            | `S`   |
| Move left            | `A`   |
| Move right           | `D`   |
| Move up              | `E`   |
| Move down            | `Q`   |
| Toggle mouse capture | `Esc` |

## How it works

The fractal surface is generated in a shader using distance estimation and raymarching.

Rather than storing a mesh for each fractal, the shader evaluates a mathematical distance function repeatedly along a ray. When the ray gets close enough to the fractal surface, the shader treats that as a hit and shades the result.

At a high level:

1. A ray is generated from the camera through the rendered object.
2. The ray is marched through a bounded volume.
3. A distance estimator tells the shader how far it can safely step.
4. When the ray approaches the fractal surface, a hit is recorded.
5. A normal is estimated from nearby distance samples.
6. The surface is shaded using the selected material and palette.
7. Depth is written so the fractal correctly interacts with the rest of the scene.

The project uses object-space calculations so the fractal remains anchored correctly in the world as the player moves around it.

## Gallery mode

The scene includes a gallery layout that arranges fractals in a 2×2×2 grid.

One fractal is interactive and controlled by the player. The remaining positions are populated with static fractals using varied types, palettes, and material settings. This gives the scene a small “fractal showroom” feel and makes it easier to compare different forms.

## Project structure

```text
vrqf/
├── project.godot
├── scenes/
│   └── main.tscn
├── scripts/
│   ├── FractalController.cs
│   └── Gallery.cs
├── shaders/
│   └── quaternion_julia.gdshader
└── textures/
    ├── palette_fire.tres
    ├── palette_ice.tres
    ├── palette_rainbow.tres
    └── palette_viridis.tres
```

## Running the project

1. Install Godot 4.x with C#/.NET support.
2. Clone the repository.
3. Open the project in Godot.
4. Ensure OpenXR is available if running in VR.
5. Run the main scene.

The project can be inspected in the Godot editor even without a VR headset, although the intended experience is VR.

## Notes

This is an experimental project and may require adjustment depending on:

* Godot version
* OpenXR runtime
* VR headset
* GPU capability
* shader compatibility
* platform-specific XR setup

The shader is computationally heavy, especially when multiple fractals are visible at once. Quality, iteration count, and raymarch step count may need to be reduced on lower-end hardware.

## Areas for future improvement

Possible next steps:

* Add screenshots or video captures
* Add proper in-world UI documentation
* Add presets for interesting fractal states
* Save and load favourite configurations
* Improve desktop/non-VR navigation
* Add performance quality profiles
* Add hand/controller interaction for grabbing and scaling fractals
* Add more fractal formulas
* Add automated export of still images
* Add explanatory notes for the maths behind each fractal

## Status

Experimental / prototype.

This project exists as a hands-on exploration of VR, shader programming, quaternion fractals, and real-time spatial rendering.
