extends RefCounted

static func _depth_range(model: GDCubismUserModel) -> Vector2i:
	var depths: Array[int] = []
	for child: Node in model.get_children():
		if child is MeshInstance2D and child.visible:
			depths.append(model.z_index + child.z_index)
	if depths.is_empty():
		return Vector2i(1, -1)
	return Vector2i(depths.min(), depths.max())

static func run(host: Node, fixture: Dictionary) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not host.get_window().is_visible():
		push_error("CUBISM_ORDER_FAIL: requires a visible graphics window")
		return false
	var models: Array[GDCubismUserModel] = []
	for index: int in 3:
		var model := GDCubismUserModel.new()
		model.playback_process_mode = GDCubismUserModel.MANUAL
		model.z_index = index
		host.add_child(model)
		model.assets = fixture.model
		model.advance(1.0 / 60.0)
		models.append(model)
	var passed: bool = true
	for model: GDCubismUserModel in models:
		var depths: Vector2i = _depth_range(model)
		if not model.is_initialized() or depths.x > depths.y:
			push_error("CUBISM_ORDER_FAIL: no visible model drawables")
			passed = false
		elif depths != Vector2i(model.z_index, model.z_index):
			push_error("CUBISM_ORDER_FAIL: drawable depth escapes model layer: " + str(depths))
			passed = false
	# Model-level reordering must remain independent of drawable-local order.
	models[0].z_index = 2
	models[1].z_index = 0
	models[2].z_index = 1
	for model: GDCubismUserModel in models:
		model.advance(1.0 / 60.0)
		if _depth_range(model) != Vector2i(model.z_index, model.z_index):
			passed = false
	for model: GDCubismUserModel in models:
		model.free()
	if passed:
		print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({
			"renderer": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"display": DisplayServer.get_name(),
		}))
		print("CUBISM_ORDER_PASS")
	return passed
