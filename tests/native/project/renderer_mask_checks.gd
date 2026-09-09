extends RefCounted

static func run(host: Node, fixture: Dictionary) -> bool:
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	host.add_child(model)
	model.assets = fixture.model
	var actual: Array[String] = []
	for child: Node in model.get_children():
		if child is SubViewport:
			var sources: Array[String] = []
			for mesh: Node in child.get_children():
				sources.append(str(mesh.name))
			sources.sort()
			actual.append(JSON.stringify(sources))
	var expected: Array[String] = []
	for composition: Array in fixture.mask_compositions:
		var sources: Array = composition.duplicate()
		sources.sort()
		expected.append(JSON.stringify(sources))
	actual.sort()
	expected.sort()
	var passed: bool = model.is_initialized() and not expected.is_empty() and actual == expected
	model.free()
	if passed:
		print("CUBISM_MASK_PASS")
	else:
		push_error("CUBISM_MASK_FAIL: expected " + str(expected) + ", got " + str(actual))
	return passed
