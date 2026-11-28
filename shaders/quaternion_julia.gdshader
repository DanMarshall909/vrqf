// Raymarched 3D fractal explorer, rendered inside a spherical proxy volume.
//
// This runs on the Fractal MeshInstance3D, so the fractal is anchored exactly
// where the proxy sits in world space. Working entirely in object space (and
// letting Godot's transform pipeline do the rest) is what keeps it in the
// correct position from every viewpoint as the player moves or turns.
//
// fractal_type / morph_target select the formula (morph blends between them):
//   0 = Quaternion Julia    4 = Sierpinski      8 = Nova (3D)          12 = Gyroid
//   1 = Mandelbulb          5 = Burning ship    9 = Apollonian         13 = Schwarz-P
//   2 = Quaternion Mandel   6 = Mandelbox      10 = Kaleidoscopic IFS  14 = Mandelbulb P3
//   3 = Menger sponge       7 = Tricorn (3D)   11 = Octahedral IFS     15 = Cubic Julia
//
// material_mode selects the surface look:
//   0 = Glow (emissive palette)       7 = UVW RGB (3D coordinate cube)
//   1 = Plastic (lit, palette)        8 = UVW Marble (3D fBM strata)
//   2 = Metal  (reflective)           9 = UVW Grid (3D lattice & checker)
//   3 = Glass  (fresnel/reflective)  10 = UVW Contours (3D origin shells)
//   4 = Matcap chrome                11 = UVW Opal (3D iridescent flecks)
//   5 = Matcap gold                  12 = UVW Voronoi (3D crystal cells)
//   6 = Matcap pearl
//
// The lit pipeline (not unshaded) is what lets Godot's ReflectionProbe bounce
// the real scene off the metal/glass surface. (SSR is unreliable here because
// this shader writes DEPTH and skips the prepass SSR relies on — the probe,
// which must exclude this mesh via render layers, is the real mechanism.)
shader_type spatial;
render_mode cull_front, depth_draw_always;

uniform int fractal_type = 0;
uniform int morph_target = 1;        // fractal to morph toward
uniform float morph = 0.0;           // 0 = fractal_type, 1 = morph_target (blends the DEs)
uniform int material_mode = 0;
uniform float material_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float material_emission : hint_range(0.0, 2.0) = 1.0;
uniform int max_steps = 96;
uniform int iterations = 8;
uniform float epsilon = 0.0012;
uniform float morph_speed = 0.25;    // animation rate for ALL fractals (0 = frozen)
uniform float shape = 0.0;           // per-fractal shape parameter (scrubbed)
uniform sampler2D palette_tex : source_color, hint_default_white;
uniform sampler2D radial_hue_tex : source_color, hint_default_white;
uniform int color_mode = 1;          // 0 = orbit palette, 1 = radial hue
uniform float radial_hue_cycles : hint_range(0.25, 8.0) = 1.0;
uniform float radial_hue_offset : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.6, 0.85, 1.0);
uniform float mesh_half = 0.15;      // proxy sphere radius (object space)
uniform float fractal_extent = 1.0;  // global size multiplier (1 = auto-fit per fractal)
uniform float boundary_eps = 0.003;  // trim hits on the box shell (kills edge lines)
uniform float ao_strength : hint_range(0.0, 1.0) = 0.75;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec3 shadow_light_dir = vec3(0.353553, 0.707107, 0.612372);
uniform vec4 fractal_params_a = vec4(0.5, 0.0, 0.5, 0.0);
uniform float fractal_param4_a = 0.0;
uniform vec4 fractal_params_b = vec4(8.0, 0.0, 0.0, 0.0);
uniform float fractal_param4_b = 0.0;

varying vec3 v_frag_local;  // this fragment's position in object space
varying vec3 v_inv_m0;
varying vec3 v_inv_m1;
varying vec3 v_inv_m2;
varying vec3 v_inv_m3;

// Hamilton product of two quaternions (w, x, y, z).
vec4 qmul(vec4 a, vec4 b) {
	return vec4(
		a.x * b.x - a.y * b.y - a.z * b.z - a.w * b.w,
		a.x * b.y + a.y * b.x + a.z * b.w - a.w * b.z,
		a.x * b.z - a.y * b.w + a.z * b.x + a.w * b.y,
		a.x * b.w + a.y * b.z - a.z * b.y + a.w * b.x
	);
}

