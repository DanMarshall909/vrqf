extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var wrist: Node = scene.get_node("XROrigin3D/LeftController/WristMenu")
	var tabs := _find_tabs(wrist)
	if tabs == null or tabs.get_node_or_null("Material") == null:
		push_error("Expected a Material tab on the VR wrist menu")
		quit(1)
		return
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("Material"))
	await process_frame

	var active: MeshInstance3D = get_first_node_in_group("fractal_controller")
	var material: ShaderMaterial = active.get_surface_override_material(0)
	active.call("CycleMaterial", 1) # Plastic supports the lit material controls.
	var controls := {
		"Increase roughness": ["material_roughness", 0.45],
		"Increase metalness": ["material_metallic", 0.10],
		"Increase emission": ["material_emission", 0.15],
	}
	for hint in controls:
		var button := _find_button(wrist, hint)
		if button == null or not button.is_visible_in_tree():
			push_error("Wrist material control is not visible: %s" % hint)
			quit(1)
			return
		var rect := button.get_global_rect()
		var bounds := button.get_viewport().get_visible_rect().size
		if rect.position.y < 0 or rect.end.y > bounds.y:
			push_error("Wrist material control is outside its viewport: %s" % hint)
			quit(1)
			return
		button.pressed.emit()
		var actual: float = material.get_shader_parameter(controls[hint][0])
		if absf(actual - controls[hint][1]) > 0.02:
			push_error("Wrist control %s did not change the shader: %.2f" % [hint, actual])
			quit(1)
			return

	print("PASS: wrist menu exposes material parameters and updates the shader")
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("Fractal"))
	var desktop_tabs: TabContainer = scene.get_node("HUD/ExplorerPanel/Tabs")
	desktop_tabs.current_tab = desktop_tabs.get_tab_idx_from_control(desktop_tabs.get_node("Fractal"))
	active.call("CycleFractal", 4) # Sierpinski Tetrahedron is one of the longest names.
	await process_frame
	var wrist_name := _find_selector_value(tabs.get_node("Fractal"), "Fractal")
	var desktop_panel: Control = scene.get_node("HUD/ExplorerPanel")
	var desktop_name := _find_selector_value(desktop_panel, "Type")
	if wrist_name == null or desktop_name == null or not _text_fits(wrist_name) or not _text_fits(desktop_name) \
			or wrist_name.get_parent().get_global_rect().position.x < 0 \
			or wrist_name.get_parent().get_global_rect().end.x > wrist_name.get_viewport().get_visible_rect().end.x \
			or desktop_name.get_parent().get_global_rect().position.x < desktop_panel.get_global_rect().position.x \
			or desktop_name.get_parent().get_global_rect().end.x > desktop_panel.get_global_rect().end.x:
		push_error("Long fractal names must fit the wrist and desktop selectors")
		quit(1)
		return
	print("PASS: long fractal names fit both selectors")
	quit(0)


func _find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for child in node.get_children():
		var result := _find_tabs(child)
		if result != null:
			return result
	return null


func _find_button(node: Node, hint: String) -> Button:
	if node is Button and node.tooltip_text == hint:
		return node
	for child in node.get_children():
		var result := _find_button(child, hint)
		if result != null:
			return result
	return null


func _find_selector_value(node: Node, title: String) -> Label:
	if node is HBoxContainer and node.get_child_count() == 4:
		var first := node.get_child(0)
		if first is Label and first.text == title and node.get_child(2) is Label:
			return node.get_child(2)
	for child in node.get_children():
		var result := _find_selector_value(child, title)
		if result != null:
			return result
	return null


func _text_fits(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	return width <= label.size.x
