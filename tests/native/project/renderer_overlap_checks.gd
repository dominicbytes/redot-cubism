extends RefCounted

static func _capture(viewport: SubViewport) -> Image:
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func run(host: Node, fixture: Dictionary) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not host.get_window().is_visible():
		push_error("CUBISM_OVERLAP_FAIL: requires a visible graphics window")
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var models: Array[GDCubismUserModel] = []
	var colors: Array[Color] = [Color(1, 0.4, 0.4, 0.7), Color(0.4, 1, 0.4, 0.8), Color(0.4, 0.4, 1, 0.9)]
	for index: int in 3:
		var model := GDCubismUserModel.new()
		model.playback_process_mode = GDCubismUserModel.MANUAL
		model.physics_evaluate = false
		model.pose_update = false
		viewport.add_child(model)
		model.assets = fixture.model
		if not model.is_initialized():
			viewport.free()
			push_error("CUBISM_OVERLAP_FAIL: fixture did not load")
			return false
		var canvas: Dictionary = model.get_canvas_info()
		model.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
		model.position = Vector2(108 + index * 20, 128)
		model.modulate = colors[index]
		model.hide()
		models.append(model)
	var layers: Array[Image] = []
	for model: GDCubismUserModel in models:
		model.show()
		model.advance(1.0 / 60.0)
		layers.append(await _capture(viewport))
		model.hide()
	var overlap_pixels: int = 0
	for y: int in 256:
		for x: int in 256:
			var covered: int = 0
			for layer: Image in layers:
				covered += int(layer.get_pixel(x, y).a > 0.05)
			overlap_pixels += int(covered >= 2)
	if overlap_pixels < 50:
		viewport.free()
		push_error("CUBISM_OVERLAP_FAIL: fixture has insufficient overlap")
		return false
	var worst_error: float = 0.0
	var capture_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--overlap-capture="):
			capture_path = argument.trim_prefix("--overlap-capture=")
	for order: Array in [[0, 1], [1, 0], [0, 1, 2], [2, 0, 1]]:
		for model: GDCubismUserModel in models:
			model.hide()
		for depth: int in order.size():
			var model: GDCubismUserModel = models[order[depth]]
			model.z_index = depth
			model.show()
			model.advance(1.0 / 60.0)
		var actual: Image = await _capture(viewport)
		var reference := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		var mismatches: int = 0
		for y: int in 256:
			for x: int in 256:
				# Isolated captures contain premultiplied RGB on transparent black.
				var expected := Color(0, 0, 0, 0)
				for index: int in order:
					var source: Color = layers[index].get_pixel(x, y)
					expected = source + expected * (1.0 - source.a)
				reference.set_pixel(x, y, expected)
				var pixel: Color = actual.get_pixel(x, y)
				var error: float = 0.0
				for channel: int in 4:
					error = maxf(error, absf(pixel[channel] - expected[channel]))
				worst_error = maxf(worst_error, error)
				mismatches += int(error > 3.0 / 255.0)
		if not capture_path.is_empty():
			if actual.save_png(capture_path) != OK or reference.save_png(capture_path.get_basename() + "-reference.png") != OK:
				viewport.free()
				push_error("CUBISM_OVERLAP_FAIL: could not save comparison")
				return false
		if mismatches > 0:
			viewport.free()
			push_error("CUBISM_OVERLAP_FAIL: order=" + str(order) + " mismatched_pixels=" + str(mismatches) + " max_error=" + str(worst_error))
			return false
	viewport.free()
	print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
	print("CUBISM_OVERLAP_PASS orders=4 overlap_pixels=" + str(overlap_pixels) + " max_error=" + str(worst_error))
	return true