vec2 rot2(vec2 v, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// ----- Distance estimators. Each returns DE and a 0..1 colour factor (trap).

float qjulia_de(vec3 pos, vec4 c, float slice_w, out float trap) {
	vec4 z = vec4(pos, slice_w);
	float dz2 = 1.0; // squared magnitude of the running derivative
	float m2 = dot(z, z);
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		dz2 *= 4.0 * m2;
		z = qmul(z, z) + c;
		m2 = dot(z, z);
		orbit = min(orbit, m2);
		if (m2 > 256.0 || dz2 > 1e24) break;
	}
	float r = sqrt(m2);
	trap = clamp(sqrt(orbit) * 0.7, 0.0, 1.0);
	return 0.25 * r * log(max(r, 1.0001)) / sqrt(max(dz2, 1e-12));
}

float qmandel_de(vec3 pos, vec4 c_offset, float slice_w, out float trap) {
	vec4 c = vec4(pos, slice_w) + c_offset;
	vec4 z = vec4(0.0);
	float dr = 1.0;
	float m2 = 0.0;
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		dr = 2.0 * sqrt(m2) * dr + 1.0;
		z = qmul(z, z) + c;
		m2 = dot(z, z);
		orbit = min(orbit, m2);
		if (m2 > 256.0 || dr > 1e12) break;
	}
	float r = sqrt(m2);
	trap = clamp(sqrt(orbit) * 0.7, 0.0, 1.0);
	return 0.5 * r * log(max(r, 1.0001)) / max(dr, 1e-6);
}

float mandelbulb_de(vec3 pos, float power, float phase_theta, float phase_phi, out float trap) {
	vec3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		r = length(z);
		if (r > 2.0 || dr > 1e12) break;
		float safe_r = max(r, 1e-6);
		float theta = acos(clamp(z.z / safe_r, -1.0, 1.0));
		float phi = (abs(z.x) + abs(z.y) > 1e-6) ? atan(z.y, z.x) : 0.0;
		dr = pow(safe_r, power - 1.0) * power * dr + 1.0;
		float zr = pow(safe_r, power);
		theta = theta * power + phase_theta;
		phi = phi * power + phase_phi;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / max(dr, 1e-6);
}

float burningship_de(vec3 pos, float power, float phase_theta, float phase_phi, out float trap) {
	vec3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		z = abs(z); // the "burning ship" fold
		r = length(z);
		if (r > 2.0 || dr > 1e12) break;
		float safe_r = max(r, 1e-6);
		float theta = acos(clamp(z.z / safe_r, -1.0, 1.0));
		float phi = (abs(z.x) + abs(z.y) > 1e-6) ? atan(z.y, z.x) : 0.0;
		dr = pow(safe_r, power - 1.0) * power * dr + 1.0;
		float zr = pow(safe_r, power);
		theta = theta * power + phase_theta;
		phi = phi * power + phase_phi;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / max(dr, 1e-6);
}

float box_de(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float menger_de(vec3 p, float ratio, float twist, float hole_size, out float trap) {
	if (abs(twist) > 1e-4) p.xz = rot2(p.xz, twist * p.y);
	float d = box_de(p, vec3(1.0));
	float s = 1.0;
	int iters = min(iterations, 10);
	for (int i = 0; i < iters; i++) {
		vec3 a = mod(p * s, 2.0) - 1.0;
		s *= ratio;
		vec3 r = abs(hole_size - ratio * abs(a));
		float da = max(r.x, r.y);
		float db = max(r.y, r.z);
		float dc = max(r.z, r.x);
		float c = (min(da, min(db, dc)) - 1.0) / s;
		d = max(d, c);
	}
	trap = clamp(length(p) * 0.6, 0.0, 1.0);
	return d;
}

float sierpinski_de(vec3 z, float scale, float offset, float rot, out float trap) {
	int iters = min(iterations, 20);
	for (int i = 0; i < iters; i++) {
		if (abs(rot) > 1e-4) z.xz = rot2(z.xz, rot);
		if (z.x + z.y < 0.0) z.xy = -z.yx;
		if (z.x + z.z < 0.0) z.xz = -z.zx;
		if (z.y + z.z < 0.0) z.zy = -z.yz;
		z = z * scale - vec3(offset) * (scale - 1.0);
	}
	trap = clamp(length(z) * 0.25, 0.0, 1.0);
	return length(z) * pow(scale, -float(iters));
}

float mandelbox_de(vec3 pos, float box_scale, float box_fold, float min_r, out float trap) {
	float s = (abs(box_scale) < 0.5) ? (box_scale < 0.0 ? -0.5 : 0.5) : box_scale;
	float min_r2 = max(min_r * min_r, 0.02);
	vec4 z = vec4(pos, 1.0);
	float orbit = 1e9;
	int iters = min(iterations, 24);
	for (int i = 0; i < iters; i++) {
		if (length(z.xyz) > 6.0 || abs(z.w) > 1e12) break;
		z.xyz = clamp(z.xyz, -box_fold, box_fold) * 2.0 - z.xyz; // box fold
		float r2 = dot(z.xyz, z.xyz);
		if (r2 < min_r2) z *= 1.0 / min_r2;                      // sphere fold
		else if (r2 < 1.0) z *= 1.0 / r2;
		z = z * vec4(vec3(s), abs(s)) + vec4(pos, 0.0);
		orbit = min(orbit, r2);
	}
	trap = clamp(sqrt(orbit) * 0.5, 0.0, 1.0);
	return length(z.xyz) / max(abs(z.w), 1e-6);
}

float tricorn_de(vec3 pos, float power, float phase_theta, float phase_phi, out float trap) {
	vec3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		r = length(z);
		if (r > 2.0 || dr > 1e12) break;
		z.y = -z.y; z.z = -z.z;                           // conjugate fold (tricorn)
		float safe_r = max(r, 1e-6);
		float theta = acos(clamp(z.z / safe_r, -1.0, 1.0));
		float phi = (abs(z.x) + abs(z.y) > 1e-6) ? atan(z.y, z.x) : 0.0;
		dr = pow(safe_r, power - 1.0) * power * dr + 1.0;
		float zr = pow(safe_r, power);
		theta = theta * power + phase_theta;
		phi = phi * power + phase_phi;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / max(dr, 1e-6);
}

float nova_de(vec3 pos, vec3 c_off, float relax, out float trap) {
	vec3 z = pos;
	vec3 dz = vec3(1.0, 0.0, 0.0);
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		if (dot(z, z) > 16.0 || dot(dz, dz) > 1e12) break;
		vec3 z2 = z * z;
		vec3 z3 = z2 * z;
		dz = 3.0 * z2 * dz;
		z = z - relax * (z3 - vec3(1.0)) / (3.0 * z2 + vec3(1e-4)) + c_off; // Newton step + constant
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.6, 0.0, 1.0);
	return 0.4 * length(z) / max(length(dz), 1e-6);
}

