extends RefCounted

static func _masks(model: GDCubismUserModel, mode: int) -> bool:
	var count: int = 0
	for child: Node in model.get_children():
		if child is SubViewport:
			count += 1
			if child.render_target_update_mode != mode:
				return false
	return count > 0

static func run(host: Node, fixture: Dictionary) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not host.get_window().is_visible():
		push_error("CUBISM_OFFSCREEN_FAIL: requires a visible graphics window")
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var parent := Node2D.new()
	viewport.add_child(parent)
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	parent.add_child(model)
	model.assets = fixture.model
	if not model.is_initialized():
		viewport.free()
		push_error("CUBISM_OFFSCREEN_FAIL: fixture did not load")
		return false
	var canvas: Dictionary = model.get_canvas_info()
	model.position = Vector2(128, 128)
	model.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	model.advance(1.0 / 60.0)
	var count: int = model.get_child_count()
	for cycle: int in 5:
		parent.position = Vector2(100000, 100000)
		model.advance(1.0 / 60.0)
		if not _masks(model, SubViewport.UPDATE_DISABLED):
			viewport.free()
			push_error("CUBISM_OFFSCREEN_FAIL: offscreen masks still render")
			return false
		if cycle == 0:
			model.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
			var before: Array[float] = []
			for parameter: GDCubismParameter in model.get_parameters():
				before.append(parameter.value)
			for step: int in 30:
				model.advance(1.0 / 60.0)
			var changed: bool = false
			var parameters: Array = model.get_parameters()
			for index: int in parameters.size():
				changed = changed or absf(parameters[index].value - before[index]) > 0.0001
			if not changed or not _masks(model, SubViewport.UPDATE_DISABLED):
				viewport.free()
				push_error("CUBISM_OFFSCREEN_FAIL: animation stopped or masks resumed offscreen")
				return false
		parent.position = Vector2.ZERO
		parent.hide()
		model.advance(1.0 / 60.0)
		if not _masks(model, SubViewport.UPDATE_DISABLED):
			viewport.free()
			push_error("CUBISM_OFFSCREEN_FAIL: hidden masks resumed during advance")
			return false
		parent.show()
		model.advance(1.0 / 60.0)
		if not _masks(model, SubViewport.UPDATE_ALWAYS) or model.get_child_count() != count:
			viewport.free()
			push_error("CUBISM_OFFSCREEN_FAIL: visible masks did not resume or nodes accumulated")
			return false
	# World-space distance must not cull a character followed by the camera.
	parent.position = Vector2(100000, 100000)
	parent.rotation = 0.3
	model.scale *= Vector2(-1.0, 0.5)
	var camera := Camera2D.new()
	camera.position = model.global_position
	camera.zoom = Vector2(0.5, 0.5)
	camera.ignore_rotation = false
	camera.rotation = 0.3
	viewport.add_child(camera)
	camera.force_update_scroll()
	model.advance(1.0 / 60.0)
	if not _masks(model, SubViewport.UPDATE_ALWAYS):
		viewport.free()
		push_error("CUBISM_OFFSCREEN_FAIL: camera-followed masks were culled")
		return false
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var opaque_pixels: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			opaque_pixels += int(image.get_pixel(x, y).a > 0.1)
	viewport.free()
	if opaque_pixels < 100:
		push_error("CUBISM_OFFSCREEN_FAIL: returned model did not render")
		return false
	print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
	print("CUBISM_OFFSCREEN_PASS cycles=5 camera_transform=true")
	return true
