# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var warnings: Array[String] = []
var captures := []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func capture(view: SubViewport, frames := 4) -> Image:
	for frame in frames: await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func compare(reference: Image, actual: Image, label: String) -> void:
	var error := 0
	var bad := 0
	var left := reference.get_data()
	var right := actual.get_data()
	expect(left.size() == right.size(), label + ": same image format")
	if left.size() != right.size(): return
	for index in left.size():
		var difference := absi(int(left[index]) - int(right[index]))
		error = maxi(error, difference)
		bad += int(difference > 3)
	expect(bad == 0, label + ": direct/fallback parity, max byte error=" + str(error) + " bad channels=" + str(bad))
	expect(reference.save_png("user://fallback-" + label + "-direct.png") == OK, "save direct capture")
	expect(actual.save_png("user://fallback-" + label + "-fallback.png") == OK, "save fallback capture")
	captures.append({"case": label, "maximum_byte_error": error, "bad_channels": bad})

func compare_modes(view: SubViewport, nodes: Array[CubismModel2D], label: String) -> void:
	for node: CubismModel2D in nodes: node.rendering_mode = CubismModel2D.DIRECT
	var direct := await capture(view)
	for node: CubismModel2D in nodes: node.rendering_mode = CubismModel2D.SUBVIEWPORT_FALLBACK
	var fallback := await capture(view, 1)
	for node: CubismModel2D in nodes: expect(node.rendering_error.is_empty(), label + ": supported fallback " + node.rendering_error)
	compare(direct, fallback, label)

