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
//   0 = Glow (emissive palette)       4 = Matcap chrome
//   1 = Plastic (lit, palette)        5 = Matcap gold
//   2 = Metal  (reflective)           6 = Matcap pearl
//   3 = Glass  (fresnel/reflective)
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
uniform float radial_hue_cycles : hint_range(0.25, 4.0) = 1.0;
uniform float radial_hue_offset : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.6, 0.85, 1.0);
uniform float mesh_half = 0.15;      // proxy sphere radius (object space)
uniform float fractal_extent = 1.0;  // global size multiplier (1 = auto-fit per fractal)
uniform float boundary_eps = 0.003;  // trim hits on the box shell (kills edge lines)
uniform float ao_strength : hint_range(0.0, 1.0) = 0.75;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec3 shadow_light_dir = vec3(0.353553, 0.707107, 0.612372);

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

float qjulia_de(vec3 pos, vec4 c, out float trap) {
	vec4 z = vec4(pos, 0.0);
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

float qmandel_de(vec3 pos, vec4 c_offset, out float trap) {
	vec4 c = vec4(pos, 0.0) + c_offset;
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

float mandelbulb_de(vec3 pos, float power, out float trap) {
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
		float zr = pow(r, power);
		theta *= power;
		phi *= power;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / max(dr, 1e-6);
}

float burningship_de(vec3 pos, float power, out float trap) {
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
		float zr = pow(r, power);
		theta *= power;
		phi *= power;
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

float menger_de(vec3 p, float ratio, out float trap) {
	float d = box_de(p, vec3(1.0));
	float s = 1.0;
	int iters = min(iterations, 10);
	for (int i = 0; i < iters; i++) {
		vec3 a = mod(p * s, 2.0) - 1.0;
		s *= ratio;
		vec3 r = abs(1.0 - ratio * abs(a));
		float da = max(r.x, r.y);
		float db = max(r.y, r.z);
		float dc = max(r.z, r.x);
		float c = (min(da, min(db, dc)) - 1.0) / s;
		d = max(d, c);
	}
	trap = clamp(length(p) * 0.6, 0.0, 1.0);
	return d;
}

float sierpinski_de(vec3 z, float scale, out float trap) {
	int iters = min(iterations, 20);
	for (int i = 0; i < iters; i++) {
		if (z.x + z.y < 0.0) z.xy = -z.yx;
		if (z.x + z.z < 0.0) z.xz = -z.zx;
		if (z.y + z.z < 0.0) z.zy = -z.yz;
		z = z * scale - vec3(1.0) * (scale - 1.0);
	}
	trap = clamp(length(z) * 0.25, 0.0, 1.0);
	return length(z) * pow(scale, -float(iters));
}

float mandelbox_de(vec3 pos, float box_scale, out float trap) {
	vec4 z = vec4(pos, 1.0);
	float orbit = 1e9;
	int iters = min(iterations, 24);
	for (int i = 0; i < iters; i++) {
		if (length(z.xyz) > 6.0 || abs(z.w) > 1e12) break;
		z.xyz = clamp(z.xyz, -1.0, 1.0) * 2.0 - z.xyz;   // box fold
		float r2 = dot(z.xyz, z.xyz);
		if (r2 < 0.25) z *= 4.0;                          // sphere fold (1.0 / 0.25)
		else if (r2 < 1.0) z *= 1.0 / r2;
		z = z * box_scale + vec4(pos, 0.0);
		orbit = min(orbit, r2);
	}
	trap = clamp(sqrt(orbit) * 0.5, 0.0, 1.0);
	return length(z.xyz) / max(abs(z.w), 1e-6);
}

float tricorn_de(vec3 pos, float power, out float trap) {
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
		float zr = pow(r, power);
		theta *= power; phi *= power;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / max(dr, 1e-6);
}

float nova_de(vec3 pos, vec3 c_off, out float trap) {
	vec3 z = pos;
	vec3 dz = vec3(1.0, 0.0, 0.0);
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		if (dot(z, z) > 16.0 || dot(dz, dz) > 1e12) break;
		vec3 z2 = z * z;
		vec3 z3 = z2 * z;
		dz = 3.0 * z2 * dz;
		z = z - (z3 - vec3(1.0)) / (3.0 * z2 + vec3(1e-4)) + c_off; // Newton step + constant
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.6, 0.0, 1.0);
	return 0.4 * length(z) / max(length(dz), 1e-6);
}

// Apollonian gasket via repeated cell-folding + inversion (after iq).
float apollonian_de(vec3 p, float k, out float trap) {
	float scale = 1.0;
	vec3 z = p;
	float orbit = 1e9;
	int iters = min(iterations, 16);
	for (int i = 0; i < iters; i++) {
		z = -1.0 + 2.0 * fract(0.5 * z + 0.5);
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
float kifs_de(vec3 z, float ang, out float trap) {
	float scale = 2.0;
	float orbit = 1e9;
	int iters = min(iterations, 20);
	for (int i = 0; i < iters; i++) {
		z.xy = rot2(z.xy, ang);
		z = abs(z);
		if (z.x < z.y) z.xy = z.yx;
		if (z.x < z.z) z.xz = z.zx;
		if (z.y < z.z) z.yz = z.zy;
		z.yz = rot2(z.yz, ang * 0.7);
		z = z * scale - vec3(1.0) * (scale - 1.0);
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.3, 0.0, 1.0);
	return length(z) * pow(scale, -float(iters));
}

// Octahedral IFS (abs + sort fold).
float octahedral_de(vec3 z, float s, out float trap) {
	float orbit = 1e9;
	int iters = min(iterations, 20);
	for (int i = 0; i < iters; i++) {
		z = abs(z);
		if (z.x < z.y) z.xy = z.yx;
		if (z.x < z.z) z.xz = z.zx;
		if (z.y < z.z) z.yz = z.zy;
		z = z * s - vec3(1.0) * (s - 1.0);
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.3, 0.0, 1.0);
	return length(z) * pow(s, -float(iters));
}

// Gyroid triply-periodic minimal surface (thickened isosurface).
float gyroid_de(vec3 p, float s, out float trap) {
	vec3 q = p * s;
	float f = dot(sin(q), cos(q.yzx));
	trap = clamp(abs(f), 0.0, 1.0);
	return (abs(f) - 0.2) * 0.3 / s;
}

// Schwarz-P triply-periodic minimal surface (thickened isosurface).
float schwarz_de(vec3 p, float s, out float trap) {
	vec3 q = p * s;
	float f = cos(q.x) + cos(q.y) + cos(q.z);
	trap = clamp(abs(f) * 0.3, 0.0, 1.0);
	return (abs(f) - 0.2) * 0.3 / s;
}

// Cubic quaternion Julia: z = z^3 + c.
float qjulia3_de(vec3 pos, vec4 c, out float trap) {
	vec4 z = vec4(pos, 0.0);
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

// Distance estimator for one fractal. `shape` (scrubbed) sets its defining
// parameter and `anim` (= TIME * morph_speed) oscillates it so it animates.
float de(int type, vec3 p, float anim, out float trap) {
	if (type == 1) return mandelbulb_de(p, clamp(8.0 + 4.0 * sin(shape) + sin(anim), 2.0, 12.0), trap);
	if (type == 2) return qmandel_de(p, 0.18 * vec4(sin(shape), cos(shape * 0.9), sin(anim), cos(anim * 0.8)), trap);
	if (type == 3) return menger_de(p, 3.0 + 0.6 * sin(shape) + 0.15 * sin(anim), trap);
	if (type == 4) return sierpinski_de(p, 2.0 + 0.28 * sin(shape) + 0.05 * sin(anim), trap);
	if (type == 5) return burningship_de(p, clamp(8.0 + 4.0 * sin(shape) + sin(anim), 2.0, 12.0), trap);
	if (type == 6) return mandelbox_de(p, 2.0 + 0.5 * sin(shape) + 0.1 * sin(anim), trap);
	if (type == 7) return tricorn_de(p, clamp(8.0 + 4.0 * sin(shape) + sin(anim), 2.0, 12.0), trap);
	if (type == 8) return nova_de(p, 0.3 * vec3(cos(shape), sin(shape * 0.9), cos(shape * 1.3)) + 0.1 * vec3(sin(anim)), trap);
	if (type == 9) return apollonian_de(p, 1.0 + 0.25 * sin(shape), trap);
	if (type == 10) return kifs_de(p, 0.4 + 0.3 * sin(shape) + 0.1 * sin(anim), trap);
	if (type == 11) return octahedral_de(p, 2.0 + 0.3 * sin(shape), trap);
	if (type == 12) return gyroid_de(p, 3.0 + 1.0 * sin(shape) + 0.3 * sin(anim), trap);
	if (type == 13) return schwarz_de(p, 3.0 + 1.0 * sin(shape), trap);
	if (type == 14) return mandelbulb_de(p, clamp(3.0 + 1.5 * sin(shape) + 0.5 * sin(anim), 2.0, 6.0), trap);
	if (type == 15) {
		vec4 c3 = 0.4 * vec4(cos(shape), sin(shape * 0.9), cos(shape * 1.3), sin(shape * 0.5))
			+ 0.1 * vec4(sin(anim), cos(anim), sin(anim * 1.3), cos(anim * 0.7));
		return qjulia3_de(p, c3, trap);
	}
	// 0 = Quaternion Julia: shape sweeps the c constant, anim wobbles it.
	vec4 c = 0.5 * vec4(cos(shape), sin(shape * 0.9), cos(shape * 1.3), sin(shape * 0.5))
		+ 0.12 * vec4(sin(anim), cos(anim * 0.8), sin(anim * 1.2), cos(anim * 0.6));
	return qjulia_de(p, c, trap);
}

float fractal_scale(int type) {
	return fractal_radius(type) / (max(fractal_extent, 0.01) * mesh_half);
}

// Blend the active fractal toward morph_target by `morph` in object space so
// fractals with different canonical domain radii stay properly framed.
float map_obj(vec3 p_obj, float anim, out float trap) {
	float sA = fractal_scale(fractal_type);
	float dA = de(fractal_type, p_obj * sA, anim, trap) / sA;
	if (morph <= 0.001) return dA; // common case: one evaluation
	float tB;
	float sB = fractal_scale(morph_target);
	float dB = de(morph_target, p_obj * sB, anim, tB) / sB;
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
		float d = map_obj(ro + l_dir_obj * t, anim, trap);
		if (d < epsilon * 0.5) return 0.2;
		res = min(res, 6.0 * d / t);
		t += clamp(d, 0.01 * mesh_half, 0.12 * mesh_half);
		if (t > max_t) break;
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

	// Sample a 1D hue texture by 3D distance from the fractal centre.
	// Object-space position keeps the colours fixed as the camera moves.
	float radial_distance = clamp(length(p_obj) / mesh_half, 0.0, 1.0);
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
	} else {
		// Glow: emissive palette (the default look).
		vec3 col = pal * (0.45 + fres * 0.75) + glow_color * fres * 0.65;
		ALBEDO = vec3(0.0);
		EMISSION = col * material_emission * ao * mix(1.0, shad, 0.35);
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	}

	// Write correct per-eye depth so the floor and controllers occlude the fractal.
	vec3 hit_world = (MODEL_MATRIX * vec4(p_obj, 1.0)).xyz;
	vec4 hit_view = VIEW_MATRIX * vec4(hit_world, 1.0);
	hit_view.xyz -= EYE_OFFSET;
	vec4 clip = PROJECTION_MATRIX * hit_view;
	DEPTH = clip.z / clip.w;
}