// Apollonian gasket via repeated cell-folding + inversion (after iq).
float apollonian_de(vec3 p, float k, float shift, out float trap) {
	float scale = 1.0;
	vec3 z = p;
	float orbit = 1e9;
	int iters = min(iterations, 16);
	for (int i = 0; i < iters; i++) {
		z = -1.0 + 2.0 * fract(0.5 * (z + vec3(shift)) + 0.5);
		float r2 = dot(z, z);
		orbit = min(orbit, r2);
		float kk = k / max(r2, 1e-4);
		z *= kk;
		scale *= kk;
		if (scale > 1e12) break;
	}
	trap = clamp(sqrt(orbit), 0.0, 1.0);
	return 0.25 * abs(z.y) / max(scale, 1e-6);
}

// Kaleidoscopic IFS: a Sierpinski fold with rotations between iterations.
float kifs_de(vec3 z, float ang_xy, float ang_yz, float scale, float offset, out float trap) {
	float orbit = 1e9;
	int iters = min(iterations, 20);
	for (int i = 0; i < iters; i++) {
		z.xy = rot2(z.xy, ang_xy);
		z = abs(z);
		if (z.x < z.y) z.xy = z.yx;
		if (z.x < z.z) z.xz = z.zx;
		if (z.y < z.z) z.yz = z.zy;
		z.yz = rot2(z.yz, ang_yz);
		z = z * scale - vec3(offset) * (scale - 1.0);
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.3, 0.0, 1.0);
	return length(z) * pow(scale, -float(iters));
}

// Octahedral IFS (abs + sort fold).
float octahedral_de(vec3 z, float s, float offset, float rot, out float trap) {
	float orbit = 1e9;
	int iters = min(iterations, 20);
	for (int i = 0; i < iters; i++) {
		if (abs(rot) > 1e-4) z.xz = rot2(z.xz, rot);
		z = abs(z);
		if (z.x < z.y) z.xy = z.yx;
		if (z.x < z.z) z.xz = z.zx;
		if (z.y < z.z) z.yz = z.zy;
		z = z * s - vec3(offset) * (s - 1.0);
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.3, 0.0, 1.0);
	return length(z) * pow(s, -float(iters));
}

// Gyroid triply-periodic minimal surface (thickened isosurface).
float gyroid_de(vec3 p, float s, float thickness, float phase, out float trap) {
	vec3 q = p * s + vec3(phase);
	float f = dot(sin(q), cos(q.yzx));
	trap = clamp(abs(f), 0.0, 1.0);
	return (abs(f) - thickness) * 0.3 / max(s, 0.1);
}

