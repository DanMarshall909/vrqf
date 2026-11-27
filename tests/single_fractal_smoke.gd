extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var fractals: Array[MeshInstance3D] = []
	_collect_fractals(scene, fractals)
	if fractals.size() != 1:
		push_error("Expected one visible fractal mesh, found %d" % fractals.size())
		quit(1)
		return

	print("PASS: one fractal mesh in the main scene")
	var active: MeshInstance3D = get_first_node_in_group("fractal_controller")
	var material: ShaderMaterial = active.get_surface_override_material(0)
	var first_type: int = material.get_shader_parameter("fractal_type")
	var first_target: int = material.get_shader_parameter("morph_target")
	if first_type == first_target:
		push_error("Morph source and target must be different")
		quit(1)
		return

	await create_timer(0.4).timeout
	var progress: float = material.get_shader_parameter("morph")
	if progress <= 0.05 or progress >= 1.0:
		push_error("Expected the fractal to morph without input, got %.3f" % progress)
		quit(1)
		return

	await create_timer(3.2).timeout
	var new_type: int = material.get_shader_parameter("fractal_type")
	var new_target: int = material.get_shader_parameter("morph_target")
	if new_type != first_target or new_target == new_type:
		push_error("Expected morph to advance to the next distinct type, got %d -> %d" % [new_type, new_target])
		quit(1)
		return

	print("PASS: the single fractal morphs and advances without input")
	active.call("AdjustMorph", -0.2)
	var manual_amount: float = material.get_shader_parameter("morph")
	await create_timer(0.4).timeout
	var held_amount: float = material.get_shader_parameter("morph")
	if absf(held_amount - manual_amount) > 0.02:
		push_error("Manual morph amount did not stay in place: %.3f -> %.3f" % [manual_amount, held_amount])
		quit(1)
		return

	var resume_key := InputEventKey.new()
	resume_key.keycode = KEY_SPACE
	resume_key.pressed = true
	Input.parse_input_event(resume_key)
	var release_key := InputEventKey.new()
	release_key.keycode = KEY_SPACE
	release_key.pressed = false
	Input.parse_input_event(release_key)
	await create_timer(0.4).timeout
	var resumed_amount: float = material.get_shader_parameter("morph")
	if resumed_amount <= held_amount + 0.05:
		push_error("Auto morph did not resume after manual adjustment")
		quit(1)
		return

	print("PASS: manual morph holds until automatic morph resumes")
	var wrist_tabs := _find_wrist_tabs(scene.get_node("XROrigin3D/LeftController/WristMenu"))
	if wrist_tabs == null or wrist_tabs.get_node_or_null("Morph") == null:
		push_error("Expected a Morph tab on the wrist menu")
		quit(1)
		return
	wrist_tabs.current_tab = wrist_tabs.get_tab_idx_from_control(wrist_tabs.get_node("Morph"))
	await process_frame
	var auto_button := _find_auto_morph_button(scene)
	if auto_button == null or not auto_button.is_visible_in_tree():
		push_error("Expected a visible Auto morph button on the wrist menu")
		quit(1)
		return
	var button_rect := auto_button.get_global_rect()
	var menu_size := auto_button.get_viewport().get_visible_rect().size
	if button_rect.position.y < 0 or button_rect.end.y > menu_size.y:
		push_error("Auto morph button is outside the wrist menu viewport: %s in %s" % [button_rect, menu_size])
		quit(1)
		return

	auto_button.pressed.emit()
	var paused_amount: float = material.get_shader_parameter("morph")
	await create_timer(0.4).timeout
	if absf(material.get_shader_parameter("morph") - paused_amount) > 0.02:
		push_error("Wrist menu did not pause automatic morphing")
		quit(1)
		return

	auto_button.pressed.emit()
	await create_timer(0.4).timeout
	if material.get_shader_parameter("morph") <= paused_amount + 0.05:
		push_error("Wrist menu did not resume automatic morphing")
		quit(1)
		return

	print("PASS: wrist menu toggles automatic morphing")
	seed(42)
	for i in 100:
		active.call("Randomize")
		var source: int = material.get_shader_parameter("fractal_type")
		var target: int = material.get_shader_parameter("morph_target")
		if source == target:
			push_error("Randomized morph paired type %d with itself on attempt %d" % [source, i])
			quit(1)
			return
	print("PASS: randomized morph pairs always use different types")
	var before_source: int = material.get_shader_parameter("fractal_type")
	var before_target: int = material.get_shader_parameter("morph_target")
	active.call("CycleFractal", before_target - before_source)
	var selected_source: int = material.get_shader_parameter("fractal_type")
	var selected_target: int = material.get_shader_parameter("morph_target")
	if selected_source == selected_target:
		push_error("Manual source selection paired a type with itself")
		quit(1)
		return
	active.call("CycleMorphTarget", selected_source - selected_target)
	selected_target = material.get_shader_parameter("morph_target")
	if selected_source == selected_target:
		push_error("Manual target selection paired a type with itself")
		quit(1)
		return
	print("PASS: manual type selection keeps the morph pair distinct")
	quit(0)


func _collect_fractals(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var material := mesh.get_surface_override_material(0)
		if material == null:
			material = mesh.material_override
		if material is ShaderMaterial and material.shader.resource_path == "res://shaders/quaternion_julia.gdshader":
			found.append(mesh)
	for child in node.get_children():
		_collect_fractals(child, found)


func _find_auto_morph_button(node: Node) -> Button:
	if node is Button and node.text.begins_with("Auto morph"):
		return node
	for child in node.get_children():
		var result := _find_auto_morph_button(child)
		if result != null:
			return result
	return null


func _find_wrist_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for child in node.get_children():
		var result := _find_wrist_tabs(child)
		if result != null:
			return result
	return null
