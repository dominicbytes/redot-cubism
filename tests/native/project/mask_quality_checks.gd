# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func masks(node: Node) -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	for child: Node in node.get_children(true):
		if child is SubViewport: result.append(child)
		elif child is GDCubismUserModel: result.append_array(masks(child))
	return result

func bounded(node: Node, limit: int, count: int) -> void:
	var targets := masks(node)
	expect(targets.size() == count and count > 0, "mask composition count stable")
	for target: SubViewport in targets:
		expect(target.size.x >= 2 and target.size.y >= 2 and target.size.x <= limit and target.size.y <= limit,
			"mask fits renderable bounds at limit " + str(limit) + ": " + str(target.size))

func capture(viewport: SubViewport) -> Image:
	for frame in 3: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		expect(false, "mask quality requires real graphics")
		finish()
		return
	var resource := load("res://imported-model.res") as CubismModelResource
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var node := CubismModel2D.new()
	node.name = "MaskCharacter"
	node.playback_process_mode = CubismModel2D.MANUAL
	node.enable_physics = false
	node.enable_pose = false
	expect(node.mask_quality == CubismModel2D.MASK_MODEL and node.custom_mask_limit == 1024, "default inherited mask quality")
	viewport.add_child(node)
	expect(node.load_model(resource) == OK, "preferred fixture loads")
	if not node.is_ready():
		viewport.free()
		finish()
		return
	var canvas := node.get_canvas_info()
	node.position = Vector2(128, 128)
	node.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	node.advance(0.05)
	var count := masks(node).size()
	var runtime := node.get_child(0, true) as GDCubismUserModel
	for quality: int in [0, 1, 2]:
		var imported := resource.duplicate(true) as CubismModelResource
		imported.import_options["rendering/mask_quality"] = quality
		expect(node.load_model(imported) == OK, "load imported mask quality")
		node.advance(0.05)
		var limit: int = [512, 1024, 2048][quality]
		expect(runtime.mask_viewport_size == limit, "imported quality reaches renderer")
		bounded(node, limit, count)
		node.mask_quality = CubismModel2D.MASK_CUSTOM
		node.custom_mask_limit = 127
		expect(node.reload_model() == OK and runtime.mask_viewport_size == 127, "explicit override wins on resource reload")
		node.mask_quality = CubismModel2D.MASK_MODEL
		expect(runtime.mask_viewport_size == limit, "returning to model quality restores imported limit")
	var inherited_scene := PackedScene.new()
	expect(inherited_scene.pack(node) == OK, "pack inherited quality")
	expect(ResourceSaver.save(inherited_scene, "user://inherited-quality.tscn") == OK, "save inherited quality")
	var saved_inherited := ResourceLoader.load("user://inherited-quality.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if saved_inherited:
		var restored := saved_inherited.instantiate() as CubismModel2D
		viewport.add_child(restored)
		restored.advance(0.05)
		var restored_runtime := restored.get_child(0, true) as GDCubismUserModel
		expect(restored.mask_quality == CubismModel2D.MASK_MODEL and restored_runtime.mask_viewport_size == 2048, "saved scene inherits imported high quality")
		bounded(restored, 2048, count)
		restored.free()
	else: expect(false, "load inherited-quality scene")
	expect(DirAccess.remove_absolute("user://inherited-quality.tscn") == OK, "remove inherited test scene")
	var old_resource := resource.duplicate(true) as CubismModelResource
	old_resource.import_options.erase("rendering/mask_quality")
	expect(node.load_model(old_resource) == OK and runtime.mask_viewport_size == 1024, "older resource inherits medium")
	var invalid_resource := resource.duplicate(true) as CubismModelResource
	invalid_resource.import_options["rendering/mask_quality"] = true
	expect(node.load_model(invalid_resource) != OK and not node.is_ready(), "invalid imported quality fails runtime validation")
	expect(node.load_model(resource) == OK, "restore original resource")
	node.advance(0.05)
	bounded(node, 1024, count)
	var original := await capture(viewport)
	expect(original.get_used_rect().size.x > 0 and original.get_used_rect().size.y > 0, "default mask quality produces visible pixels")
	for entry in [[CubismModel2D.MASK_LOW, 512], [CubismModel2D.MASK_HIGH, 2048], [CubismModel2D.MASK_CUSTOM, 127]]:
		node.custom_mask_limit = 127
		node.mask_quality = entry[0]
		node.advance(0.05)
		bounded(node, entry[1], count)
		await capture(viewport)
	var warnings: Array[int] = []
	node.runtime_warning.connect(func(code: int, _message: String): warnings.append(code))
	node.call("set_mask_quality", -1)
	node.call("set_mask_quality", 99)
	expect(warnings == [ERR_INVALID_PARAMETER, ERR_INVALID_PARAMETER] and node.mask_quality == CubismModel2D.MASK_CUSTOM, "invalid quality preserves previous value")
	for requested: int in [-9223372036854775807, -1, 0, 1, 2, 127, 4096, 8192, 9223372036854775807]:
		node.custom_mask_limit = requested
		var limit := clampi(requested, 2, 4096)
		expect(node.custom_mask_limit == limit, "custom limit clamps before narrowing integer")
		node.advance(0.05)
		bounded(node, limit, count)
		await capture(viewport)
	node.custom_mask_limit = 127
	expect(node.reload_model() == OK and node.mask_quality == CubismModel2D.MASK_CUSTOM and node.custom_mask_limit == 127, "reload retains quality settings")
	node.advance(0.05)
	bounded(node, 127, count)
	var packed := PackedScene.new()
	expect(packed.pack(node) == OK, "pack quality settings")
	var scene_path := "user://mask-quality-settings.tscn"
	expect(ResourceSaver.save(packed, scene_path) == OK, "save quality settings")
	var saved := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if saved:
		var restored := saved.instantiate() as CubismModel2D
		expect(restored.mask_quality == CubismModel2D.MASK_CUSTOM and restored.custom_mask_limit == 127, "settings survive scene reload")
		viewport.add_child(restored)
		restored.advance(0.05)
		bounded(restored, 127, count)
		restored.free()
	else: expect(false, "saved scene loads")
	expect(DirAccess.remove_absolute(scene_path) == OK, "remove test save")
	node.mask_quality = CubismModel2D.MASK_MEDIUM
	node.advance(0.05)
	var restored_image := await capture(viewport)
	expect(original.get_data() == restored_image.get_data(), "returning to medium restores identical pixels")
	# The legacy wrapper is a migration oracle, not official SDK parity. Match
	# the explicit quality so this comparison tests ownership/rendering behavior.
	node.hide()
	var legacy := GDCubismUserModel.new()
	legacy.playback_process_mode = GDCubismUserModel.MANUAL
	legacy.physics_evaluate = false
	legacy.pose_update = false
	legacy.mask_viewport_size = 1024
	legacy.position = node.position
	legacy.scale = node.scale
	viewport.add_child(legacy)
	legacy.model = resource
	legacy.advance(0.05)
	var legacy_image := await capture(viewport)
	expect(original.get_data() == legacy_image.get_data(), "same explicit limit matches legacy pixels")
	for entry in [[CubismModel2D.MASK_LOW, 512], [CubismModel2D.MASK_MEDIUM, 1024], [CubismModel2D.MASK_HIGH, 2048], [CubismModel2D.MASK_CUSTOM, 127]]:
		legacy.hide()
		node.show()
		node.mask_quality = entry[0]
		node.custom_mask_limit = 127
		node.advance(0.05)
		var preferred_image := await capture(viewport)
		node.hide()
		legacy.show()
		legacy.mask_viewport_size = entry[1]
		legacy.advance(0.05)
		var comparison := await capture(viewport)
		expect(preferred_image.get_data() == comparison.get_data(), "quality selects the matching legacy limit " + str(entry[1]))
	for limit: int in [0, -1, 1, 2, 128, 8192, 2147483647]:
		legacy.mask_viewport_size = limit
		legacy.advance(0.05)
		bounded(legacy, 4096 if limit <= 0 else clampi(limit, 2, 4096), count)
		await capture(viewport)
	viewport.free()
	await process_frame
	expect(await preload("res://renderer_transform_checks.gd").run(root, {"resource": resource}), "bounded masks survive singular, mirrored, tiny and huge transforms")
	finish()

func finish() -> void:
	print("CUBISM_MASK_QUALITY " + JSON.stringify({"checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method()}))
	if failures.is_empty(): print("CUBISM_MASK_QUALITY_PASS")
	quit(0 if failures.is_empty() else 1)
