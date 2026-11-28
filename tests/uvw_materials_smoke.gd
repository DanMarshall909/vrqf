extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("uvw_materials_smoke.gd must run on a real GPU renderer (without --headless)")
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

	# Switch to Mandelbulb (type 1) with frozen animation for clean, consistent captures.
	active.call("CycleFractal", 1)
	material.set_shader_parameter("morph", 0.0)
	material.set_shader_parameter("morph_speed", 0.0)
	material.set_shader_parameter("shape", 0.0)
	material.set_shader_parameter("iterations", 8)

	# Verify Hue cycles slider reaches up to 8.0 (e.g. 6.0).
	var desktop_tabs: TabContainer = scene.get_node("HUD/ExplorerPanel/Tabs")
	var hue_cycles := _find_slider(desktop_tabs.get_node("Material"), "Hue cycles")
	if hue_cycles == null or hue_cycles.max_value < 8.0:
		push_error("Expected Hue cycles slider max_value >= 8.0, got %s" % [hue_cycles.max_value if hue_cycles else null])
		quit(1)
		return
	hue_cycles.value = 6.0
	await _render_frames(1)
	if absf(float(material.get_shader_parameter("radial_hue_cycles")) - 6.0) > 0.02:
		push_error("Hue cycles slider did not reach 6.0")
		quit(1)
		return
	hue_cycles.value = 1.0

	var wrist: Node = scene.get_node("XROrigin3D/LeftController/WristMenu")
	var wrist_tabs := _find_tabs(wrist)
	var wrist_mat_tab := wrist_tabs.get_node("Material")
	wrist_tabs.current_tab = wrist_tabs.get_tab_idx_from_control(wrist_mat_tab)
	var roughness_slider := _find_slider(desktop_tabs.get_node("Material"), "Roughness")
	var metalness_slider := _find_slider(desktop_tabs.get_node("Material"), "Metalness")

	var expected_uvw := [
		["UVW RGB", "uvw_rgb.png"],
		["UVW Marble", "uvw_marble.png"],
		["UVW Grid", "uvw_grid.png"],
		["UVW Contours", "uvw_contours.png"],
		["UVW Opal", "uvw_opal.png"],
		["UVW Voronoi", "uvw_voronoi.png"],
	]

	# Cycle through all materials from 0 to verify 13 total and find each UVW mode.
	var seen_names: Array[String] = []
	for _i in 13:
		seen_names.append(str(active.get("MaterialName")))
		active.call("CycleMaterial", 1)
	if str(active.get("MaterialName")) != seen_names[0]:
		push_error("Expected 13 material modes wrapping back to %s, got %s" % [seen_names[0], active.get("MaterialName")])
		quit(1)
		return
	for entry in expected_uvw:
		if not seen_names.has(entry[0]):
			push_error("Missing UVW material %s in %s" % [entry[0], seen_names])
			quit(1)
			return
	print("PASS: all 6 3D UVW material modes registered (13 total materials)")

	var capture_dir := OS.get_environment("VRQF_CAPTURE_DIR")
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)

	var images := {}
	for i in expected_uvw.size():
		var target_name: String = expected_uvw[i][0]
		var target_file: String = expected_uvw[i][1]
		var guard := 0
		while str(active.get("MaterialName")) != target_name and guard < 15:
			active.call("CycleMaterial", 1)
			guard += 1
		if str(active.get("MaterialName")) != target_name:
			push_error("Could not select %s" % target_name)
			quit(1)
			return
		await _render_frames(2)

		if not bool(active.get("MaterialSupportsSurfaceParams")) \
				or not roughness_slider.editable or not metalness_slider.editable:
			push_error("Expected surface params editable for %s" % target_name)
			quit(1)
			return

		var wrist_mat_label := _find_selector_value(wrist_mat_tab, "Material")
		if wrist_mat_label == null or not _text_fits(wrist_mat_label) or not _inside_viewport(wrist_mat_label):
			push_error("Material name %s does not fit wrist menu selector" % target_name)
			quit(1)
			return

		var img := root.get_texture().get_image()
		if not capture_dir.is_empty():
			img.save_png(capture_dir.path_join(target_file))
		var stats := _measure_crop(img)
		if not stats["finite"] or stats["non_flat_count"] < 200 or stats["chroma_var"] < 0.0005:
			push_error("UVW material %s failed visual variance check: %s" % [target_name, stats])
			quit(1)
			return
		images[target_name] = img

	var diff_rgb_contours := _mean_rgb_diff(images["UVW RGB"], images["UVW Contours"])
	var diff_rgb_grid := _mean_rgb_diff(images["UVW RGB"], images["UVW Grid"])
	var diff_contours_grid := _mean_rgb_diff(images["UVW Contours"], images["UVW Grid"])
	if diff_rgb_contours < 0.02 or diff_rgb_grid < 0.02 or diff_contours_grid < 0.02:
		push_error("UVW modes are not visually distinct (diffs: %.4f, %.4f, %.4f)" % [diff_rgb_contours, diff_rgb_grid, diff_contours_grid])
		quit(1)
		return

	print("PASS: all 6 UVW materials support surface params, fit VR UI, and render distinct 3D colours")
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
	var non_flat := 0
	var bg := img.get_pixel(int(w * 0.1), int(h * 0.1))
	var colors: Array[Color] = []
	var sum := Vector3.ZERO
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var c := img.get_pixel(x, y)
			if is_nan(c.r) or is_nan(c.g) or is_nan(c.b) or is_inf(c.r) or is_inf(c.g) or is_inf(c.b):
				return {"finite": false, "non_flat_count": 0, "chroma_var": 0.0}
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.08:
				non_flat += 1
				colors.append(c)
				sum += Vector3(c.r, c.g, c.b)
	var mean := sum / maxf(float(colors.size()), 1.0)
	var var_sum := 0.0
	for c in colors:
		var d := Vector3(c.r, c.g, c.b) - mean
		var_sum += d.length_squared()
	return {
		"finite": true,
		"non_flat_count": non_flat,
		"chroma_var": var_sum / maxf(float(colors.size()), 1.0),
	}


func _mean_rgb_diff(a: Image, b: Image) -> float:
	var w := a.get_width()
	var h := a.get_height()
	var x0 := int(w * 0.35)
	var x1 := int(w * 0.65)
	var y0 := int(h * 0.35)
	var y1 := int(h * 0.65)
	var diff := 0.0
	var count := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			diff += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			count += 1
	return diff / maxf(float(count), 1.0)


func _inside_viewport(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	var viewport_rect := control.get_viewport().get_visible_rect()
	return viewport_rect.encloses(rect)


func _text_fits(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	return width <= label.size.x


func _find_slider(node: Node, hint: String) -> HSlider:
	if node is HSlider and node.tooltip_text == hint:
		return node
	for child in node.get_children():
		var found := _find_slider(child, hint)
		if found != null:
			return found
	return null


func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for child in node.get_children():
		var found := _find_tabs(child)
		if found != null:
			return found
	return null


func _find_selector_value(node: Node, title: String) -> Label:
	if node is HBoxContainer and node.get_child_count() == 4:
		var first := node.get_child(0)
		if first is Label and first.text == title and node.get_child(2) is Label:
			return node.get_child(2)
	for child in node.get_children():
		var found := _find_selector_value(child, title)
		if found != null:
			return found
	return null
