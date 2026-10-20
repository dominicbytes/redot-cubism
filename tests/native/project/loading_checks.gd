extends RefCounted

static func run(host: Node, fixture: Dictionary) -> bool:
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	host.add_child(model)
	var removed: Dictionary = {"done": false}
	model.child_entered_tree.connect(func(_child: Node) -> void:
		if not removed.done:
			removed.done = true
			host.remove_child(model)
	)
	model.assets = fixture.model
	if not removed.done or model.is_inside_tree() or not model.is_initialized() or model.get_model_state() != GDCubismUserModel.READY or model.get_child_count() == 0:
		model.free()
		push_error("CUBISM_LOADING_FAIL: removal during renderer creation did not retain a complete legacy model")
		return false
	var parameter: GDCubismParameter = model.get_parameters()[0]
	var children := model.get_child_count()
	model.advance(0.0)
	host.add_child(model)
	if not parameter.is_valid() or model.get_parameters()[0] != parameter or model.get_child_count() != children:
		model.free()
		push_error("CUBISM_LOADING_FAIL: reentry replaced retained legacy state")
		return false
	model.unload_model()
	if model.is_initialized() or parameter.is_valid() or model.get_child_count() != 0:
		model.free()
		push_error("CUBISM_LOADING_FAIL: explicit unload retained native state")
		return false
	model.free()
	var cancelled := GDCubismUserModel.new()
	host.add_child(cancelled)
	cancelled.child_entered_tree.connect(func(_child: Node) -> void: cancelled.unload_model())
	cancelled.assets = fixture.model
	if cancelled.is_initialized() or cancelled.get_child_count() != 0:
		cancelled.free()
		push_error("CUBISM_LOADING_FAIL: unload during renderer creation retained partial state")
		return false
	cancelled.free()
	print("CUBISM_LOADING_PASS")
	return true
