extends RefCounted

static func _values(model: GDCubismUserModel) -> PackedFloat64Array:
	var values: PackedFloat64Array = []
	for parameter: GDCubismParameter in model.get_parameters():
		values.append(parameter.value)
	return values

static func _moved(before: PackedFloat64Array, model: GDCubismUserModel) -> bool:
	var after: PackedFloat64Array = _values(model)
	for i: int in before.size():
		if absf(before[i] - after[i]) > 0.0001:
			return true
	return false

static func _mask_modes(model: GDCubismUserModel, expected: int) -> bool:
	var count: int = 0
	for child: Node in model.get_children():
		if child is SubViewport:
			count += 1
			if child.render_target_update_mode != expected:
				return false
	return count > 0

static func _visibility(host: Node, fixture: Dictionary) -> bool:
	var parent := Node2D.new()
	parent.hide()
	host.add_child(parent)
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	parent.add_child(model)
	model.assets = fixture.model
	var nodes: int = model.get_child_count()
	if not _mask_modes(model, SubViewport.UPDATE_DISABLED):
		push_error("CUBISM_PROCESS_FAIL: initially hidden mask viewports still render")
		parent.free()
		return false
	for cycle: int in 5:
		parent.show()
		if not _mask_modes(model, SubViewport.UPDATE_ALWAYS):
			push_error("CUBISM_PROCESS_FAIL: inherited visibility did not restore masks")
			parent.free()
			return false
		model.hide()
		model.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
		var before: PackedFloat64Array = _values(model)
		for step: int in 30:
			model.advance(1.0 / 60.0)
		if (cycle == 0 and not _moved(before, model)) or not _mask_modes(model, SubViewport.UPDATE_DISABLED):
			push_error("CUBISM_PROCESS_FAIL: hidden animation or mask suspension")
			parent.free()
			return false
		model.show()
		parent.hide()
		if not _mask_modes(model, SubViewport.UPDATE_DISABLED) or model.get_child_count() != nodes:
			push_error("CUBISM_PROCESS_FAIL: inherited hiding retained rendering or allocated nodes")
			parent.free()
			return false
	parent.free()
	return true

static func run(host: Node, fixture: Dictionary) -> bool:
	var tree: SceneTree = host.get_tree()
	if not _visibility(host, fixture):
		return false
	for mode: int in [GDCubismUserModel.IDLE, GDCubismUserModel.PHYSICS, GDCubismUserModel.MANUAL]:
		var model: GDCubismUserModel = preload("res://process_override.gd").new()
		model.assets = fixture.model
		model.playback_process_mode = mode
		model.physics_evaluate = false
		model.pose_update = false
		host.add_child(model)
		model.set_process(false)
		model.set_physics_process(false)
		model.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
		var before: PackedFloat64Array = _values(model)
		for frame: int in 30:
			await tree.process_frame
		var moved: bool = _moved(before, model)
		if moved != (mode != GDCubismUserModel.MANUAL):
			push_error("CUBISM_PROCESS_FAIL: native process mode " + str(mode))
			return false
		if mode == GDCubismUserModel.MANUAL:
			for step: int in 30:
				model.advance(1.0 / 60.0)
			if not _moved(before, model):
				push_error("CUBISM_PROCESS_FAIL: manual advance did not animate")
				return false
		before = _values(model)
		tree.paused = true
		if mode == GDCubismUserModel.MANUAL:
			model.advance(0.5)
		for frame: int in 10:
			await tree.process_frame
		tree.paused = false
		if _moved(before, model) != (mode == GDCubismUserModel.MANUAL):
			push_error("CUBISM_PROCESS_FAIL: paused processing or explicit manual advance")
			return false
		model.queue_free()
		await tree.process_frame
		await tree.process_frame
	print("CUBISM_PROCESS_PASS")
	return true
