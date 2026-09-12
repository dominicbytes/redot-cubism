# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func expect(value: bool, message: String) -> bool:
	if not value:
		printerr("CUBISM_LEGACY_BRIDGE_FAIL: " + message)
		quit(1)
	return value

func _run() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://bridge-expected.json"))
	if "--wrong-source" in OS.get_cmdline_user_args():
		expected.sources[0] = "res://unrelated.model3.json"
	var capture_dir := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	for index in expected.scenes.size():
		var scene := (load(expected.scenes[index]) as PackedScene).instantiate()
		var model: GDCubismUserModel = scene if scene is GDCubismUserModel else scene.get_node("Legacy")
		model.playback_process_mode = GDCubismUserModel.MANUAL
		var host: Node = root
		var viewport: SubViewport
		if not capture_dir.is_empty():
			viewport = SubViewport.new()
			viewport.size = Vector2i(256, 256)
			viewport.transparent_bg = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			host = viewport
		host.add_child(scene)
		if not expect(model.is_initialized() and model.assets == expected.sources[index] and model.model == null, "legacy source and initialization"):
			return
		var resource := model.get("_legacy_model") as CubismModelResource
		if not expect(resource != null and resource.source_model_path == expected.sources[index], "imported bridge source"):
			return
		if not expect(resource.layout.get("x", 0.0) == expected.layout_x[index], "distinct same-name model layout"):
			return
		for texture: Texture2D in resource.textures:
			if not expect(texture is PortableCompressedTexture2D and texture.get_width() > 0, "imported texture"):
				return
		var group: String = resource.motion_groups.keys()[0]
		var motion := model.start_motion(group, 0, GDCubismUserModel.PRIORITY_FORCE)
		if not expect(motion != null and motion.get_error() == OK, "motion accepted"):
			return
		var before := PackedFloat64Array()
		for parameter: Object in model.get_parameters():
			before.append(parameter.value)
		var moved := false
		for frame in 120:
			model.advance(1.0 / 60.0)
			var parameters := model.get_parameters()
			for p in parameters.size():
				if not expect(is_finite(parameters[p].value), "finite motion parameter"):
					return
				moved = moved or absf(parameters[p].value - before[p]) > 0.0001
		if not expect(moved, "motion changed parameters"):
			return
		model.start_expression(resource.expressions[0].id)
		model.advance(1.0 / 60.0)
		if viewport != null:
			var canvas := model.get_canvas_info()
			model.position = Vector2(128, 128)
			model.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
			for frame in 4:
				await process_frame
				RenderingServer.force_draw(false)
			var image := viewport.get_texture().get_image()
			if not expect(image.get_used_rect().size.x > 10 and image.get_used_rect().size.y > 10, "visible model pixels"):
				return
			if not expect(image.save_png(capture_dir.path_join("legacy-" + str(index) + ".png")) == OK, "capture written"):
				return
		host.remove_child(scene)
		if not expect(not model.is_initialized(), "tree exit unloads"):
			return
		host.add_child(scene)
		if not expect(model.is_initialized() and model.get("_legacy_model") == resource, "tree reentry retains bridge"):
			return
		scene.free()
		if viewport != null:
			viewport.free()
	print("CUBISM_LEGACY_BRIDGE_PASS models=", expected.scenes.size())
	quit()
