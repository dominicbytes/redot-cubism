extends RefCounted

static func _depth_range(model: GDCubismUserModel) -> Vector2i:
	var depths: Array[int] = []
	for child: Node in model.get_children():
		if child is MeshInstance2D and child.visible:
			depths.append(model.z_index + child.z_index)
	if depths.is_empty():
		return Vector2i(1, -1)
	return Vector2i(depths.min(), depths.max())

static func _drawable_order(model: GDCubismUserModel) -> Array[String]:
	var order: Array[String] = []
	for child: Node in model.get_children():
		if child is MeshInstance2D:
			order.append(str(child.name))
	return order

static func _dynamic_order(model: GDCubismUserModel, oracle: Dictionary) -> bool:
	model.physics_evaluate = false
	model.pose_update = false
	var changed: int = 0
	for test: Dictionary in oracle.cases:
		for parameter: GDCubismParameter in model.get_parameters():
			parameter.value = oracle.defaults[parameter.id]
		model.advance(1.0 / 60.0)
		if _drawable_order(model) != oracle.default_order:
			push_error("CUBISM_ORDER_FAIL: default order differs from Core")
			return false
		var found: bool = false
		for parameter: GDCubismParameter in model.get_parameters():
			if parameter.id == test.parameter:
				parameter.value = test.value
				found = true
		model.advance(1.0 / 60.0)
		if not found or test.order == oracle.default_order or _drawable_order(model) != test.order:
			push_error("CUBISM_ORDER_FAIL: dynamic order differs from Core for " + str(test.parameter))
			return false
		if _depth_range(model) != Vector2i(model.z_index, model.z_index):
			push_error("CUBISM_ORDER_FAIL: dynamic order escaped model layer")
			return false
		changed += 1
	for parameter: GDCubismParameter in model.get_parameters():
		parameter.value = oracle.defaults[parameter.id]
	model.advance(1.0 / 60.0)
	if changed == 0 or _drawable_order(model) != oracle.default_order:
		push_error("CUBISM_ORDER_FAIL: dynamic order did not restore")
		return false
	print("CUBISM_DYNAMIC_ORDER_PASS cases=" + str(changed))
	return true

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
	if passed and fixture.get("draw_order_oracle") != null:
		passed = _dynamic_order(models[0], fixture.draw_order_oracle)
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
