// Raymarched 3D fractal explorer, rendered inside the box volume.
//
// This runs on the Cube MeshInstance3D, so the fractal is anchored exactly
// where the box sits in world space. Working entirely in object space (and
// letting Godot's transform pipeline do the rest) is what keeps it in the
// correct position from every viewpoint as the player moves or turns.
//
// fractal_type selects the formula:
//   0 = Quaternion Julia (animated)   3 = Menger sponge
//   1 = Mandelbulb (power 8)          4 = Sierpinski tetrahedron
//   2 = Quaternion Mandelbrot         5 = Burning ship (3D)
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

uniform int fractal_type = 0;
uniform int max_steps = 96;
uniform int iterations = 8;
uniform float epsilon = 0.0012;
uniform vec4 julia_c = vec4(-0.45, -0.3, -0.5, 0.2);
uniform float morph_speed = 0.25;
uniform float morph_amount = 0.18;
uniform vec3 color_a : source_color = vec3(0.18, 0.45, 0.95);
uniform vec3 color_b : source_color = vec3(0.98, 0.35, 0.7);
uniform vec3 glow_color : source_color = vec3(0.6, 0.85, 1.0);
uniform float mesh_half = 0.15;      // BoxMesh half-extent (size 0.3 -> 0.15)
uniform float fractal_extent = 1.3;  // fractal half-size the box maps to

varying vec3 v_cam_local;   // camera position in object space
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

float qmandel_de(vec3 pos, out float trap) {
	vec4 c = vec4(pos, 0.0);
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

float menger_de(vec3 p, out float trap) {
	float d = box_de(p, vec3(1.0));
	float s = 1.0;
	for (int i = 0; i < iterations; i++) {
		vec3 a = mod(p * s, 2.0) - 1.0;
		s *= 3.0;
		vec3 r = abs(1.0 - 3.0 * abs(a));
		float da = max(r.x, r.y);
		float db = max(r.y, r.z);
		float dc = max(r.z, r.x);
		float c = (min(da, min(db, dc)) - 1.0) / s;
		d = max(d, c);
	}
	trap = clamp(length(p) * 0.6, 0.0, 1.0);
	return d;
}

float sierpinski_de(vec3 z, out float trap) {
	float scale = 2.0;
	for (int i = 0; i < iterations; i++) {
		if (z.x + z.y < 0.0) z.xy = -z.yx;
		if (z.x + z.z < 0.0) z.xz = -z.zx;
		if (z.y + z.z < 0.0) z.zy = -z.yz;
		z = z * scale - vec3(1.0) * (scale - 1.0);
	}
	trap = clamp(length(z) * 0.25, 0.0, 1.0);
	return length(z) * pow(scale, -float(iterations));
}

float map(vec3 p, vec4 c, out float trap) {
	if (fractal_type == 1) return mandelbulb_de(p, 8.0, trap);
	if (fractal_type == 2) return qmandel_de(p, trap);
	if (fractal_type == 3) return menger_de(p, trap);
	if (fractal_type == 4) return sierpinski_de(p, trap);
	if (fractal_type == 5) return burningship_de(p, 8.0, trap);
	return qjulia_de(p, c, trap);
}

vec3 calc_normal(vec3 p, vec4 c) {
	float h = 0.0008;
	vec2 k = vec2(1.0, -1.0);
	float t;
	return normalize(
		k.xyy * map(p + k.xyy * h, c, t) +
		k.yyx * map(p + k.yyx * h, c, t) +
		k.yxy * map(p + k.yxy * h, c, t) +
		k.xxx * map(p + k.xxx * h, c, t)
	);
}

// Ray vs axis-aligned box [-b, b]. Returns false if the ray misses.
bool ray_box(vec3 ro, vec3 rd, float b, out float t_near, out float t_far) {
	vec3 inv = 1.0 / rd;
	vec3 n = inv * ro;
	vec3 k = abs(inv) * vec3(b);
	vec3 t1 = -n - k;
	vec3 t2 = -n + k;
	t_near = max(max(t1.x, t1.y), t1.z);
	t_far = min(min(t2.x, t2.y), t2.z);
	return t_near <= t_far && t_far > 0.0;
}

void vertex() {
	v_frag_local = VERTEX;
	v_cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	// Ray in object space.
	vec3 ro = v_cam_local;
	vec3 rd = normalize(v_frag_local - v_cam_local);

	float t_near, t_far;
	if (!ray_box(ro, rd, mesh_half, t_near, t_far)) {
		discard;
	}
	t_near = max(t_near, 0.0); // start at the camera if it is inside the box

	// Object -> fractal domain scale.
	float scale = fractal_extent / mesh_half;

	// Animate the Julia constant (only used by the quaternion Julia set).
	vec4 c = julia_c + morph_amount * vec4(
		sin(TIME * morph_speed),
		cos(TIME * morph_speed * 0.7),
		sin(TIME * morph_speed * 1.3),
		cos(TIME * morph_speed * 0.5)
	);

	// Sphere-trace through the box.
	float t = t_near;
	bool hit = false;
	float trap = 0.0;
	vec3 p_obj = ro;
	for (int i = 0; i < max_steps; i++) {
		p_obj = ro + rd * t;
		float d = map(p_obj * scale, c, trap) / scale; // DE back in object units
		if (d < epsilon) { hit = true; break; }
		t += d;
		if (t > t_far) break;
	}

	if (!hit) {
		discard;
	}

	// Shading (object-space normal, lit by a fixed key + fresnel rim).
	vec3 n = calc_normal(p_obj * scale, c);
	vec3 light_dir = normalize(vec3(0.4, 0.8, 0.5));
	float diff = clamp(dot(n, light_dir), 0.0, 1.0);
	float ambient = 0.25;
	float fres = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);

	vec3 base = mix(color_a, color_b, trap);
	vec3 col = base * (ambient + diff * 0.9) + glow_color * fres * 0.6;

	ALBEDO = col;
	EMISSION = col * (0.35 + fres * 0.5);

	// Write correct depth so the floor and controllers occlude the fractal.
	vec3 hit_world = (MODEL_MATRIX * vec4(p_obj, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hit_world, 1.0);
	DEPTH = clip.z / clip.w;
}
