// Raymarched 3D fractal explorer, rendered inside the box volume.
//
// This runs on the Cube MeshInstance3D, so the fractal is anchored exactly
// where the box sits in world space. Working entirely in object space (and
// letting Godot's transform pipeline do the rest) is what keeps it in the
// correct position from every viewpoint as the player moves or turns.
//
// fractal_type / morph_target select the formula (morph blends between them):
//   0 = Quaternion Julia    3 = Menger sponge   6 = Mandelbox
//   1 = Mandelbulb          4 = Sierpinski      7 = Tricorn (3D)
//   2 = Quaternion Mandel   5 = Burning ship    8 = Nova (3D)
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
uniform int max_steps = 96;
uniform int iterations = 8;
uniform float epsilon = 0.0012;
uniform float morph_speed = 0.25;    // animation rate for ALL fractals (0 = frozen)
uniform float shape = 0.0;           // per-fractal shape parameter (scrubbed)
uniform sampler2D palette_tex : source_color, hint_default_white;
uniform vec3 glow_color : source_color = vec3(0.6, 0.85, 1.0);
uniform float mesh_half = 0.15;      // proxy sphere radius (object space)
uniform float fractal_extent = 1.0;  // global size multiplier (1 = auto-fit per fractal)
uniform float boundary_eps = 0.003;  // trim hits on the box shell (kills edge lines)

varying vec3 v_frag_local;  // this fragment's position in object space

// Hamilton product of two quaternions (w, x, y, z).
vec4 qmul(vec4 a, vec4 b) {
	return vec4(
		a.x * b.x - a.y * b.y - a.z * b.z - a.w * b.w,
		a.x * b.y + a.y * b.x + a.z * b.w - a.w * b.z,
		a.x * b.z - a.y * b.w + a.z * b.x + a.w * b.y,
		a.x * b.w + a.y * b.z - a.z * b.y + a.w * b.x
	);
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
		if (m2 > 256.0) break;
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
		if (m2 > 256.0) break;
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
		if (r > 2.0) break;
		float theta = acos(clamp(z.z / r, -1.0, 1.0));
		float phi = atan(z.y, z.x);
		dr = pow(r, power - 1.0) * power * dr + 1.0;
		float zr = pow(r, power);
		theta *= power;
		phi *= power;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / dr;
}

float burningship_de(vec3 pos, float power, out float trap) {
	vec3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		z = abs(z); // the "burning ship" fold
		r = length(z);
		if (r > 2.0) break;
		float theta = acos(clamp(z.z / r, -1.0, 1.0));
		float phi = atan(z.y, z.x);
		dr = pow(r, power - 1.0) * power * dr + 1.0;
		float zr = pow(r, power);
		theta *= power;
		phi *= power;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / dr;
}

float box_de(vec3 p, vec3 b) {
	vec3 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float menger_de(vec3 p, float ratio, out float trap) {
	float d = box_de(p, vec3(1.0));
	float s = 1.0;
	for (int i = 0; i < iterations; i++) {
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
	for (int i = 0; i < iterations; i++) {
		if (z.x + z.y < 0.0) z.xy = -z.yx;
		if (z.x + z.z < 0.0) z.xz = -z.zx;
		if (z.y + z.z < 0.0) z.zy = -z.yz;
		z = z * scale - vec3(1.0) * (scale - 1.0);
	}
	trap = clamp(length(z) * 0.25, 0.0, 1.0);
	return length(z) * pow(scale, -float(iterations));
}

float mandelbox_de(vec3 pos, float box_scale, out float trap) {
	vec4 z = vec4(pos, 1.0);
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		if (length(z.xyz) > 6.0) break;
		z.xyz = clamp(z.xyz, -1.0, 1.0) * 2.0 - z.xyz;   // box fold
		float r2 = dot(z.xyz, z.xyz);
		if (r2 < 0.25) z *= 4.0;                          // sphere fold (1.0 / 0.25)
		else if (r2 < 1.0) z *= 1.0 / r2;
		z = z * box_scale + vec4(pos, 0.0);
		orbit = min(orbit, r2);
	}
	trap = clamp(sqrt(orbit) * 0.5, 0.0, 1.0);
	return length(z.xyz) / abs(z.w);
}

float tricorn_de(vec3 pos, float power, out float trap) {
	vec3 z = pos;
	float dr = 1.0;
	float r = 0.0;
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		r = length(z);
		if (r > 2.0) break;
		z.y = -z.y; z.z = -z.z;                           // conjugate fold (tricorn)
		float theta = acos(clamp(z.z / r, -1.0, 1.0));
		float phi = atan(z.y, z.x);
		dr = pow(r, power - 1.0) * power * dr + 1.0;
		float zr = pow(r, power);
		theta *= power; phi *= power;
		z = zr * vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)) + pos;
		orbit = min(orbit, r);
	}
	trap = clamp(orbit * 0.5, 0.0, 1.0);
	return 0.5 * log(max(r, 1.0001)) * r / dr;
}

