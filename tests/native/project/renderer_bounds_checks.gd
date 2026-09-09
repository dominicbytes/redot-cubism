extends RefCounted

static func run(host: Node, fixture: Dictionary) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not host.get_window().is_visible():
		push_error("CUBISM_BOUNDS_FAIL: requires a visible graphics window")
		return false
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	host.add_child(model)
	model.assets = fixture.model
	model.advance(1.0 / 60.0)
	var checked: int = 0
	var negative_axes: int = 0
	var passed: bool = model.is_initialized()
	for child: Node in model.get_children():
		if not child is MeshInstance2D:
			continue
		var mesh: ArrayMesh = child.mesh
		var vertices: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var minimum: Vector2 = vertices[0]
		var maximum: Vector2 = vertices[0]
		for vertex: Vector2 in vertices:
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
		negative_axes += int(maximum.x < 0.0) + int(maximum.y < 0.0)
		var bounds: AABB = mesh.custom_aabb
		var expected := AABB(Vector3(minimum.x, minimum.y, 0.0), Vector3(maximum.x - minimum.x, maximum.y - minimum.y, 0.0))
		if not bounds.is_equal_approx(expected):
			push_error("CUBISM_BOUNDS_FAIL: mesh " + str(child.name) + " has loose or incorrect bounds")
			passed = false
		checked += 1
	model.free()
	if checked == 0 or negative_axes == 0:
		push_error("CUBISM_BOUNDS_FAIL: fixture did not exercise all-negative coordinates")
		return false
	if passed:
		print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({
			"renderer": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"display": DisplayServer.get_name(),
		}))
		print("CUBISM_BOUNDS_PASS meshes=" + str(checked) + " negative_axes=" + str(negative_axes))
	return passed