func find_named(node: Node, name_to_find: String) -> Node:
	if node.name == name_to_find: return node
	for child: Node in node.get_children(true):
		var found := find_named(child, name_to_find)
		if found: return found
	return null

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		expect(false, "real graphics required")
		finish()
		return
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var background := ColorRect.new()
	background.size = Vector2(256, 256)
	background.color = Color(0.2, 0.4, 0.8, 0.5)
	view.add_child(background)
	var parent := Node2D.new()
	view.add_child(parent)
	var nodes: Array[CubismModel2D] = []
	for filename: String in ["imported-model.res", "alpha-model.res"]:
		var resource := load("res://" + filename) as CubismModelResource
		if resource == null:
			expect(false, "requires imported straight and premultiplied fixtures")
			view.free()
			finish()
			return
		resource = resource.duplicate(false) as CubismModelResource
		resource.layout = {}
		var node := CubismModel2D.new()
		node.name = "Character" + str(nodes.size())
		node.playback_process_mode = CubismModel2D.MANUAL
		node.enable_physics = false
		node.enable_pose = false
		node.runtime_warning.connect(func(_code: int, message: String) -> void: warnings.append(message))
		parent.add_child(node)
		expect(node.rendering_mode == CubismModel2D.DIRECT, "direct default")
		expect(node.load_model(resource) == OK and node.is_ready(), "load fallback fixture")
		if not node.is_ready():
			view.free()
			finish()
			return
		var canvas := node.get_canvas_info()
		node.scale = Vector2.ONE * 220.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
		node.position = Vector2(128, 128)
		node.advance(0.05)
		nodes.append(node)
	var selected := nodes[0]
	nodes[1].hide()
	var scale := selected.scale
	for pose: String in ["normal", "rotated", "mirrored", "clipped", "canvas-zoom", "viewport-stretch", "parent-modulate", "tiny"]:
		selected.position = Vector2(128, 128)
		selected.rotation = 0.31 if pose == "rotated" else 0.0
		selected.scale = scale * Vector2(-0.8, 1.1) if pose == "mirrored" else scale
		if pose == "tiny": selected.scale *= 0.002
		if pose == "clipped": selected.position = Vector2(18.3, 32.7)
		view.canvas_transform = Transform2D(0, Vector2(-25, 10)).scaled(Vector2(1.1, 0.8)) if pose == "canvas-zoom" else Transform2D.IDENTITY
		view.size_2d_override = Vector2i(128, 128) if pose == "viewport-stretch" else Vector2i.ZERO
		view.size_2d_override_stretch = pose == "viewport-stretch"
		parent.modulate = Color(0.8, 0.7, 0.9, 0.65) if pose == "parent-modulate" else Color.WHITE
		await compare_modes(view, [selected], pose)
	view.canvas_transform = Transform2D.IDENTITY
	view.size_2d_override = Vector2i.ZERO
	view.size_2d_override_stretch = false
	parent.modulate = Color.WHITE
	selected.position = Vector2(110, 128)
	selected.scale = scale
	nodes[1].position = Vector2(145, 125)
	nodes[1].modulate = Color(0.8, 0.9, 0.7, 0.7)
	nodes[1].show()
	await compare_modes(view, nodes, "overlap")
	selected.z_index = 1
	await compare_modes(view, nodes, "overlap-reordered")
	for node: CubismModel2D in nodes: node.hide()
	var empty := await capture(view)
	selected.show()
	var visible := await capture(view)
	expect(empty.get_data() != visible.get_data(), "fallback reference actually draws model")
	var runtime := selected.get_child(0, true) as GDCubismUserModel
	var mesh_id: int = runtime.get_meshes().values()[0].mesh.get_instance_id()
	var motion: CubismMotionHandle
	if OS.get_cmdline_user_args().has("--motion"):
		motion = selected.play_motion(&"Cue/0", CubismMotionPriority.FORCE, true)
		expect(motion.get_error() == OK, "start motion for mode-switch preservation")
	selected.advance(0.05)
	var elapsed := motion.get_elapsed_seconds() if motion else 0.0
	var before := selected.get_parameter_value(&"ParamAngleX")
	selected.paused = true
	selected.position += Vector2(15, 0)
	await compare_modes(view, [selected], "paused-moved")
	selected.position += Vector2(9, -4)
	var moved := await capture(view, 1)
	selected.rendering_mode = CubismModel2D.DIRECT
	var moved_reference := await capture(view)
	compare(moved_reference, moved, "paused-first-frame")
	selected.rendering_mode = CubismModel2D.SUBVIEWPORT_FALLBACK
	await capture(view)
	expect(runtime.get_meshes().values()[0].mesh.get_instance_id() == mesh_id and selected.get_parameter_value(&"ParamAngleX") == before, "switching and frame refresh preserve native geometry and pose")
	if motion: expect(not motion.is_finished() and motion.get_elapsed_seconds() == elapsed, "frame refresh does not replace or advance motion")
	var atlas := find_named(selected, "CubismDrawableAtlas") as SubViewport
	expect(atlas != null and atlas.size.x <= 4096 and atlas.size.y <= 4096 and atlas.size.x * atlas.size.y <= 8388608, "bounded per-model atlas")
	var packed := PackedScene.new()
	expect(packed.pack(selected) == OK, "pack fallback scene")
	expect(packed.get_state().get_node_count() == 1, "transient renderer nodes excluded from scene")
	expect(ResourceSaver.save(packed, "user://fallback-scene.tscn") == OK, "save fallback scene")
	var saved := ResourceLoader.load("user://fallback-scene.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	expect(saved != null, "reopen fallback scene")
	var restored := saved.instantiate() as CubismModel2D
	expect(restored.rendering_mode == CubismModel2D.SUBVIEWPORT_FALLBACK, "scene retains explicit mode")
	parent.add_child(restored)
	restored.hide()
	restored.free()
	expect(DirAccess.remove_absolute("user://fallback-scene.tscn") == OK, "remove saved test scene")
	expect(warnings.is_empty(), "no warnings for supported cases: " + str(warnings))
	view.size = Vector2i(40, 40)
	selected.position = Vector2(20, 20)
	await capture(view)
	expect(not selected.rendering_error.is_empty() and warnings.size() == 1, "unsupported target produces one actionable warning")
	expect(selected.rendering_mode == CubismModel2D.SUBVIEWPORT_FALLBACK, "unsupported target does not silently switch modes")
	await capture(view)
	expect(warnings.size() == 1, "unsupported warning is not emitted each frame")
	view.size = Vector2i(1024, 1024)
	selected.position = Vector2(512, 512)
	selected.scale = scale * 4.0
	await capture(view)
	expect(selected.rendering_error.contains("allocation limit") and warnings.size() == 2, "reject oversized atlas before allocating it")
	selected.scale = scale
	view.size = Vector2i(256, 256)
	selected.position = Vector2(128, 128)
	await capture(view)
	expect(selected.rendering_error.is_empty(), "recover after target becomes supported")
	selected.rendering_mode = CubismModel2D.DIRECT
	await capture(view)
	expect(find_named(selected, "CubismDrawableAtlas") == null, "direct mode frees fallback targets")
	selected.rendering_mode = CubismModel2D.SUBVIEWPORT_FALLBACK
	await capture(view)
	selected.unload_model()
	expect(find_named(selected, "CubismDrawableAtlas") == null and selected.rendering_error.is_empty(), "unload frees fallback targets and errors")
	view.free()
	finish()

func finish() -> void:
	for failure: String in failures: printerr("FALLBACK_FAIL: ", failure)
	var file := FileAccess.open("user://fallback-report.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks": checks, "failures": failures, "captures": captures}, "\t") + "\n")
	print("CUBISM_FALLBACK checks=", checks, " failures=", failures.size())
	if failures.is_empty(): print("CUBISM_FALLBACK_PASS")
	quit(0 if failures.is_empty() else 1)
