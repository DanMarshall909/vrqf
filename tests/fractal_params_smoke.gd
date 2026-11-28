extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var active: MeshInstance3D = get_first_node_in_group("fractal_controller")
	var material: ShaderMaterial = active.get_surface_override_material(0)
	active.set("AutoMorph", false)

	var desktop_tabs: TabContainer = scene.get_node_or_null("HUD/ExplorerPanel/Tabs")
	var wrist: Node = scene.get_node_or_null("XROrigin3D/LeftController/WristMenu")
	var wrist_tabs := _find_tabs(wrist)
	if desktop_tabs == null or wrist_tabs == null:
		push_error("Expected both desktop and wrist TabContainers")
		quit(1)
		return

	var expected_tabs := ["Material", "Fractal", "Params", "Morph"]
	if not _has_tabs(desktop_tabs, expected_tabs) or not _has_tabs(wrist_tabs, expected_tabs):
		push_error("Expected unified 4-tab parity (Material, Fractal, Params, Morph) on both desktop and wrist menus")
		quit(1)
		return
	print("PASS: desktop and VR wrist menus share unified 4-tab structure")

	# 1. AO & Shadows on Material tab (desktop + wrist).
	_select_tab(desktop_tabs, "Material")
	_select_tab(wrist_tabs, "Material")
	await process_frame

	var ao_slider := _find_slider(desktop_tabs.get_node("Material"), "AO")
	var shadow_slider := _find_slider(desktop_tabs.get_node("Material"), "Shadows")
	if ao_slider == null or shadow_slider == null:
		push_error("Expected AO and Shadows sliders on desktop Material tab")
		quit(1)
		return
	ao_slider.value = 0.40
	shadow_slider.value = 0.30
	await process_frame
	if not _near(material.get_shader_parameter("ao_strength"), 0.40) \
			or not _near(material.get_shader_parameter("shadow_strength"), 0.30):
		push_error("Desktop AO/Shadows sliders did not update shader uniforms")
		quit(1)
		return

	for hint in ["Decrease ao", "Increase ao", "Decrease shadows", "Increase shadows"]:
		var btn := _find_button(wrist_tabs.get_node("Material"), hint)
		if btn == null or not _inside_viewport(btn):
			push_error("Wrist button %s missing or clipped outside viewport" % hint)
			quit(1)
			return
	_find_button(wrist_tabs.get_node("Material"), "Increase ao").pressed.emit()
	_find_button(wrist_tabs.get_node("Material"), "Increase shadows").pressed.emit()
	await process_frame
	if material.get_shader_parameter("ao_strength") <= 0.41 \
			or material.get_shader_parameter("shadow_strength") <= 0.31:
		push_error("Wrist AO/Shadows buttons did not update shader uniforms")
		quit(1)
		return

	# 2. Randomize button on desktop Fractal tab.
	_select_tab(desktop_tabs, "Fractal")
	await process_frame
	var rnd_btn := _find_button(desktop_tabs.get_node("Fractal"), "Randomize fractal and material settings")
	if rnd_btn == null:
		push_error("Expected Randomize button on desktop Fractal tab")
		quit(1)
		return

	# 3. Morph timing controls (desktop + wrist).
	_select_tab(desktop_tabs, "Morph")
	_select_tab(wrist_tabs, "Morph")
	await process_frame
	var hold_slider := _find_slider(desktop_tabs.get_node("Morph"), "Hold (s)")
	var trans_slider := _find_slider(desktop_tabs.get_node("Morph"), "Transition (s)")
	var wrist_hold_inc := _find_button(wrist_tabs.get_node("Morph"), "Increase hold (s)")
	var wrist_trans_inc := _find_button(wrist_tabs.get_node("Morph"), "Increase transition (s)")
	if hold_slider == null or trans_slider == null or wrist_hold_inc == null or wrist_trans_inc == null \
			or not _inside_viewport(wrist_hold_inc) or not _inside_viewport(wrist_trans_inc):
		push_error("Expected Hold (s) and Transition (s) controls on desktop and wrist Morph tabs")
		quit(1)
		return
	hold_slider.value = 1.5
	trans_slider.value = 2.0
	await process_frame
	if not _near(float(active.get("MorphHoldSeconds")), 1.5) \
			or not _near(float(active.get("MorphTransitionSeconds")), 2.0):
		push_error("Desktop Hold/Transition sliders did not update FractalController")
		quit(1)
		return
	wrist_hold_inc.pressed.emit()
	wrist_trans_inc.pressed.emit()
	await process_frame
	if float(active.get("MorphHoldSeconds")) <= 1.6 \
			or float(active.get("MorphTransitionSeconds")) <= 2.1:
		push_error("Wrist Hold/Transition buttons did not update FractalController")
		quit(1)
		return
	print("PASS: AO, Shadows, Randomize, and Morph timing controls work across desktop and VR")

	# 4. Context-sensitive Params tab: Quaternion Julia -> Mandelbulb -> Mandelbox -> memory -> reset.
	_select_tab(desktop_tabs, "Params")
	_select_tab(wrist_tabs, "Params")
	await process_frame

	var desk_params := desktop_tabs.get_node("Params")
	var wrist_params := wrist_tabs.get_node("Params")
	for label in ["C real (w)", "C i (x)", "C j (y)", "C k (z)", "4D slice (w)"]:
		if _find_slider(desk_params, label) == null:
			push_error("Missing Quaternion Julia slider %s on desktop Params tab" % label)
			quit(1)
			return
		var wbtn := _find_button(wrist_params, "Increase %s" % label.to_lower())
		if wbtn == null or not _inside_viewport(wbtn):
			push_error("Missing or clipped Quaternion Julia wrist button for %s" % label)
			quit(1)
			return
	var reset_btn := _find_button_by_text(desk_params, "Reset formula")
	var wrist_reset_btn := _find_button_by_text(wrist_params, "Reset formula")
	if reset_btn == null or wrist_reset_btn == null or not _inside_viewport(wrist_reset_btn):
		push_error("Missing or clipped Reset formula button on Params tab")
		quit(1)
		return

	_find_slider(desk_params, "C real (w)").value = 0.75
	_find_slider(desk_params, "4D slice (w)").value = 0.30
	await process_frame
	var pa: Vector4 = material.get_shader_parameter("fractal_params_a")
	var p4a: float = material.get_shader_parameter("fractal_param4_a")
	if not _near(pa.x, 0.75) or not _near(p4a, 0.30):
		push_error("Quaternion Julia params did not reach shader: params_a=%s slice=%s" % [pa, p4a])
		quit(1)
		return

	# Cycle to Mandelbulb (type 1).
	active.call("CycleFractal", 1)
	await process_frame
	if _find_slider(desk_params, "C real (w)") != null:
		push_error("Params tab retained Quaternion Julia slider after switching to Mandelbulb")
		quit(1)
		return
	for label in ["Power", "Phase theta", "Phase phi"]:
		if _find_slider(desk_params, label) == null:
			push_error("Missing Mandelbulb slider %s" % label)
			quit(1)
			return
	pa = material.get_shader_parameter("fractal_params_a")
	if not _near(pa.x, 8.0):
		push_error("Expected Mandelbulb default Power=8.0, got %.2f" % pa.x)
		quit(1)
		return
	var inc_power := _find_button(wrist_params, "Increase power")
	if inc_power == null or not _inside_viewport(inc_power):
		push_error("Missing or clipped Increase power wrist button")
		quit(1)
		return
	inc_power.pressed.emit()
	await process_frame
	pa = material.get_shader_parameter("fractal_params_a")
	if not _near(pa.x, 8.5):
		push_error("Expected Mandelbulb Power=8.5 after wrist increment, got %.2f" % pa.x)
		quit(1)
		return

	# Cycle to Mandelbox (type 6).
	active.call("CycleFractal", 5)
	await process_frame
	for label in ["Scale", "Box fold", "Min radius"]:
		if _find_slider(desk_params, label) == null:
			push_error("Missing Mandelbox slider %s" % label)
			quit(1)
			return
		var wbtn := _find_button(wrist_params, "Increase %s" % label.to_lower())
		if wbtn == null or not _inside_viewport(wbtn):
			push_error("Missing or clipped Mandelbox wrist button for %s" % label)
			quit(1)
			return

	# Cycle back to Quaternion Julia (type 0) and set morph_target = Mandelbulb (1).
	active.call("CycleFractal", 10)
	while int(material.get_shader_parameter("morph_target")) != 1:
		active.call("CycleMorphTarget", 1)
	await process_frame
	pa = material.get_shader_parameter("fractal_params_a")
	p4a = material.get_shader_parameter("fractal_param4_a")
	var pb: Vector4 = material.get_shader_parameter("fractal_params_b")
	if not _near(pa.x, 0.75) or not _near(p4a, 0.30) or not _near(pb.x, 8.5):
		push_error("Per-fractal param memory or morph target isolation failed: a=%s slice=%s b=%s" % [pa, p4a, pb])
		quit(1)
		return

	# Reset formula restores Quaternion Julia defaults.
	reset_btn = _find_button_by_text(desk_params, "Reset formula")
	if reset_btn == null:
		push_error("Missing Reset formula button after returning to Quaternion Julia")
		quit(1)
		return
	reset_btn.pressed.emit()
	await process_frame
	pa = material.get_shader_parameter("fractal_params_a")
	p4a = material.get_shader_parameter("fractal_param4_a")
	if not _near(pa.x, 0.50) or not _near(p4a, 0.0):
		push_error("Reset formula did not restore Quaternion Julia defaults: a=%s slice=%s" % [pa, p4a])
		quit(1)
		return
	print("PASS: context-sensitive Params tab updates, remembers, isolates morph target, and resets")

	# 5. All 4 wrist menu tabs fit strictly inside the SubViewport.
	for tab_name in expected_tabs:
		_select_tab(wrist_tabs, tab_name)
		await process_frame
		var page := wrist_tabs.get_node(tab_name)
		if not _all_buttons_inside_viewport(page):
			push_error("Wrist tab %s has buttons outside its SubViewport" % tab_name)
			quit(1)
			return
	print("PASS: all 4 wrist menu tabs fit inside the VR SubViewport")
	quit(0)


func _has_tabs(tabs: TabContainer, expected: Array) -> bool:
	if tabs.get_tab_count() != expected.size():
		return false
	for i in expected.size():
		if tabs.get_tab_title(i) != expected[i] or tabs.get_node_or_null(expected[i]) == null:
			return false
	return true


func _select_tab(tabs: TabContainer, tab_name: String) -> void:
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node(tab_name))


func _all_buttons_inside_viewport(node: Node) -> bool:
	if node is Button:
		if not _inside_viewport(node):
			return false
	for child in node.get_children():
		if not _all_buttons_inside_viewport(child):
			return false
	return true


func _inside_viewport(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	var viewport_rect := control.get_viewport().get_visible_rect()
	return viewport_rect.encloses(rect)


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.02


func _find_tabs(node: Node) -> TabContainer:
	if node == null:
		return null
	if node is TabContainer:
		return node
	for child in node.get_children():
		var found := _find_tabs(child)
		if found != null:
			return found
	return null


func _find_button(node: Node, hint: String) -> Button:
	if node is Button and node.tooltip_text == hint:
		return node
	for child in node.get_children():
		var found := _find_button(child, hint)
		if found != null:
			return found
	return null


func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
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
