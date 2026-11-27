extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var panel: Control = scene.get_node_or_null("HUD/ExplorerPanel")
	if panel == null or not panel.visible:
		push_error("Expected a visible desktop panel for fractal and material controls")
		quit(1)
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		push_error("Mouse must be visible on desktop so the controls can be clicked immediately")
		quit(1)
		return

	var active: MeshInstance3D = get_first_node_in_group("fractal_controller")
	var material: ShaderMaterial = active.get_surface_override_material(0)
	var next_material := _find_button(panel, "Next material")
	var previous_material := _find_button(panel, "Previous material")
	var roughness := _find_slider(panel, "Roughness")
	var metalness := _find_slider(panel, "Metalness")
	var emission := _find_slider(panel, "Emission")
	if next_material == null or previous_material == null or roughness == null or metalness == null or emission == null:
		push_error("Expected material selection and roughness, metalness, emission sliders")
		quit(1)
		return

	next_material.pressed.emit() # Plastic
	await process_frame
	if material.get_shader_parameter("material_mode") != 1:
		push_error("Material selector did not choose Plastic")
		quit(1)
		return

	roughness.value = 0.8
	metalness.value = 0.4
	emission.value = 0.8
	await process_frame
	if not _near(material.get_shader_parameter("material_roughness"), 0.8) \
			or not _near(material.get_shader_parameter("material_metallic"), 0.4) \
			or not _near(material.get_shader_parameter("material_emission"), 0.8):
		push_error("Material sliders did not update the shader")
		quit(1)
		return

	next_material.pressed.emit() # Metal
	previous_material.pressed.emit() # Return to Plastic
	await process_frame
	if not _near(material.get_shader_parameter("material_roughness"), 0.8) \
			or not _near(material.get_shader_parameter("material_metallic"), 0.4) \
			or not _near(material.get_shader_parameter("material_emission"), 0.8):
		push_error("Material edits were lost when switching presets")
		quit(1)
		return
	print("PASS: material controls edit the shader and retain each preset's settings")

	var settings := {
		"Detail": ["iterations", 12.0],
		"Shape": ["shape", 1.5],
		"Animation speed": ["morph_speed", 0.6],
		"Size": ["fractal_extent", 1.4],
		"Quality": ["max_steps", 120.0],
	}
	for label in settings:
		var slider := _find_slider(panel, label)
		if slider == null:
			push_error("Missing fractal slider: %s" % label)
			quit(1)
			return
		slider.value = settings[label][1]
		await process_frame
		if not _near(material.get_shader_parameter(settings[label][0]), settings[label][1]):
			push_error("Fractal slider %s did not update the shader" % label)
			quit(1)
			return
	print("PASS: desktop fractal sliders update the shader")
	quit(0)


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.02


func _find_button(node: Node, hint: String) -> Button:
	if node is Button and node.tooltip_text == hint:
		return node
	for child in node.get_children():
		var result := _find_button(child, hint)
		if result != null:
			return result
	return null


func _find_slider(node: Node, hint: String) -> HSlider:
	if node is HSlider and node.tooltip_text == hint:
		return node
	for child in node.get_children():
		var result := _find_slider(child, hint)
		if result != null:
			return result
	return null
