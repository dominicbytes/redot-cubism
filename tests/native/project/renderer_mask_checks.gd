extends RefCounted

static func run(host: Node, fixture: Dictionary) -> bool:
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	host.add_child(model)
	model.assets = fixture.model
	var actual: Array[String] = []
	var textures: Dictionary = {}
	for child: Node in model.get_children():
		if child is MeshInstance2D:
			textures[str(child.name)] = child.material.get_shader_parameter("tex_main")
	var texture_matches: bool = true
	for child: Node in model.get_children():
		if child is SubViewport:
			var sources: Array[String] = []
			for mesh: Node in child.get_children():
				sources.append(str(mesh.name))
				if mesh.material.get_shader_parameter("tex_main") != textures.get(str(mesh.name)):
					push_error("CUBISM_MASK_FAIL: incorrect source texture for " + str(mesh.name))
					texture_matches = false
			sources.sort()
			actual.append(JSON.stringify(sources))
	var expected: Array[String] = []
	for composition: Array in fixture.mask_compositions:
		var sources: Array = composition.duplicate()
		sources.sort()
		expected.append(JSON.stringify(sources))
	actual.sort()
	expected.sort()
	var passed: bool = model.is_initialized() and texture_matches and not expected.is_empty() and actual == expected
	model.free()
	if passed:
		print("CUBISM_MASK_PASS")
	else:
		push_error("CUBISM_MASK_FAIL: expected " + str(expected) + ", got " + str(actual))
	return passed
