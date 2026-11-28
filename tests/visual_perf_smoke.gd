extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("visual_perf_smoke.gd must run on a real GPU renderer (without --headless)")
		quit(1)
		return

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _render_frames(2)

	var active: MeshInstance3D = get_first_node_in_group("fractal_controller")
	var material: ShaderMaterial = active.get_surface_override_material(0)
	active.set("AutoMorph", false)
	var hud := scene.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false

	var probe := scene.get_node_or_null("ReflectionProbe") as ReflectionProbe
	if probe == null or probe.update_mode != ReflectionProbe.UPDATE_ONCE:
		push_error("ReflectionProbe must use UPDATE_ONCE to avoid per-frame cubemap rebakes")
		quit(1)
		return

	var world_env := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		push_error("Missing WorldEnvironment")
		quit(1)
		return
	var env := world_env.environment
	if not env.glow_enabled or env.ssao_enabled or env.ssr_enabled:
		push_error("Expected glow_enabled=true, ssao_enabled=false, ssr_enabled=false (got glow=%s ssao=%s ssr=%s)" % [env.glow_enabled, env.ssao_enabled, env.ssr_enabled])
		quit(1)
		return
	print("PASS: scene performance and glow environment invariants hold")

	var ao_val = material.get_shader_parameter("ao_strength")
	var shadow_val = material.get_shader_parameter("shadow_strength")
	if ao_val == null or float(ao_val) <= 0.0 or shadow_val == null or float(shadow_val) <= 0.0:
		push_error("Expected positive ao_strength and shadow_strength uniforms, got ao=%s shadow=%s" % [ao_val, shadow_val])
		quit(1)
		return

	var capture_dir := OS.get_environment("VRQF_CAPTURE_DIR")
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)
		material.set_shader_parameter("fractal_type", 0)
		material.set_shader_parameter("material_mode", 0)
		material.set_shader_parameter("morph", 0.0)
		material.set_shader_parameter("morph_speed", 0.0)
		material.set_shader_parameter("shape", 0.0)
		await _render_frames(2)
		root.get_texture().get_image().save_png(capture_dir.path_join("glow_radial_hue.png"))

	# AO + soft shadow visual check on Plastic Mandelbulb.
	material.set_shader_parameter("fractal_type", 1)
	material.set_shader_parameter("material_mode", 1)
	material.set_shader_parameter("material_roughness", 0.35)
	material.set_shader_parameter("material_metallic", 0.0)
	material.set_shader_parameter("material_emission", 0.05)
	material.set_shader_parameter("morph", 0.0)
	material.set_shader_parameter("morph_speed", 0.0)
	material.set_shader_parameter("shape", 0.0)
	material.set_shader_parameter("iterations", 8)
	await _render_frames(2)
	var occluded_img := root.get_texture().get_image()
	if not capture_dir.is_empty():
		occluded_img.save_png(capture_dir.path_join("plastic_mandelbulb_ao.png"))
	var occluded_stats := _measure_crop(occluded_img)
	if not occluded_stats["finite"] or occluded_stats["non_flat_count"] < 200:
		push_error("Plastic Mandelbulb did not render valid non-empty fractal pixels: %s" % [occluded_stats])
		quit(1)
		return

	material.set_shader_parameter("ao_strength", 0.0)
	material.set_shader_parameter("shadow_strength", 0.0)
	await _render_frames(2)
	var unoccluded_img := root.get_texture().get_image()
	var unoccluded_stats := _measure_crop(unoccluded_img)
	if not unoccluded_stats["finite"]:
		push_error("Unoccluded Mandelbulb produced non-finite pixels")
		quit(1)
		return

	var occluded_mean: float = occluded_stats["mean_luma"]
	var unoccluded_mean: float = unoccluded_stats["mean_luma"]
	if occluded_mean >= unoccluded_mean - 0.005:
		push_error("Expected AO + soft shadow to darken crevices (occluded=%.4f vs unoccluded=%.4f)" % [occluded_mean, unoccluded_mean])
		quit(1)
		return
	print("PASS: raymarched AO and soft shadows darken fractal crevices (%.4f < %.4f)" % [occluded_mean, unoccluded_mean])

	material.set_shader_parameter("ao_strength", ao_val)
	material.set_shader_parameter("shadow_strength", shadow_val)

	if not capture_dir.is_empty():
		material.set_shader_parameter("fractal_type", 6)
		material.set_shader_parameter("material_mode", 2)
		material.set_shader_parameter("material_roughness", 0.08)
		material.set_shader_parameter("material_metallic", 1.0)
		material.set_shader_parameter("material_emission", 0.0)
		material.set_shader_parameter("iterations", 10)
		await _render_frames(2)
		root.get_texture().get_image().save_png(capture_dir.path_join("metal_mandelbox.png"))

	# Verify all 16 fractal types at Detail=64 produce finite, non-empty frames.
	material.set_shader_parameter("material_mode", 1)
	material.set_shader_parameter("material_roughness", 0.35)
	material.set_shader_parameter("material_metallic", 0.0)
	material.set_shader_parameter("material_emission", 0.1)
	material.set_shader_parameter("morph", 0.0)
	material.set_shader_parameter("iterations", 64)
	for ftype in 16:
		material.set_shader_parameter("fractal_type", ftype)
		await _render_frames(2)
		var stats := _measure_crop(root.get_texture().get_image())
		if not stats["finite"] or stats["non_flat_count"] < 100:
			push_error("Fractal type %d at iterations=64 failed sanity check: %s" % [ftype, stats])
			quit(1)
			return
	print("PASS: all 16 fractal types render finite non-empty pixels at iterations=64")

	# Verify cross-scale morph (Apollonian -> Mandelbox) stays framed and finite.
	material.set_shader_parameter("fractal_type", 9)
	material.set_shader_parameter("morph_target", 6)
	material.set_shader_parameter("morph", 0.5)
	material.set_shader_parameter("iterations", 10)
	await _render_frames(2)
	var morph_stats := _measure_crop(root.get_texture().get_image())
	if not morph_stats["finite"] or morph_stats["non_flat_count"] < 200:
		push_error("Cross-scale Apollonian->Mandelbox morph failed sanity check: %s" % [morph_stats])
		quit(1)
		return
	print("PASS: cross-scale Apollonian->Mandelbox morph renders finite framed pixels")
	quit(0)


func _render_frames(count: int) -> void:
	for _i in count:
		await process_frame
		await RenderingServer.frame_post_draw


func _measure_crop(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(w * 0.3)
	var x1 := int(w * 0.7)
	var y0 := int(h * 0.3)
	var y1 := int(h * 0.7)
	var sum := 0.0
	var count := 0
	var non_flat := 0
	var bg := img.get_pixel(int(w * 0.1), int(h * 0.1))
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var c := img.get_pixel(x, y)
			if is_nan(c.r) or is_nan(c.g) or is_nan(c.b) or is_inf(c.r) or is_inf(c.g) or is_inf(c.b):
				return {"finite": false, "mean_luma": 0.0, "non_flat_count": 0}
			var luma := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += luma
			count += 1
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.08:
				non_flat += 1
	return {
		"finite": true,
		"mean_luma": sum / maxf(float(count), 1.0),
		"non_flat_count": non_flat,
	}