// Schwarz-P triply-periodic minimal surface (thickened isosurface).
float schwarz_de(vec3 p, float s, float thickness, float phase, out float trap) {
	vec3 q = p * s + vec3(phase);
	float f = cos(q.x) + cos(q.y) + cos(q.z);
	trap = clamp(abs(f) * 0.3, 0.0, 1.0);
	return (abs(f) - thickness) * 0.3 / max(s, 0.1);
}

// Cubic quaternion Julia: z = z^3 + c.
float qjulia3_de(vec3 pos, vec4 c, float slice_w, out float trap) {
	vec4 z = vec4(pos, slice_w);
	float dz2 = 1.0;
	float m2 = dot(z, z);
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		dz2 *= 9.0 * m2 * m2;          // |3 z^2|^2 = 9 |z|^4
		z = qmul(qmul(z, z), z) + c;   // z^3 + c
		m2 = dot(z, z);
		orbit = min(orbit, m2);
		if (m2 > 256.0 || dz2 > 1e24) break;
	}
	float r = sqrt(m2);
	trap = clamp(sqrt(orbit) * 0.7, 0.0, 1.0);
	return 0.16 * r * log(max(r, 1.0001)) / sqrt(max(dz2, 1e-12));
}

// Bounding radius of each fractal in its own fractal space. The sphere is
// scaled to this so each fractal fits snugly inside instead of being clipped
// (the cubic Menger/Sierpinski reach their corners at radius ~sqrt(3)).
float fractal_radius(int type) {
	if (type == 1) return 1.3;   // Mandelbulb
	if (type == 2) return 1.6;   // Quaternion Mandelbrot
	if (type == 3) return 1.85;  // Menger sponge (cube corners)
	if (type == 4) return 1.85;  // Sierpinski tetrahedron
	if (type == 5) return 1.4;   // Burning ship
	if (type == 6) return 4.5;   // Mandelbox (lives in a larger domain)
	if (type == 7) return 1.4;   // Tricorn
	if (type == 8) return 1.6;   // Nova
	if (type == 9) return 1.1;   // Apollonian
	if (type == 10) return 1.8;  // Kaleidoscopic IFS
	if (type == 11) return 1.8;  // Octahedral IFS
	if (type == 12) return 1.4;  // Gyroid
	if (type == 13) return 1.4;  // Schwarz-P
	if (type == 14) return 1.35; // Mandelbulb P3
	if (type == 15) return 1.4;  // Cubic Julia
	return 1.5;                  // Quaternion Julia
}

// Distance estimator for one fractal. `fp`/`fp4` set its per-formula parameters,
// `shape` modulates around them, and `anim` (= TIME * morph_speed) animates it.
float de(int type, vec3 p, float anim, vec4 fp, float fp4, out float trap) {
	if (type == 1) return mandelbulb_de(p, clamp(fp.x + 4.0 * sin(shape) + sin(anim), 1.5, 16.0), fp.y, fp.z, trap);
	if (type == 2) {
		vec4 off = fp + 0.18 * vec4(sin(shape), cos(shape * 0.9) - 1.0, sin(anim), cos(anim * 0.8) - 1.0);
		return qmandel_de(p, off, fp4, trap);
	}
	if (type == 3) return menger_de(p, max(fp.x + 0.6 * sin(shape) + 0.15 * sin(anim), 1.5), fp.y, fp.z, trap);
	if (type == 4) return sierpinski_de(p, max(fp.x + 0.28 * sin(shape) + 0.05 * sin(anim), 1.05), fp.y, fp.z, trap);
	if (type == 5) return burningship_de(p, clamp(fp.x + 4.0 * sin(shape) + sin(anim), 1.5, 16.0), fp.y, fp.z, trap);
	if (type == 6) return mandelbox_de(p, fp.x + 0.5 * sin(shape) + 0.1 * sin(anim), max(fp.y, 0.1), fp.z, trap);
	if (type == 7) return tricorn_de(p, clamp(fp.x + 4.0 * sin(shape) + sin(anim), 1.5, 16.0), fp.y, fp.z, trap);
	if (type == 8) {
		vec3 off = fp.xyz + 0.3 * vec3(cos(shape) - 1.0, sin(shape * 0.9), cos(shape * 1.3) - 1.0) + 0.1 * vec3(sin(anim));
		return nova_de(p, off, max(fp.w, 0.1), trap);
	}
	if (type == 9) return apollonian_de(p, max(fp.x + 0.25 * sin(shape), 0.1), fp.y, trap);
	if (type == 10) {
		return kifs_de(p, fp.x + 0.3 * sin(shape) + 0.1 * sin(anim), fp.y + 0.21 * sin(shape) + 0.07 * sin(anim), max(fp.z, 1.05), fp.w, trap);
	}
	if (type == 11) return octahedral_de(p, max(fp.x + 0.3 * sin(shape), 1.05), fp.y, fp.z, trap);
	if (type == 12) return gyroid_de(p, max(fp.x + 1.0 * sin(shape) + 0.3 * sin(anim), 0.1), fp.y, fp.z, trap);
	if (type == 13) return schwarz_de(p, max(fp.x + 1.0 * sin(shape), 0.1), fp.y, fp.z, trap);
	if (type == 14) return mandelbulb_de(p, clamp(fp.x + 1.5 * sin(shape) + 0.5 * sin(anim), 1.5, 16.0), fp.y, fp.z, trap);
	if (type == 15) {
		vec4 c3 = fp + 0.4 * vec4(cos(shape) - 1.0, sin(shape * 0.9), cos(shape * 1.3) - 1.0, sin(shape * 0.5))
			+ 0.1 * vec4(sin(anim), cos(anim) - 1.0, sin(anim * 1.3), cos(anim * 0.7) - 1.0);
		return qjulia3_de(p, c3, fp4, trap);
	}
	// 0 = Quaternion Julia: shape sweeps the c constant, anim wobbles it.
	vec4 c = fp + 0.5 * vec4(cos(shape) - 1.0, sin(shape * 0.9), cos(shape * 1.3) - 1.0, sin(shape * 0.5))
		+ 0.12 * vec4(sin(anim), cos(anim * 0.8) - 1.0, sin(anim * 1.2), cos(anim * 0.6) - 1.0);
	return qjulia_de(p, c, fp4, trap);
}

