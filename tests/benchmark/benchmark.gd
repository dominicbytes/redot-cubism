# SPDX-License-Identifier: MIT
extends SceneTree

const COUNTS := {"static": 1, "vn": 2, "party": 3, "crowd": 8, "masks": 1, "physics": 3, "offscreen": 8, "hidden": 8}
const OWNED := ["loaded_models", "live_drawable_nodes", "live_mesh_resources", "live_material_resources", "live_mask_viewports", "live_compositor_viewports", "live_motion_handles"]
var config: Dictionary
var report: Dictionary = {"status": "FAIL", "samples": [], "errors": []}
var models: Array[CubismModel2D] = []
var lips: Array[CubismLipSync] = []
var view: SubViewport

func _initialize() -> void:
	run.call_deferred()

func require(value: bool, message: String) -> bool:
	if not value: report.errors.append(message)
	return value

func finish() -> void:
	if is_instance_valid(view): view.free()
	var remaining := CubismBuildInfo.get_debug_statistics()
	if remaining.enabled:
		for key: String in OWNED: require(remaining[key] == 0, "ownership after cleanup: " + key)
	report.status = "PASS" if report.errors.is_empty() else "FAIL"
	var output := FileAccess.open(config.output, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write benchmark report")
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("CUBISM_BENCHMARK_", report.status)
	for error: String in report.errors: printerr(error)
	quit(0 if report.status == "PASS" else 1)

func run() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var initial := CubismBuildInfo.get_debug_statistics()
	if not require(initial.enabled, "Benchmarks require a debug addon for CPU counters"):
		finish()
		return
	for key: String in OWNED: require(initial[key] == 0, "nonempty initial ownership: " + key)
	var scenario: String = config.scenario
	var resource := load(config.mask_resource if scenario == "masks" else config.resource) as CubismModelResource
	if not require(resource != null, "Imported model resource must load"):
		finish()
		return
	if scenario == "physics": require(not resource.physics_path.is_empty(), "Physics stress requires physics data")
	if scenario == "vn":
		require(not resource.eye_blink_parameter_ids.is_empty(), "VN requires blink targets")
		require(not resource.lip_sync_parameter_ids.is_empty(), "VN requires lip targets")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1024, 768)
	view = SubViewport.new()
	view.size = Vector2i(1024, 768)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var display := TextureRect.new()
	display.texture = view.get_texture()
	display.size = Vector2(1024, 768)
	root.add_child(display)
	var count: int = COUNTS[scenario]
	for index in count:
		var model := CubismModel2D.new()
		model.playback_process_mode = CubismModel2D.MANUAL
		model.deterministic_seed = 100 + index
		model.enable_physics = scenario == "physics"
		model.enable_pose = false
		model.enable_eye_blink = scenario in ["vn", "crowd", "offscreen", "hidden"]
		model.enable_breath = scenario == "vn"
		model.mask_quality = CubismModel2D.MASK_HIGH if scenario == "masks" else CubismModel2D.MASK_LOW
		model.offscreen_update_mode = CubismModel2D.OFFSCREEN_PAUSED
		view.add_child(model)
		models.append(model)
		if not require(model.load_model(resource) == OK, "Model load failed"):
			finish()
			return
		var canvas := model.get_canvas_info()
		var height := 700.0 if count == 1 else 320.0
		model.scale = Vector2.ONE * height / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
		model.position = Vector2(512, 384) if count == 1 else Vector2(128 + (index % 4) * 256, 192 + (index / 4) * 384)
		if scenario == "offscreen": model.position += Vector2(10000, 10000)
		if scenario == "hidden": model.hide()
		if scenario in ["vn", "party", "physics"]:
			require(model.play_motion(config.motion, CubismMotionPriority.FORCE, true).get_error() == OK, "Motion must exist")
		if scenario == "party": require(model.set_expression(config.expression, 0) == OK, "Expression must exist")
		if scenario == "vn":
			var lip := CubismLipSync.new()
			lip.profile = CubismLipSyncProfile.new()
			view.add_child(lip)
			require(lip.set_target_model(model) == OK, "Lip target must attach")
			lips.append(lip)
	if not report.errors.is_empty():
		finish()
		return
	var previous_usec := Time.get_ticks_usec()
	for frame in int(config.warmup) + int(config.samples):
		var before_frame := Engine.get_process_frames()
		while Engine.get_process_frames() == before_frame: await process_frame
		for index in lips.size(): lips[index].submit_sample(0.5 + 0.5 * sin((frame + index * 7) / 12.0))
		for model in models: model.advance(1.0 / 60.0)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var snapshot := CubismBuildInfo.get_debug_statistics()
		if frame >= int(config.warmup):
			report.samples.append({
				"frame_usec": now - previous_usec,
				"model_update_usec": snapshot.model_update_usec,
				"renderer_update_usec": snapshot.renderer_update_usec,
				"vertex_bytes": snapshot.vertex_bytes_uploaded_last_frame,
				"mask_requests": snapshot.mask_redraws_last_frame,
				"engine_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
				"render_video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
		previous_usec = now
	report.ownership = CubismBuildInfo.get_debug_statistics()
	require(report.ownership.loaded_models == count, "All requested models must be loaded")
	if scenario == "masks": require(report.ownership.live_mask_viewports >= 8, "Mask stress requires at least eight mask compositions")
	if scenario in ["hidden", "offscreen"]:
		for sample: Dictionary in report.samples: require(sample.mask_requests == 0, "Culled masks must not request redraw")
	report.fixture_fingerprint = resource.import_fingerprint
	report.build = CubismBuildInfo.get_versions()
	report.gpu = RenderingServer.get_video_adapter_name()
	report.driver = RenderingServer.get_current_rendering_driver_name()
	display.free()
	finish()