float nova_de(vec3 pos, vec3 c_off, out float trap) {
	vec3 z = pos;
	vec3 dz = vec3(1.0, 0.0, 0.0);
	float orbit = 1e9;
	for (int i = 0; i < iterations; i++) {
		if (dot(z, z) > 16.0) break;
		vec3 z2 = z * z;
		vec3 z3 = z2 * z;
		dz = 3.0 * z2 * dz;
		z = z - (z3 - vec3(1.0)) / (3.0 * z2 + vec3(1e-4)) + c_off; // Newton step + constant
		orbit = min(orbit, dot(z, z));
	}
	trap = clamp(sqrt(orbit) * 0.6, 0.0, 1.0);
	return 0.4 * length(z) / max(length(dz), 1e-6);
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
	// 0 = Quaternion Julia: shape sweeps the c constant, anim wobbles it.
	vec4 c = 0.5 * vec4(cos(shape), sin(shape * 0.9), cos(shape * 1.3), sin(shape * 0.5))
		+ 0.12 * vec4(sin(anim), cos(anim * 0.8), sin(anim * 1.2), cos(anim * 0.6));
	return qjulia_de(p, c, trap);
}

// Blend the active fractal toward morph_target by `morph` (a soft DE mix —
// not a true SDF union, but it morphs the surface convincingly).
float map(vec3 p, float anim, out float trap) {
	float dA = de(fractal_type, p, anim, trap);
	if (morph <= 0.001) return dA; // common case: one evaluation
	float tB;
	float dB = de(morph_target, p, anim, tB);
	trap = mix(trap, tB, morph);
	return mix(dA, dB, morph);
}

vec3 calc_normal(vec3 p, float anim) {
	float h = 0.0008;
	vec2 k = vec2(1.0, -1.0);
	float t;
	return normalize(
		k.xyy * map(p + k.xyy * h, anim, t) +
		k.yyx * map(p + k.yyx * h, anim, t) +
		k.yxy * map(p + k.yxy * h, anim, t) +
		k.xxx * map(p + k.xxx * h, anim, t)
	);
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
}

void fragment() {
	// Ray in object space. The eye position is taken from INV_VIEW_MATRIX
	// per-fragment so it is correct PER EYE under VR multiview — precomputing
	// it in the vertex stage (CAMERA_POSITION_WORLD) gives the mono/centre
	// camera and collapses the stereo, making the fractal look like it's
	// painted on the inside of the box.
	vec3 ro = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec3 rd = normalize(v_frag_local - ro);

	float t_near, t_far;
	if (!ray_sphere(ro, rd, mesh_half, t_near, t_far)) {
		discard;
	}
	t_near = max(t_near, 0.0); // start at the camera if it is inside the volume

	// Object -> fractal domain scale (per-fractal fit; radius blends while morphing).
	float radius = mix(fractal_radius(fractal_type), fractal_radius(morph_target), morph);
	float scale = radius * fractal_extent / mesh_half;

	// Animation phase shared by every fractal (morph_speed scales it; 0 = frozen).
	float anim = TIME * morph_speed;

	// Sphere-trace through the box.
	float t = t_near;
	bool hit = false;
	float trap = 0.0;
	vec3 p_obj = ro;
	for (int i = 0; i < max_steps; i++) {
		p_obj = ro + rd * t;
		float d = map(p_obj * scale, anim, trap) / scale; // DE back in object units
		if (d < epsilon) { hit = true; break; }
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
	vec3 n_obj = calc_normal(p_obj * scale, anim);
	vec3 n_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_obj, 0.0)).xyz);
	NORMAL = n_view;

	// Palette colour from the orbit trap.
	vec3 pal = texture(palette_tex, vec2(trap, 0.5)).rgb;
	float fres = pow(1.0 - clamp(dot(n_view, vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 3.0);

	if (material_mode == 1) {
		// Plastic: lit dielectric tinted by the palette.
		ALBEDO = pal;
		METALLIC = 0.0;
		ROUGHNESS = 0.35;
		SPECULAR = 0.5;
		EMISSION = pal * 0.05;
	} else if (material_mode == 2) {
		// Metal: reflects the real scene via ReflectionProbe + SSR.
		ALBEDO = mix(pal, vec3(1.0), 0.6);
		METALLIC = 1.0;
		ROUGHNESS = 0.08;
		SPECULAR = 0.5;
	} else if (material_mode == 3) {
		// Glass: smooth, strongly reflective dielectric (fresnel-driven).
		// Not true refraction — reflections only (see notes).
		ALBEDO = mix(pal * 0.2, vec3(1.0), fres);
		METALLIC = 0.0;
		ROUGHNESS = 0.02;
		SPECULAR = 1.0;
		EMISSION = glow_color * fres * 0.25;
	} else if (material_mode == 4) {
		// Matcap chrome.
		vec3 m = procedural_matcap(n_view, vec3(0.8, 0.85, 0.95), 24.0);
		ALBEDO = vec3(0.0);
		EMISSION = m;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	} else if (material_mode == 5) {
		// Matcap gold.
		vec3 m = procedural_matcap(n_view, vec3(1.0, 0.75, 0.3), 16.0);
		ALBEDO = vec3(0.0);
		EMISSION = m;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	} else if (material_mode == 6) {
		// Matcap pearl.
		vec3 m = procedural_matcap(n_view, mix(pal, vec3(0.95), 0.5), 8.0);
		ALBEDO = vec3(0.0);
		EMISSION = m;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	} else {
		// Glow: emissive palette (the default look).
		vec3 col = pal * (0.4 + fres * 0.6) + glow_color * fres * 0.5;
		ALBEDO = vec3(0.0);
		EMISSION = col;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
	}

	// Write correct depth so the floor and controllers occlude the fractal.
	vec3 hit_world = (MODEL_MATRIX * vec4(p_obj, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hit_world, 1.0);
	DEPTH = clip.z / clip.w;
}