float fractal_scale(int type) {
	return fractal_radius(type) / (max(fractal_extent, 0.01) * mesh_half);
}

// Blend the active fractal toward morph_target by `morph` in object space so
// fractals with different canonical domain radii stay properly framed.
float map_obj(vec3 p_obj, float anim, out float trap) {
	float sA = fractal_scale(fractal_type);
	float dA = de(fractal_type, p_obj * sA, anim, fractal_params_a, fractal_param4_a, trap) / sA;
	if (morph <= 0.001) return dA; // common case: one evaluation
	float tB;
	float sB = fractal_scale(morph_target);
	float dB = de(morph_target, p_obj * sB, anim, fractal_params_b, fractal_param4_b, tB) / sB;
	trap = mix(trap, tB, morph);
	return mix(dA, dB, morph);
}

vec3 calc_normal(vec3 p_obj, float anim, float h) {
	vec2 k = vec2(1.0, -1.0);
	float t;
	return normalize(
		k.xyy * map_obj(p_obj + k.xyy * h, anim, t) +
		k.yyx * map_obj(p_obj + k.yyx * h, anim, t) +
		k.yxy * map_obj(p_obj + k.yxy * h, anim, t) +
		k.xxx * map_obj(p_obj + k.xxx * h, anim, t)
	);
}

float calc_ao(vec3 p_obj, vec3 n_obj, float anim) {
	float occ = 0.0;
	float sca = 1.0;
	float trap;
	for (int i = 0; i < 5; i++) {
		float h = (0.01 + 0.03 * float(i)) * mesh_half;
		float d = map_obj(p_obj + n_obj * h, anim, trap);
		occ += max(h - d, 0.0) * sca;
		sca *= 0.6;
	}
	return clamp(1.0 - occ * (6.0 / max(mesh_half, 0.01)), 0.15, 1.0);
}

float calc_soft_shadow(vec3 p_obj, vec3 n_obj, vec3 l_dir_obj, float anim) {
	if (shadow_strength <= 0.001) return 1.0;
	if (dot(n_obj, l_dir_obj) <= 0.0) return 0.25;
	float res = 1.0;
	float t = max(epsilon * 4.0, 0.005 * mesh_half);
	float max_t = mesh_half * 1.6;
	vec3 ro = p_obj + n_obj * (epsilon * 2.0);
	float trap;
	for (int i = 0; i < 16; i++) {
		vec3 p_s = ro + l_dir_obj * t;
		if (length(p_s) > mesh_half || t > max_t) break;
		float d = map_obj(p_s, anim, trap);
		if (d < epsilon * 0.5) return 0.2;
		res = min(res, 6.0 * d / t);
		t += clamp(d, 0.01 * mesh_half, 0.12 * mesh_half);
	}
	return clamp(res, 0.2, 1.0);
}

