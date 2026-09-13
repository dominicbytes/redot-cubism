# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var redraw_results: Array[Dictionary] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func masks(node: Node) -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	for child: Node in node.get_children(true):
		if child is SubViewport: result.append(child)
		elif child is GDCubismUserModel: result.append_array(masks(child))
	return result

func density(node: CubismModel2D, expected: float, label: String) -> void:
	var targets := masks(node)
	expect(not targets.is_empty(), label + " has masks")
	for target: SubViewport in targets:
		expect(absf(target.canvas_transform.x.length() - expected) < 0.00001
			and absf(target.canvas_transform.y.length() - expected) < 0.00001, label + " uniform pixel density")
		expect(target.size.x >= 2 and target.size.y >= 2 and target.size.x <= 4096 and target.size.y <= 4096, label + " bounded target")

func disabled(node: CubismModel2D, label: String) -> void:
	for target: SubViewport in masks(node):
		expect(target.render_target_update_mode == SubViewport.UPDATE_DISABLED, label)

func channels(node: CubismModel2D, alpha: float) -> void:
	for target: SubViewport in masks(node):
		for mesh: MeshInstance2D in target.get_children():
			(mesh.material as ShaderMaterial).set_shader_parameter("channel", Vector4(0, 0, 0, alpha))

func capture(viewport: SubViewport) -> Image:
	for frame in 3: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func redraws(node: CubismModel2D, policy: int, speed: float) -> void:
	node.position = Vector2(100000, 100000)
	node.offscreen_update_mode = CubismModel2D.OFFSCREEN_ALWAYS
	channels(node, 0)
	node.advance(0.01)
	var target := masks(node)[0]
	var previous := (await capture(target)).get_data()
	node.offscreen_update_mode = policy
	node.speed_scale = speed
	var started := Time.get_ticks_usec()
	var frames := 0
	var changed := 0
	var last_request_start := -1
	while (frames < 16 or Time.get_ticks_usec() - started < 350000) and frames < 120:
		# Change alpha monotonically so image changes prove actual GPU redraws.
		# Reading the SubViewport's UPDATE_ONCE property alone cannot prove this.
		channels(node, float(frames + 1) / 121.0)
		var before := Time.get_ticks_usec()
		for step in 5: node.advance(0.01)
		var after := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var current := target.get_texture().get_image().get_data()
		if current != previous:
			changed += 1
			if policy == CubismModel2D.OFFSCREEN_REDUCED and last_request_start >= 0:
				expect(after - last_request_start >= 100000, "redraw requests respect 100 ms clock brackets")
			last_request_start = before
		previous = current
		frames += 1
	var elapsed := Time.get_ticks_usec() - started
	if policy == CubismModel2D.OFFSCREEN_ALWAYS: expect(changed == frames, "always redraws every submitted frame")
	elif policy == CubismModel2D.OFFSCREEN_PAUSED: expect(changed == 0, "paused offscreen texture remains unchanged")
	else: expect(changed >= 2 and changed <= ceili(float(elapsed) / 100000.0) + 1, "reduced redraw cadence is bounded and live")
	redraw_results.append({"policy": policy, "speed": speed, "frames": frames, "redraws": changed, "elapsed_usec": elapsed})
	node.speed_scale = 1
	channels(node, 1)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		expect(false, "mask policy requires real graphics")
		finish()
		return
	var resource := load("res://imported-model.res") as CubismModelResource
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var node := CubismModel2D.new()
	node.name = "MaskPolicyCharacter"
	node.playback_process_mode = CubismModel2D.MANUAL
	node.enable_physics = false
	node.enable_pose = false
	node.mask_quality = CubismModel2D.MASK_CUSTOM
	node.custom_mask_limit = 4096
	expect(node.offscreen_update_mode == CubismModel2D.OFFSCREEN_PAUSED, "default preserves offscreen suspension")
	node.offscreen_update_mode = CubismModel2D.OFFSCREEN_ALWAYS
	viewport.add_child(node)
	expect(node.load_model(resource) == OK, "policy fixture loads")
	if not node.is_ready() or masks(node).is_empty():
		expect(false, "loaded fixture has masks")
		viewport.free()
		finish()
		return
	var canvas := node.get_canvas_info()
	var base := 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	node.position = Vector2(128, 128)
	node.scale = Vector2.ONE * base
	node.advance(0.05)
	density(node, base, "fit to viewport")
	var original := await capture(viewport)
	for factor: float in [0.5, 1, 2, 4]:
		node.scale = Vector2.ONE * base * factor
		node.advance(0.05)
		density(node, base * factor, "uniform zoom " + str(factor))
	node.scale = Vector2(base * -2, base * 0.5)
	node.rotation = 0.4
	node.advance(0.05)
	density(node, base * 2, "rotated nonuniform reflection")
	node.transform = Transform2D(Vector2(base, 0), Vector2(base, base), Vector2(128, 128))
	node.advance(0.05)
	density(node, base * (1 + sqrt(5.0)) / 2, "shear maximum stretch")
	node.transform = Transform2D(Vector2(base, 0), Vector2(0, base), Vector2(128, 128))
	var camera := Camera2D.new()
	camera.position = Vector2(128, 128)
	camera.zoom = Vector2(2, 0.75)
	camera.ignore_rotation = false
	camera.rotation = 0.2
	viewport.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	node.advance(0.05)
	density(node, base * 2, "camera zoom and rotation")
	camera.free()
	viewport.canvas_transform = Transform2D.IDENTITY
	var layer := CanvasLayer.new()
	layer.transform = Transform2D(Vector2(1.5, 0), Vector2(0, 0.75), Vector2.ZERO)
	viewport.add_child(layer)
	node.reparent(layer, false)
	node.advance(0.05)
	density(node, base * 1.5, "canvas layer scaling")
	node.reparent(viewport, false)
	layer.free()
	viewport.size = Vector2i(512, 512)
	viewport.size_2d_override = Vector2i(256, 256)
	viewport.size_2d_override_stretch = true
	node.advance(0.05)
	density(node, base * 2, "viewport stretch uses physical pixels")
	viewport.size_2d_override_stretch = false
	viewport.size_2d_override = Vector2i.ZERO
	viewport.size = Vector2i(256, 256)
	viewport.global_canvas_transform = Transform2D(Vector2(1.25, 0), Vector2(0, 0.5), Vector2.ZERO)
	node.advance(0.05)
	density(node, base * 1.25, "global canvas scaling")
	viewport.global_canvas_transform = Transform2D(0, Vector2(100000, 100000))
	node.offscreen_update_mode = CubismModel2D.OFFSCREEN_PAUSED
	node.advance(0.05)
	disabled(node, "global canvas translation participates in culling")
	viewport.global_canvas_transform = Transform2D.IDENTITY
	node.offscreen_update_mode = CubismModel2D.OFFSCREEN_ALWAYS
	node.transform = Transform2D(Vector2.ZERO, Vector2(0, base), Vector2(128, 128))
	node.advance(0.05)
	disabled(node, "always policy cannot draw a singular transform")
	node.transform = Transform2D(Vector2(base, 0), Vector2(0, base), Vector2(128, 128))
	for policy: int in [CubismModel2D.OFFSCREEN_ALWAYS, CubismModel2D.OFFSCREEN_REDUCED, CubismModel2D.OFFSCREEN_PAUSED]:
		await redraws(node, policy, 1)
		node.hide()
		node.advance(0.05)
		disabled(node, "hidden masks suspend under every policy")
		node.show()
	await redraws(node, CubismModel2D.OFFSCREEN_REDUCED, 0.25)
	await redraws(node, CubismModel2D.OFFSCREEN_REDUCED, 4)
	var warnings: Array[int] = []
	node.runtime_warning.connect(func(code: int, _message: String): warnings.append(code))
	node.call("set_offscreen_update_mode", -1)
	node.call("set_offscreen_update_mode", 99)
	expect(warnings == [ERR_INVALID_PARAMETER, ERR_INVALID_PARAMETER] and node.offscreen_update_mode == CubismModel2D.OFFSCREEN_REDUCED, "invalid policies preserve the active mode")
	var packed := PackedScene.new()
	expect(packed.pack(node) == OK and ResourceSaver.save(packed, "user://mask-policy.tscn") == OK, "save offscreen policy")
	var saved := ResourceLoader.load("user://mask-policy.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if saved:
		var restored := saved.instantiate() as CubismModel2D
		expect(restored.offscreen_update_mode == CubismModel2D.OFFSCREEN_REDUCED, "policy survives scene save/reopen")
		restored.free()
	else: expect(false, "policy scene loads")
	expect(DirAccess.remove_absolute("user://mask-policy.tscn") == OK, "remove test policy save")
	if OS.get_cmdline_user_args().has("--motion"):
		var reference := CubismModel2D.new()
		reference.playback_process_mode = CubismModel2D.MANUAL
		reference.enable_physics = false
		reference.enable_pose = false
		viewport.add_child(reference)
		for policy: int in [CubismModel2D.OFFSCREEN_ALWAYS, CubismModel2D.OFFSCREEN_REDUCED, CubismModel2D.OFFSCREEN_PAUSED]:
			expect(node.reload_model() == OK and reference.load_model(resource) == OK, "reload motion comparison")
			node.offscreen_update_mode = policy
			var handle := node.play_motion(&"Cue/0", CubismMotionPriority.FORCE)
			var comparison := reference.play_motion(&"Cue/0", CubismMotionPriority.FORCE)
			for frame in 30:
				node.advance(0.05)
				reference.advance(0.05)
				expect(is_equal_approx(handle.get_elapsed_seconds(), comparison.get_elapsed_seconds()) and is_equal_approx(node.get_parameter_value(&"ParamAngleX"), reference.get_parameter_value(&"ParamAngleX")), "offscreen policy preserves motion clock and pose")
			expect(handle.is_finished() and handle.get_reason() == CubismMotionHandle.COMPLETED, "offscreen motion completes normally")
		reference.free()
	node.position = Vector2(128, 128)
	expect(node.reload_model() == OK, "restore visible model")
	node.advance(0.05)
	var restored_image := await capture(viewport)
	expect(original.get_data() == restored_image.get_data(), "restoring visibility and transforms restores pixels")
	viewport.free()
	await process_frame
	finish()

func finish() -> void:
	print("CUBISM_MASK_POLICY " + JSON.stringify({"checks": checks, "failures": failures, "redraws": redraw_results, "renderer": RenderingServer.get_current_rendering_method()}))
	if failures.is_empty(): print("CUBISM_MASK_POLICY_PASS")
	quit(0 if failures.is_empty() else 1)
