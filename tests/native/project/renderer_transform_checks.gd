extends RefCounted

static func _capture(viewport: SubViewport) -> Image:
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func run(host: Node, fixture: Dictionary) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not host.get_window().is_visible():
		push_error("CUBISM_TRANSFORM_FAIL: requires graphics")
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
	model.mask_viewport_size = 128
	parent.add_child(model)
	model.assets = fixture.model
	if not model.is_initialized():
		viewport.free()
		return false
	var canvas: Dictionary = model.get_canvas_info()
	var scale: Vector2 = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	parent.position = Vector2(128, 128)
	model.scale = scale
	model.advance(1.0 / 60.0)
	var before: Image = await _capture(viewport)
	var count: int = model.get_child_count()
	for factor: Vector2 in [Vector2.ZERO, Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0.5), Vector2(0.000001, 0.000001), Vector2(10000, 10000)]:
		parent.rotation = 0.4
		# Node2D.set_scale clamps zero to epsilon; assign the intended matrix.
		model.transform = Transform2D(Vector2(scale.x * factor.x, 0), Vector2(0, scale.y * factor.y), Vector2.ZERO)
		model.advance(1.0 / 60.0)
		var masks: int = 0
		for child: Node in model.get_children():
			if child is SubViewport:
				masks += 1
				if factor.x * factor.y == 0.0 and child.render_target_update_mode != SubViewport.UPDATE_DISABLED:
					viewport.free()
					push_error("CUBISM_TRANSFORM_FAIL: singular transform still renders masks")
					return false
				if child.size.x < 1 or child.size.y < 1 or child.size.x > 128 or child.size.y > 128:
					viewport.free()
					push_error("CUBISM_TRANSFORM_FAIL: invalid or unbounded mask dimensions")
					return false
		if masks == 0 or model.get_child_count() != count:
			viewport.free()
			push_error("CUBISM_TRANSFORM_FAIL: mask/node count changed")
			return false
		await _capture(viewport)
	parent.rotation = 0.0
	model.scale = scale
	model.advance(1.0 / 60.0)
	var after: Image = await _capture(viewport)
	viewport.free()
	if before.get_data() != after.get_data():
		push_error("CUBISM_TRANSFORM_FAIL: returning to original transform changed pixels")
		return false
	print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
	print("CUBISM_TRANSFORM_PASS cases=6 restored_pixels=true")
	return true