// Cheap procedural "matcap": shade from the view-space normal as if lit by a
// sphere capture. tint/style chosen by the caller for chrome / gold / pearl.
vec3 procedural_matcap(vec3 nv, vec3 tint, float metal_sheen) {
	// nv is the view-space normal. Use its xy as the matcap lookup.
	vec2 m = nv.xy * 0.5 + 0.5;
	float key = pow(clamp(m.y * 0.6 + 0.5, 0.0, 1.0), 1.5);   // soft top light
	float rim = pow(1.0 - clamp(nv.z, 0.0, 1.0), 3.0);        // grazing rim
	float spec = pow(clamp(dot(nv, normalize(vec3(0.4, 0.7, 0.6))), 0.0, 1.0), metal_sheen);
	return tint * (0.25 + key * 0.8) + vec3(1.0) * spec * 0.9 + tint * rim * 0.6;
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash33(i + vec3(0.0, 0.0, 0.0)).x;
	float n100 = hash33(i + vec3(1.0, 0.0, 0.0)).x;
	float n010 = hash33(i + vec3(0.0, 1.0, 0.0)).x;
	float n110 = hash33(i + vec3(1.0, 1.0, 0.0)).x;
	float n001 = hash33(i + vec3(0.0, 0.0, 1.0)).x;
	float n101 = hash33(i + vec3(1.0, 0.0, 1.0)).x;
	float n011 = hash33(i + vec3(0.0, 1.0, 1.0)).x;
	float n111 = hash33(i + vec3(1.0, 1.0, 1.0)).x;
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(13.7, 7.3, 19.1);
		a *= 0.5;
	}
	return v;
}

// 3D cellular distance: returns vec2(edge_distance, cell_id).
vec2 voronoi3(vec3 p) {
	vec3 n = floor(p);
	vec3 f = fract(p);
	float md1 = 8.0;
	float md2 = 8.0;
	float cell_id = 0.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 g = vec3(float(i), float(j), float(k));
				vec3 o = hash33(n + g);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < md1) {
					md2 = md1;
					md1 = d;
					cell_id = o.x;
				} else if (d < md2) {
					md2 = d;
				}
			}
		}
	}
	return vec2(sqrt(md2) - sqrt(md1), cell_id);
}

vec3 sample_color(float u) {
	return color_mode == 1
		? texture(radial_hue_tex, vec2(fract(u + radial_hue_offset), 0.5)).rgb
		: texture(palette_tex, vec2(clamp(u, 0.0, 1.0), 0.5)).rgb;
}

// Ray vs sphere of radius r centred at the origin (rd must be normalised).
// A sphere has no edges or corners, so there are no straight clip-lines and
// no grazing-ray precision artifacts the way an axis-aligned box has.
bool ray_sphere(vec3 ro, vec3 rd, float r, out float t_near, out float t_far) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) return false;
	h = sqrt(h);
	t_near = -b - h;
	t_far = -b + h;
	return t_far > 0.0;
}

void vertex() {
	v_frag_local = VERTEX;
	mat4 inv_m = inverse(MODEL_MATRIX);
	v_inv_m0 = inv_m[0].xyz;
	v_inv_m1 = inv_m[1].xyz;
	v_inv_m2 = inv_m[2].xyz;
	v_inv_m3 = inv_m[3].xyz;
}

