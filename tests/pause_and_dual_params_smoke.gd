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
	var desktop_tabs: TabContainer = scene.get_node("HUD/ExplorerPanel/Tabs")
	var wrist: Node = scene.get_node("XROrigin3D/LeftController/WristMenu")
	var wrist_tabs := _find_tabs(wrist)

	# 1. Pause morph & Pause anim buttons on Material, Fractal, Params, and Morph tabs.
	for tab_name in ["Material", "Fractal", "Params", "Morph"]:
		_select_tab(desktop_tabs, tab_name)
		_select_tab(wrist_tabs, tab_name)
		await process_frame
		var d_anim := _find_button(desktop_tabs.get_node(tab_name), "Pause or resume fractal shape animation")
		var w_anim := _find_button(wrist_tabs.get_node(tab_name), "Pause or resume fractal shape animation")
		if d_anim == null or w_anim == null or not _inside_viewport(w_anim):
			push_error("Missing or clipped Pause anim control on tab %s" % tab_name)
			quit(1)
			return
		if tab_name != "Morph":
			var d_morph := _find_button(desktop_tabs.get_node(tab_name), "Pause or resume automatic morphing")
			var w_morph := _find_button(wrist_tabs.get_node(tab_name), "Pause or resume automatic morphing")
			if d_morph == null or w_morph == null or not _inside_viewport(w_morph):
				push_error("Missing or clipped Pause morph control on tab %s" % tab_name)
				quit(1)
				return

	# Verify morph pause & resume via Fractal tab button.
	_select_tab(desktop_tabs, "Fractal")
	await process_frame
	active.set("MorphHoldSeconds", 0.0)
	active.set("MorphTransitionSeconds", 1.2)
	await create_timer(0.2).timeout
	var pause_morph_btn := _find_button(desktop_tabs.get_node("Fractal"), "Pause or resume automatic morphing")
	if pause_morph_btn.text != "Pause morph":
		push_error("Expected initial button label 'Pause morph', got '%s'" % pause_morph_btn.text)
		quit(1)
		return
	pause_morph_btn.pressed.emit()
	await process_frame
	if bool(active.get("AutoMorph")) or pause_morph_btn.text != "Resume morph":
		push_error("Pause morph button did not pause AutoMorph or update label")
		quit(1)
		return
	var paused_morph: float = material.get_shader_parameter("morph")
	await create_timer(0.3).timeout
	if absf(float(material.get_shader_parameter("morph")) - paused_morph) > 0.01:
		push_error("Morph continued advancing while paused")
		quit(1)
		return
	pause_morph_btn.pressed.emit()
	await process_frame
	if not bool(active.get("AutoMorph")) or pause_morph_btn.text != "Pause morph":
		push_error("Resume morph button did not resume AutoMorph")
		quit(1)
		return
	await create_timer(0.3).timeout
	if float(material.get_shader_parameter("morph")) <= paused_morph + 0.05:
		push_error("Morph did not advance after Resume morph")
		quit(1)
		return

	# Verify shape animation pause & resume preserves SpeedValue and anim_phase.
	active.set("AutoMorph", false)
	material.set_shader_parameter("morph", 0.0)
	var initial_speed := float(active.get("SpeedValue"))
	await create_timer(0.2).timeout
	var pause_anim_btn := _find_button(desktop_tabs.get_node("Fractal"), "Pause or resume fractal shape animation")
	if pause_anim_btn.text != "Pause anim":
		push_error("Expected initial button label 'Pause anim', got '%s'" % pause_anim_btn.text)
		quit(1)
		return
	pause_anim_btn.pressed.emit()
	await process_frame
	if not bool(active.get("AnimationPaused")) or pause_anim_btn.text != "Resume anim" \
			or absf(float(active.get("SpeedValue")) - initial_speed) > 0.001:
		push_error("Pause anim failed to pause without altering SpeedValue")
		quit(1)
		return
	var paused_phase = material.get_shader_parameter("anim_phase")
	if paused_phase == null:
		push_error("Missing anim_phase shader uniform")
		quit(1)
		return
	await create_timer(0.25).timeout
	if absf(float(material.get_shader_parameter("anim_phase")) - float(paused_phase)) > 0.0001:
		push_error("anim_phase continued advancing while animation was paused")
		quit(1)
		return
	pause_anim_btn.pressed.emit()
	await process_frame
	if bool(active.get("AnimationPaused")) or pause_anim_btn.text != "Pause anim":
		push_error("Resume anim did not unpause")
		quit(1)
		return
	await create_timer(0.25).timeout
	if float(material.get_shader_parameter("anim_phase")) <= float(paused_phase) + 0.01:
		push_error("anim_phase did not resume advancing from paused value")
		quit(1)
		return

	# Verify K keyboard shortcut pauses & resumes anim_phase cleanly without changing SpeedValue.
	_send_key(KEY_K)
	await process_frame
	if not bool(active.get("AnimationPaused")) or pause_anim_btn.text != "Resume anim" \
			or absf(float(active.get("SpeedValue")) - initial_speed) > 0.001:
		push_error("KEY_K did not pause animation cleanly")
		quit(1)
		return
	var k_paused_phase = float(material.get_shader_parameter("anim_phase"))
	await create_timer(0.25).timeout
	if absf(float(material.get_shader_parameter("anim_phase")) - k_paused_phase) > 0.0001:
		push_error("anim_phase continued advancing after KEY_K pause")
		quit(1)
		return
	_send_key(KEY_K)
	await process_frame
	if bool(active.get("AnimationPaused")) or pause_anim_btn.text != "Pause anim":
		push_error("Second KEY_K did not resume animation")
		quit(1)
		return
	await create_timer(0.25).timeout
	if float(material.get_shader_parameter("anim_phase")) <= k_paused_phase + 0.01:
		push_error("anim_phase did not resume advancing after second KEY_K")
		quit(1)
		return
	print("PASS: morph and animation pause/resume controls (and K shortcut) work across desktop and VR")

	# 2. Dual A/B fractal parameter editing on Params tab.
	_select_tab(desktop_tabs, "Params")
	_select_tab(wrist_tabs, "Params")
	await process_frame

	var desk_params := desktop_tabs.get_node("Params")
	var wrist_params := wrist_tabs.get_node("Params")
	var slot_a := _find_button(desk_params, "Edit source fractal (A) parameters")
	var slot_b := _find_button(desk_params, "Edit target fractal (B) parameters")
	var w_slot_a := _find_button(wrist_params, "Edit source fractal (A) parameters")
	var w_slot_b := _find_button(wrist_params, "Edit target fractal (B) parameters")
	if slot_a == null or slot_b == null or w_slot_a == null or w_slot_b == null \
			or not _inside_viewport(w_slot_a) or not _inside_viewport(w_slot_b):
		push_error("Missing or clipped A/B source-target switcher buttons on Params tab")
		quit(1)
		return
	if bool(active.get("EditingMorphTarget")) or _find_slider(desk_params, "C real (w)") == null:
		push_error("Expected default Params slot A (Quaternion Julia)")
		quit(1)
		return
	if not slot_a.button_pressed or slot_b.button_pressed or slot_a.button_group == null or slot_a.button_group.allow_unpress \
			or not w_slot_a.button_pressed or w_slot_b.button_pressed or w_slot_a.button_group == null or w_slot_a.button_group.allow_unpress:
		push_error("A/B toggle buttons must use a non-unpressable ButtonGroup with A pressed initially")
		quit(1)
		return

	# Edit A slightly so we can verify A stays preserved across B edits and B reset.
	_find_slider(desk_params, "C real (w)").value = 0.65
	await process_frame

	# Switch to B (Mandelbulb, type 1).
	slot_b.pressed.emit()
	await process_frame
	if not bool(active.get("EditingMorphTarget")):
		push_error("Clicking B · Target did not set EditingMorphTarget=true")
		quit(1)
		return
	var desk_b_btn := _find_button(desk_params, "Edit target fractal (B) parameters")
	var desk_a_btn := _find_button(desk_params, "Edit source fractal (A) parameters")
	var wrist_b_btn := _find_button(wrist_params, "Edit target fractal (B) parameters")
	if not desk_b_btn.button_pressed or desk_a_btn.button_pressed or not wrist_b_btn.button_pressed:
		push_error("Switching to slot B did not update button_pressed state on Desktop or VR")
		quit(1)
		return
	desk_b_btn.pressed.emit()
	await process_frame
	if not desk_b_btn.button_pressed:
		push_error("Clicking already-active B · Target unpressed the active toggle button")
		quit(1)
		return
	if _find_slider(desk_params, "C real (w)") != null or _find_slider(desk_params, "Power") == null \
			or _find_button(wrist_params, "Increase power") == null:
		push_error("Desktop or VR Params tab did not rebuild for target Mandelbulb")
		quit(1)
		return

	_find_slider(desk_params, "Power").value = 10.0
	await process_frame
	var pa: Vector4 = material.get_shader_parameter("fractal_params_a")
	var pb: Vector4 = material.get_shader_parameter("fractal_params_b")
	if not _near(pb.x, 10.0) or not _near(pa.x, 0.65):
		push_error("Editing B corrupted A or failed to update B: a=%s b=%s" % [pa, pb])
		quit(1)
		return

	_find_button(wrist_params, "Increase power").pressed.emit()
	await process_frame
	pb = material.get_shader_parameter("fractal_params_b")
	if not _near(pb.x, 10.5):
		push_error("Wrist Increase power on B did not update fractal_params_b.x: %s" % [pb])
		quit(1)
		return

	# Cycle morph target while editing B -> Quaternion Mandelbrot (type 2).
	active.call("CycleMorphTarget", 1)
	await process_frame
	if _find_slider(desk_params, "Offset w") == null or _find_slider(desk_params, "Offset x") == null:
		push_error("Cycling target while editing B did not rebuild Params tab for Quaternion Mandelbrot")
		quit(1)
		return
	_find_slider(desk_params, "Offset x").value = 0.55
	await process_frame
	pb = material.get_shader_parameter("fractal_params_b")
	if not _near(pb.y, 0.55):
		push_error("Editing Quaternion Mandelbrot B Offset x failed: %s" % [pb])
		quit(1)
		return

	# Reset formula while editing B resets B only, preserving A.
	var reset_b := _find_button_by_text(desk_params, "Reset formula")
	reset_b.pressed.emit()
	await process_frame
	pa = material.get_shader_parameter("fractal_params_a")
	pb = material.get_shader_parameter("fractal_params_b")
	if not _near(pb.y, 0.18) or not _near(pa.x, 0.65):
		push_error("Reset formula on B did not isolate B from A: a=%s b=%s" % [pa, pb])
		quit(1)
		return

	# Switch back to A -> preserves A's edit (0.65).
	_find_button(desk_params, "Edit source fractal (A) parameters").pressed.emit()
	await process_frame
	if bool(active.get("EditingMorphTarget")) or not _near(_find_slider(desk_params, "C real (w)").value, 0.65):
		push_error("Returning to slot A did not restore Quaternion Julia edit")
		quit(1)
		return
	print("PASS: Params tab edits and resets both source (A) and target (B) independently")

	# 3. Verify all 4 VR WristMenu tabs (including Params A & B) fit strictly inside SubViewport.
	for tab_name in ["Material", "Fractal", "Params", "Morph"]:
		_select_tab(wrist_tabs, tab_name)
		await process_frame
		if not _all_buttons_inside_viewport(wrist_tabs.get_node(tab_name)):
			push_error("Wrist tab %s overflows SubViewport" % tab_name)
			quit(1)
			return
	_select_tab(wrist_tabs, "Params")
	_find_button(wrist_params, "Edit target fractal (B) parameters").pressed.emit()
	await process_frame
	if not _all_buttons_inside_viewport(wrist_params):
		push_error("Wrist Params tab (slot B) overflows SubViewport")
		quit(1)
		return
	print("PASS: all 4 VR wrist menu tabs fit strictly inside the SubViewport")
	quit(0)


func _send_key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = code
	release.pressed = false
	Input.parse_input_event(release)


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
