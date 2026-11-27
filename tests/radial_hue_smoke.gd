extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var fractal: MeshInstance3D = get_first_node_in_group("fractal_controller")
	var material: ShaderMaterial = fractal.get_surface_override_material(0)
	var radial_texture: GradientTexture1D = material.get_shader_parameter("radial_hue_tex")
	if radial_texture == null:
		push_error("The fractal material needs its radial hue texture")
		quit(1)
		return
	var inner := radial_texture.gradient.sample(0.0)
	var middle := radial_texture.gradient.sample(0.5)
	if inner.r < 0.9 or inner.g > 0.1 or middle.g < 0.9 or middle.b < 0.9:
		push_error("The radial texture must contain a changing hue gradient")
		quit(1)
		return
	var panel: Control = scene.get_node("HUD/ExplorerPanel")
	var colour_button := _find_button(panel, "Next colour source")
	var palette_button := _find_button(panel, "Next palette")
	var hue_cycles := _find_slider(panel, "Hue cycles")
	var hue_offset := _find_slider(panel, "Hue offset")
	if material.get_shader_parameter("color_mode") != 1 or colour_button == null \
			or palette_button == null or hue_cycles == null or hue_offset == null:
		push_error("The fractal must start with editable radial hue colouring")
		quit(1)
		return

	hue_cycles.value = 2.0
	hue_offset.value = 0.25
	await process_frame
	if not _near(material.get_shader_parameter("radial_hue_cycles"), 2.0) \
			or not _near(material.get_shader_parameter("radial_hue_offset"), 0.25):
		push_error("Desktop hue controls did not update the shader")
		quit(1)
		return

	colour_button.pressed.emit()
	await process_frame
	if material.get_shader_parameter("color_mode") != 0:
		push_error("Colour source selector did not restore orbit palette colouring")
		quit(1)
		return
	palette_button.pressed.emit()
	await process_frame
	if material.get_shader_parameter("color_mode") != 0:
		push_error("Choosing a palette must use orbit colouring")
		quit(1)
		return
	hue_cycles.value = 1.5
	await process_frame
	if material.get_shader_parameter("color_mode") != 1:
		push_error("Editing radial hue must make its effect visible")
		quit(1)
		return
	_send_key(KEY_C)
	await process_frame
	if material.get_shader_parameter("color_mode") != 0:
		push_error("C should switch to orbit palette colouring")
		quit(1)
		return
	_send_key(KEY_C)
	await process_frame
	if material.get_shader_parameter("color_mode") != 1:
		push_error("C should switch back to radial hue colouring")
		quit(1)
		return
	print("PASS: desktop radial hue controls update the colour shader")

	var wrist: Node = scene.get_node("XROrigin3D/LeftController/WristMenu")
	var tabs := _find_tabs(wrist)
	if tabs == null or tabs.get_node_or_null("Material") == null:
		push_error("Missing wrist material controls")
		quit(1)
		return
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("Material"))
	await process_frame
	var wrist_colour := _find_selector_next(tabs.get_node("Material"), "Colour")
	var wrist_cycles := _find_button(wrist, "Increase hue cycles")
	var wrist_offset := _find_button(wrist, "Increase hue offset")
	if wrist_colour == null or wrist_cycles == null or wrist_offset == null \
			or not _inside_viewport(wrist_colour) or not _inside_viewport(wrist_cycles) or not _inside_viewport(wrist_offset):
		push_error("Wrist hue controls must fit and be usable")
		quit(1)
		return
	wrist_colour.pressed.emit()
	await process_frame
	if material.get_shader_parameter("color_mode") != 0:
		push_error("Wrist colour selector did not switch to orbit palette")
		quit(1)
		return
	wrist_colour.pressed.emit()
	await process_frame
	if material.get_shader_parameter("color_mode") != 1:
		push_error("Wrist colour selector did not switch back to radial hue")
		quit(1)
		return
	wrist_cycles.pressed.emit()
	wrist_offset.pressed.emit()
	await process_frame
	if material.get_shader_parameter("radial_hue_cycles") <= 1.5 \
			or material.get_shader_parameter("radial_hue_offset") <= 0.25:
		push_error("Wrist hue controls did not update the shader")
		quit(1)
		return
	print("PASS: wrist radial hue controls fit and update the colour shader")
	quit(0)


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.02


func _send_key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = code
	release.pressed = false
	Input.parse_input_event(release)


func _inside_viewport(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	var viewport_rect := control.get_viewport().get_visible_rect()
	return viewport_rect.encloses(rect)


func _find_button(node: Node, hint: String) -> Button:
	if node is Button and node.tooltip_text == hint:
		return node
	for child in node.get_children():
		var found := _find_button(child, hint)
		if found != null:
			return found
	return null


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


func _find_selector_next(node: Node, title: String) -> Button:
	if node is HBoxContainer and node.get_child_count() == 4:
		var label := node.get_child(0)
		if label is Label and label.text == title and node.get_child(3) is Button:
			return node.get_child(3)
	for child in node.get_children():
		var found := _find_selector_next(child, title)
		if found != null:
			return found
	return null
