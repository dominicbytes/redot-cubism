extends RefCounted

static func _capture(viewport: SubViewport) -> Image:
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func run(host: Node, fixture: Dictionary) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	viewport.add_child(model)
	model.assets = fixture.model
	if not model.is_initialized():
		viewport.free()
		return false
	var canvas: Dictionary = model.get_canvas_info()
	model.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	model.position = Vector2(128, 128)
	model.advance(1.0 / 60.0)
	var baseline: Image = await _capture(viewport)
	var overlay: Node2D = preload("res://addons/gd_cubism/res/debug_overlay.gd").new()
	model.add_child(overlay)
	for flag: int in [1, 2, 4, 7]:
		overlay.overlays = flag
		if flag == 7:
			for child: Node in model.get_children():
				if child is MeshInstance2D:
					overlay.drawable_id = str(child.name)
					break
		var actual: Image = await _capture(viewport)
		if actual.get_data() == baseline.get_data():
			viewport.free()
			push_error("CUBISM_OVERLAY_FAIL: overlay flag did not draw: " + str(flag))
			return false
		for argument: String in OS.get_cmdline_user_args():
			if flag == 7 and argument.begins_with("--overlay-capture="):
				if actual.save_png(argument.trim_prefix("--overlay-capture=")) != OK:
					viewport.free()
					return false
	overlay.drawable_id = "__not_a_drawable__"
	overlay.overlays = 5
	var filtered: Image = await _capture(viewport)
	if filtered.get_data() != baseline.get_data():
		viewport.free()
		push_error("CUBISM_OVERLAY_FAIL: drawable filter did not suppress unmatched IDs")
		return false
	overlay.overlays = 0
	var restored: Image = await _capture(viewport)
	if restored.get_data() != baseline.get_data():
		viewport.free()
		push_error("CUBISM_OVERLAY_FAIL: disabling overlay left drawing behind")
		return false
	model.unload_model()
	overlay.overlays = 7
	await _capture(viewport)
	viewport.free()
	print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
	print("CUBISM_OVERLAY_PASS flags=4 restored_pixels=true")
	return true
