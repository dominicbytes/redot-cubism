extends RefCounted

static func _render(host: Node, fixture: Dictionary, mode: String, opacity: float) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var container: Node = viewport
	if mode == "canvas_group":
		container = CanvasGroup.new()
		viewport.add_child(container)
	elif mode == "subviewport":
		var inner := SubViewport.new()
		inner.size = viewport.size
		inner.transparent_bg = true
		inner.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.add_child(inner)
		container = inner
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = inner.get_texture()
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		sprite.material = material
		viewport.add_child(sprite)
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	container.add_child(model)
	model.assets = fixture.model
	if not model.is_initialized():
		viewport.free()
		return null
	var canvas: Dictionary = model.get_canvas_info()
	model.position = Vector2(128, 128)
	model.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	model.modulate = Color(0.9, 0.7, 1.0, opacity)
	model.advance(1.0 / 60.0)
	for frame: int in 5:
		await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.free()
	return image

static func run(host: Node, fixture: Dictionary, mode: String, capture_dir: String = "") -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless" or not mode in ["canvas_group", "subviewport"]:
		return false
	var maximum: float = 0.0
	for opacity: float in [1.0, 0.65]:
		var reference: Image = await _render(host, fixture, "direct", opacity)
		var actual: Image = await _render(host, fixture, mode, opacity)
		if reference == null or actual == null:
			return false
		var mismatches: int = 0
		var coverage: int = 0
		for y: int in 256:
			for x: int in 256:
				var a: Color = reference.get_pixel(x, y)
				var b: Color = actual.get_pixel(x, y)
				coverage += int(a.a > 0.05)
				var error: float = 0.0
				for channel: int in 4:
					error = maxf(error, absf(a[channel] - b[channel]))
				maximum = maxf(maximum, error)
				mismatches += int(error > 3.0 / 255.0)
		if not capture_dir.is_empty():
			if reference.save_png(capture_dir.path_join(mode + "-reference.png")) != OK or actual.save_png(capture_dir.path_join(mode + ".png")) != OK:
				return false
		if coverage < 100 or mismatches > 0:
			push_error("CUBISM_FALLBACK_FAIL: " + mode + " opacity=" + str(opacity) + " pixels=" + str(mismatches) + " max_error=" + str(maximum))
			return false
	print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
	print("CUBISM_FALLBACK_PASS mode=" + mode + " cases=2 max_error=" + str(maximum))
	return true
