extends RefCounted

static func run(host: Node, fixture: Dictionary) -> bool:
	var model := GDCubismUserModel.new()
	host.add_child(model)
	var removed: Dictionary = {"done": false}
	model.child_entered_tree.connect(func(_child: Node) -> void:
		if not removed.done:
			removed.done = true
			host.remove_child(model)
	)
	model.assets = fixture.model
	if not removed.done or model.is_initialized() or model.get_child_count() != 0:
		push_error("CUBISM_LOADING_FAIL: removal during renderer creation retained partial state")
		return false
	model.free()
	print("CUBISM_LOADING_PASS")
	return true
