// Animated quaternion Julia set, raymarched inside the box volume.
//
// This runs on the Cube MeshInstance3D, so the fractal is anchored exactly
// where the box sits in world space. Working entirely in object space (and
// letting Godot's transform pipeline do the rest) is what keeps it in the
// correct position from every viewpoint as the player moves or turns.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

uniform int max_steps = 96;
uniform int julia_iterations = 8;
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

// Quaternion Julia distance estimator. Returns DE in 'de' and an orbit trap
// (closeness to the origin) in 'trap' for colouring.
float qjulia_de(vec3 pos, vec4 c, out float trap) {
	vec4 z = vec4(pos, 0.0);
	float dz2 = 1.0; // squared magnitude of the running derivative
	float m2 = dot(z, z);
	trap = 1e9;
	for (int i = 0; i < julia_iterations; i++) {
		// d/dz of z^2 is 2z, so |z'| accumulates as |2z| * |z'|.
		dz2 *= 4.0 * m2;
		z = qmul(z, z) + c;
		m2 = dot(z, z);
		trap = min(trap, m2);
		if (m2 > 256.0) break;
	}
	float r = sqrt(m2);
	// Analytic distance estimate for an escape-time set.
	return 0.25 * r * log(max(r, 1.0001)) / sqrt(max(dz2, 1e-12));
}

float map(vec3 p, vec4 c, out float trap) {
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

	// Animate the Julia constant.
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

	vec3 base = mix(color_a, color_b, clamp(sqrt(trap) * 1.4, 0.0, 1.0));
	vec3 col = base * (ambient + diff * 0.9) + glow_color * fres * 0.6;

	ALBEDO = col;
	EMISSION = col * (0.35 + fres * 0.5);

	// Write correct depth so the floor and controllers occlude the fractal.
	vec3 hit_world = (MODEL_MATRIX * vec4(p_obj, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(hit_world, 1.0);
	DEPTH = clip.z / clip.w;
}