void fragment() {
	// Per-eye ray origin in object space. Under multiview, VIEW_MATRIX is the
	// CENTRAL camera and the per-eye offset is in EYE_OFFSET (view space), so
	// fold it in — using INV_VIEW_MATRIX[3] alone gives the mono camera for
	// both eyes, collapsing the stereo so the fractal looks painted on the
	// sphere shell. (In flat mode EYE_OFFSET is zero, so this is unchanged.)
	mat3 inv_model_3 = mat3(v_inv_m0, v_inv_m1, v_inv_m2);
	vec3 cam_world = (INV_VIEW_MATRIX * vec4(EYE_OFFSET, 1.0)).xyz;
	vec3 ro = inv_model_3 * cam_world + v_inv_m3;
	vec3 rd = normalize(v_frag_local - ro);

	float t_near, t_far;
	if (!ray_sphere(ro, rd, mesh_half, t_near, t_far)) {
		discard;
	}
	t_near = max(t_near, 0.0); // start at the camera if it is inside the volume

	// Animation phase shared by every fractal (morph_speed scales it; 0 = frozen).
	float anim = TIME * morph_speed;

	// Sphere-trace through the proxy volume with distance-adaptive tolerance.
	float t = t_near;
	bool hit = false;
	float trap = 0.0;
	float hit_eps = epsilon;
	vec3 p_obj = ro;
	for (int i = 0; i < max_steps; i++) {
		p_obj = ro + rd * t;
		float d = map_obj(p_obj, anim, trap);
		float step_eps = clamp(t * 0.0012, epsilon * 0.35, epsilon * 4.0);
		if (d < step_eps) {
			hit = true;
			hit_eps = step_eps;
			break;
		}
		t += d;
		if (t > t_far) break;
	}

	if (!hit) {
		discard;
	}

	// Trim hits sitting on the bounding shell — a fractal surface clipped by
	// the volume boundary, or a grazing-ray sliver. With a sphere this is a
	// soft circular crop rather than straight box-edge lines.
	if (mesh_half - length(p_obj) < boundary_eps) {
		discard;
	}

	// Object-space normal, then into view space for the lit pipeline.
	vec3 n_obj = calc_normal(p_obj, anim, max(hit_eps * 0.75, 0.0002));
	vec3 n_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_obj, 0.0)).xyz);
	NORMAL = n_view;

	float ao = (ao_strength > 0.001) ? mix(1.0, calc_ao(p_obj, n_obj, anim), ao_strength) : 1.0;
	vec3 l_dir_obj = normalize(inv_model_3 * shadow_light_dir);
	float shad = mix(1.0, calc_soft_shadow(p_obj, n_obj, l_dir_obj, anim), shadow_strength);

	// Sample a 1D hue texture by 3D distance from the fractal centre,
	// and build normalized 3D object-space UVW coordinates in [-1, 1]^3.
	vec3 uvw = p_obj / max(mesh_half, 0.001);
	float uvw_scale = max(radial_hue_cycles, 0.25);
	float radial_distance = clamp(length(uvw), 0.0, 1.0);
	float hue_lookup = fract(radial_distance * radial_hue_cycles + radial_hue_offset);
	vec3 pal = color_mode == 1
		? texture(radial_hue_tex, vec2(hue_lookup, 0.5)).rgb
		: texture(palette_tex, vec2(trap, 0.5)).rgb;
	float fres = pow(1.0 - clamp(dot(n_view, VIEW), 0.0, 1.0), 3.0);

	if (material_mode == 1) {
		// Plastic: lit dielectric tinted by the palette.
		ALBEDO = pal * shad;
		METALLIC = material_metallic;
		ROUGHNESS = material_roughness;
		SPECULAR = 0.5;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = pal * material_emission * ao;
	} else if (material_mode == 2) {
		// Metal: reflects the real scene via ReflectionProbe.
		ALBEDO = mix(pal, vec3(1.0), color_mode == 1 ? 0.3 : 0.6) * shad;
		METALLIC = material_metallic;
		ROUGHNESS = material_roughness;
		SPECULAR = 0.5;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = pal * material_emission * ao;
	} else if (material_mode == 3) {
		// Glass: smooth, strongly reflective dielectric (fresnel-driven).
		// Not true refraction — reflections only (see notes).
		ALBEDO = mix(pal * 0.2, vec3(1.0), fres) * shad;
		METALLIC = material_metallic;
		ROUGHNESS = material_roughness;
		SPECULAR = 1.0;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = glow_color * fres * material_emission * ao;
	} else if (material_mode == 4) {
		// Matcap chrome.
		vec3 tint = color_mode == 1 ? mix(vec3(0.8, 0.85, 0.95), pal, 0.5) : vec3(0.8, 0.85, 0.95);
		vec3 m = procedural_matcap(n_view, tint, 24.0);
		ALBEDO = vec3(0.0);
		EMISSION = m * material_emission * ao * mix(1.0, shad, 0.5);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	} else if (material_mode == 5) {
		// Matcap gold.
		vec3 tint = color_mode == 1 ? mix(vec3(1.0, 0.75, 0.3), pal, 0.5) : vec3(1.0, 0.75, 0.3);
		vec3 m = procedural_matcap(n_view, tint, 16.0);
		ALBEDO = vec3(0.0);
		EMISSION = m * material_emission * ao * mix(1.0, shad, 0.5);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	} else if (material_mode == 6) {
		// Matcap pearl.
		vec3 m = procedural_matcap(n_view, mix(pal, vec3(0.95), 0.5), 8.0);
		ALBEDO = vec3(0.0);
		EMISSION = m * material_emission * ao * mix(1.0, shad, 0.5);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	} else if (material_mode == 7) {
		// UVW RGB: direct 3D object-space (u, v, w) coordinate cube.
		vec3 rot_uvw = uvw;
		rot_uvw.xz = rot2(rot_uvw.xz, radial_hue_offset * 6.2831853);
		vec3 col = (uvw_scale <= 1.01)
			? clamp(rot_uvw * 0.5 + 0.5, 0.0, 1.0)
			: 0.5 + 0.5 * sin(rot_uvw * uvw_scale * 3.14159265);
		ALBEDO = col * shad;
		METALLIC = material_metallic;
		ROUGHNESS = material_roughness;
		SPECULAR = 0.5;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = col * material_emission * ao;
	} else if (material_mode == 8) {
		// UVW Marble: domain-warped 3D strata & mineral veins.
		vec3 q = uvw * (2.5 * uvw_scale);
		float warp = fbm3(q);
		float strata = sin((q.x + q.y * 0.65 - q.z * 0.45) * 2.4 + warp * 5.2);
		float band = 0.5 + 0.5 * strata;
		float vein = pow(1.0 - abs(strata), 6.0);
		vec3 col = mix(sample_color(band * 0.85 + warp * 0.15), vec3(0.97, 0.96, 0.94), vein * 0.7);
		ALBEDO = col * shad;
		METALLIC = material_metallic;
		ROUGHNESS = clamp(material_roughness * (1.0 - vein * 0.5), 0.02, 1.0);
		SPECULAR = 0.6;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = (col * 0.35 + vec3(vein * 0.65)) * material_emission * ao;
	} else if (material_mode == 9) {
		// UVW Grid: 3D volumetric checkerboard + glowing XYZ coordinate lattice.
		vec3 g = uvw * (4.0 * uvw_scale);
		vec3 cell = floor(g);
		float checker = mod(cell.x + cell.y + cell.z, 2.0);
		vec3 f = abs(fract(g) - 0.5);
		float line = 1.0 - smoothstep(0.03, 0.08, min(min(f.x, f.y), f.z));
		vec3 base = mix(vec3(0.09, 0.10, 0.13), vec3(0.20, 0.23, 0.28), checker);
		vec3 line_col = sample_color(radial_distance * 0.7 + (cell.x + cell.y + cell.z) * 0.08);
		ALBEDO = mix(base, line_col, line) * shad;
		METALLIC = material_metallic;
		ROUGHNESS = mix(material_roughness, 0.1, line);
		SPECULAR = 0.5;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = line_col * line * material_emission * ao;
	} else if (material_mode == 10) {
		// UVW Contours: crisp concentric 3D shells by distance from origin.
		float shells = radial_distance * (6.0 * uvw_scale);
		float shell_idx = floor(shells) / max(6.0 * uvw_scale, 1.0);
		float frac_r = fract(shells);
		float ring = 1.0 - smoothstep(0.06, 0.14, min(frac_r, 1.0 - frac_r));
		vec3 shell_col = sample_color(shell_idx);
		vec3 ring_col = mix(shell_col, vec3(1.0), 0.55);
		ALBEDO = mix(shell_col * 0.65, ring_col, ring) * shad;
		METALLIC = material_metallic;
		ROUGHNESS = mix(material_roughness, 0.12, ring);
		SPECULAR = 0.55;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = ring_col * ring * material_emission * ao;
	} else if (material_mode == 11) {
		// UVW Opal: 3D noise interference + view-angle thin-film iridescence.
		vec3 q = uvw * (3.2 * uvw_scale);
		float n1 = fbm3(q);
		float n2 = noise3(q * 2.7 + vec3(n1 * 3.0));
		float spec_shift = n1 * 0.8 + n2 * 0.5 + fres * 0.45;
		vec3 fire = sample_color(spec_shift);
		vec3 body = mix(vec3(0.04, 0.06, 0.09), fire, smoothstep(0.35, 0.72, n2));
		ALBEDO = body * shad;
		METALLIC = material_metallic;
		ROUGHNESS = material_roughness;
		SPECULAR = 0.85;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = fire * (0.25 + fres * 0.75) * smoothstep(0.30, 0.75, n2) * material_emission * ao;
	} else if (material_mode == 12) {
		// UVW Voronoi: 3D cellular crystal facets & glowing boundary veins.
		vec2 vor = voronoi3(uvw * (3.5 * uvw_scale));
		float crack = 1.0 - smoothstep(0.02, 0.075, vor.x);
		vec3 cell_col = sample_color(vor.y + radial_distance * 0.35);
		ALBEDO = mix(cell_col * 0.7, vec3(0.95), crack * 0.4) * shad;
		METALLIC = material_metallic;
		ROUGHNESS = mix(material_roughness, 0.08, crack);
		SPECULAR = 0.7;
		AO = ao;
		AO_LIGHT_AFFECT = 0.7;
		EMISSION = cell_col * (0.15 + crack * 1.15) * material_emission * ao;
	} else {
		// Glow: emissive palette (the default look).
		vec3 col = pal * (0.45 + fres * 0.75) + glow_color * fres * 0.65;
		ALBEDO = vec3(0.0);
		EMISSION = col * material_emission * ao * mix(1.0, shad, 0.35);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	}

	// Write correct depth so the floor and controllers occlude the fractal.
	// In Godot Forward+ multiview, PROJECTION_MATRIX already encodes the per-eye
	// offset relative to central VIEW_MATRIX space (matching scene_forward_clustered.glsl).
	vec3 hit_world = (MODEL_MATRIX * vec4(p_obj, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hit_world, 1.0);
	DEPTH = clip.z / clip.w;
}
