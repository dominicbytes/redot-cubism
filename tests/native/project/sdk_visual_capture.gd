# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(fixture.size[0]), int(fixture.size[1]))
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var result := {"id": fixture.id, "models": [], "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}
	if result.display == "headless":
		push_error("SDK visual capture requires a real graphics backend")
		quit(1)
		return
	for state: Dictionary in fixture.models:
		var resource := load(state.resource) as CubismModelResource
		if resource == null or resource.source_hash != state.manifest_sha256 or FileAccess.get_sha256(resource.moc_path) != state.moc_sha256:
			push_error("SDK visual manifest/MOC identity mismatch")
			quit(1)
			return
		if resource.texture_paths.size() != state.texture_sha256.size():
			push_error("SDK visual texture count mismatch")
			quit(1)
			return
		for index in resource.texture_paths.size():
			if FileAccess.get_sha256(resource.texture_paths[index]) != state.texture_sha256[index]:
				push_error("SDK visual source texture identity mismatch")
				quit(1)
				return
		resource = resource.duplicate(false) as CubismModelResource
		resource.layout = {} # The reference MVP already includes the model layout.
		var model := CubismModel2D.new()
		model.playback_process_mode = CubismModel2D.MANUAL
		model.enable_physics = false
		model.enable_pose = false
		model.enable_eye_blink = false
		model.enable_breath = false
		viewport.add_child(model)
		if model.load_model(resource) != OK or model.premultiplied_alpha != state.premultiplied_alpha:
			push_error("SDK visual model load or texture encoding mismatch: " + model.get_last_error())
			quit(1)
			return
		model.mask_quality = int(state.mask_quality)
		var unit: float = model.get_canvas_info().pixels_per_unit
		var m: Array = state.mvp
		var half_size := Vector2(viewport.size) * 0.5
		model.transform = Transform2D(Vector2(m[0] * half_size.x, -m[1] * half_size.y) / unit,
			Vector2(-m[4] * half_size.x, m[5] * half_size.y) / unit,
			Vector2((m[12] + 1.0) * half_size.x, (1.0 - m[13]) * half_size.y))
		for id: String in model.get_parameter_ids():
			if not state.parameters.has(id) or model.set_parameter_value(id, state.parameters[id]) != OK:
				push_error("SDK visual parameter assignment failed")
				quit(1)
				return
		for id: String in model.get_part_ids():
			if not state.parts.has(id) or model.set_part_opacity(id, state.parts[id]) != OK:
				push_error("SDK visual part assignment failed")
				quit(1)
				return
		model.advance(1.0 / 60.0)
		var actual := {"resource": state.resource, "parameters": {}, "parts": {}, "premultiplied_alpha": model.premultiplied_alpha}
		for id: String in model.get_parameter_ids(): actual.parameters[id] = model.get_parameter_value(id)
		var runtime := model.get_child(0, true) as GDCubismUserModel
		for part: GDCubismPartOpacity in runtime.get_part_opacities(): actual.parts[part.id] = part.value
		result.models.append(actual)
	for frame in 5: await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(args[1].path_join("actual.png")) != OK:
		push_error("Cannot save SDK visual capture")
		quit(1)
		return
	var output := FileAccess.open(args[1].path_join("actual.json"), FileAccess.WRITE)
	if output == null:
		push_error("Cannot save SDK visual state")
		quit(1)
		return
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	viewport.free()
	print("CUBISM_SDK_VISUAL_CAPTURE_PASS")
	quit()
