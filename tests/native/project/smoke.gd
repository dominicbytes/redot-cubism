extends Node2D

var completed_motions: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("CUBISM_NATIVE_FAIL: " + message)
		get_tree().quit(1)
	return condition

func _values(model: GDCubismUserModel) -> PackedFloat64Array:
	var values: PackedFloat64Array = []
	for parameter: GDCubismParameter in model.get_parameters():
		values.append(parameter.value)
	return values

func _node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _node_count(child)
	return count

func _window_cycles(model: GDCubismUserModel) -> bool:
	var window: Window = get_window()
	var nodes: int = _node_count(model)
	var minimize_observed: bool = true
	for cycle: int in 5:
		model.hide()
		for frame: int in 3:
			model.advance(1.0 / 60.0)
			await get_tree().process_frame
		model.show()
		window.mode = Window.MODE_MINIMIZED
		for frame: int in 3:
			model.advance(1.0 / 60.0)
			await get_tree().process_frame
		minimize_observed = minimize_observed and window.mode == Window.MODE_MINIMIZED
		window.mode = Window.MODE_WINDOWED
		for frame: int in 3:
			model.advance(1.0 / 60.0)
			await get_tree().process_frame
		if not _check(_node_count(model) == nodes, "mask/view nodes accumulated across visibility changes"):
			return false
	print("CUBISM_WINDOW_CYCLES:" + JSON.stringify({"cycles": 5, "owned_node_count": nodes, "minimize_observed": minimize_observed}))
	return true

func _capture(model: GDCubismUserModel, path: String) -> bool:
	if not await _window_cycles(model):
		return false
	var canvas: Dictionary = model.get_canvas_info()
	var viewport_size: Vector2 = get_viewport_rect().size
	model.position = viewport_size / 2.0
	model.scale = Vector2.ONE * viewport_size.y / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	# Restore pose groups for the visual check after isolated parameter tests.
	model.pose_update = true
	for frame: int in 120:
		model.advance(1.0 / 60.0)
	for frame: int in 3:
		model.advance(1.0 / 60.0)
		await RenderingServer.frame_post_draw
	var capture: Image = get_viewport().get_texture().get_image()
	if not _check(capture.save_png(path) == OK, "capture could not be written"):
		return false
	print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({
		"adapter": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(),
		"viewport": [capture.get_width(), capture.get_height()],
	}))
	return true

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	if "--loading-checks" in OS.get_cmdline_user_args():
		var passed: bool = preload("res://loading_checks.gd").run(self, fixture)
		get_tree().quit(0 if passed else 1)
		return
	if "--handle-checks" in OS.get_cmdline_user_args():
		var passed: bool = await preload("res://handle_checks.gd").run(self, fixture)
		get_tree().quit(0 if passed else 1)
		return
	if "--delta-checks" in OS.get_cmdline_user_args():
		var passed: bool = preload("res://delta_checks.gd").run(self, fixture)
		get_tree().quit(0 if passed else 1)
		return
	if "--process-checks" in OS.get_cmdline_user_args():
		var passed: bool = await preload("res://process_checks.gd").run(self, fixture)
		get_tree().quit(0 if passed else 1)
		return
	if "--lifecycle-checks" in OS.get_cmdline_user_args():
		var passed: bool = await preload("res://lifecycle_checks.gd").run(self, fixture)
		get_tree().quit(0 if passed else 1)
		return
	var versions: Dictionary = CubismBuildInfo.get_versions()
	print("CUBISM_NATIVE_VERSIONS:" + JSON.stringify(versions))
	if not _check(versions.runtime_core_packed == 0x06000001, "Core version mismatch"):
		return
	if not _check(versions.runtime_redot.major == 26 and versions.runtime_redot.minor == 2, "Redot version mismatch"):
		return
	if not _check(OS.has_feature("editor") or not ClassDB.class_exists("GDCubismPlugin"), "editor plugin registered in export template"):
		return
	for class_name_: String in ["GDCubismUserModel", "GDCubismParameter", "GDCubismPartOpacity", "GDCubismMotionLoader", "GDCubismMotionQueueEntryHandle", "GDCubismMotionEntry", "GDCubismEffectBreath", "GDCubismEffectEyeBlink", "GDCubismEffectCustom", "GDCubismEffectHitArea", "GDCubismEffectTargetPoint"]:
		if not _check(ClassDB.class_exists(class_name_), "class missing: " + class_name_):
			return
	var model := GDCubismUserModel.new()
	add_child(model)
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	model.assets = fixture.model
	if not _check(not model.get_canvas_info().is_empty(), "model failed to initialize"):
		return
	if not _check(not model.get_meshes().is_empty(), "drawable meshes missing"):
		return
	var before: PackedFloat64Array = _values(model)
	model.motion_finished.connect(func() -> void: completed_motions += 1)
	var handle: GDCubismMotionQueueEntryHandle = model.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
	if not _check(handle.get_error() == OK, "motion rejected"):
		return
	var moved: bool = false
	for frame: int in int(ceil((float(fixture.motion_duration) + 2.0) * 60.0)):
		model.advance(1.0 / 60.0)
		var current: PackedFloat64Array = _values(model)
		for i: int in before.size():
			moved = moved or absf(before[i] - current[i]) > 0.0001
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(moved and completed_motions == 1, "motion did not animate and finish exactly once"):
		return
	model.assets = fixture.model
	before = _values(model)
	model.start_expression(fixture.expression)
	for frame: int in 120:
		model.advance(1.0 / 60.0)
	var after: PackedFloat64Array = _values(model)
	var expression_changed: bool = false
	for i: int in before.size():
		expression_changed = expression_changed or absf(before[i] - after[i]) > 0.0001
	if not _check(expression_changed, "expression did not change parameters"):
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			if not await _capture(model, argument.trim_prefix("--capture=")):
				return
	model.stop_expression()
	model.stop_motion()
	model.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("CUBISM_NATIVE_PASS")
	get_tree().quit()
