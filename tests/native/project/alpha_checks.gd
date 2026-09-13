# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func verify_materials(node: Node, expected: bool) -> int:
	var count := 0
	if node is MeshInstance2D and node.material is ShaderMaterial:
		var value: Variant = node.material.get_shader_parameter("premultiplied_alpha")
		if value is bool:
			count += 1
			expect(value == expected, "drawable shader matches imported alpha format")
	for child: Node in node.get_children(true): count += verify_materials(child, expected)
	return count

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var straight := load("res://imported-model.res") as CubismModelResource
	var premultiplied := load("res://alpha-model.res") as CubismModelResource
	if straight == null or premultiplied == null:
		expect(false, "both imported alpha fixtures required")
		finish()
		return
	expect(not straight.get_premultiplied_alpha() and premultiplied.get_premultiplied_alpha(), "resource encodings survive load/export")
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var nodes: Array[CubismModel2D] = []
	for resource: CubismModelResource in [straight, premultiplied]:
		var node := CubismModel2D.new()
		node.name = "AlphaCharacter" + str(nodes.size())
		node.playback_process_mode = CubismModel2D.MANUAL
		node.enable_physics = false
		node.enable_pose = false
		expect(not node.premultiplied_alpha, "unloaded node reports false")
		view.add_child(node)
		expect(node.load_model(resource) == OK and node.is_ready(), "load imported alpha model")
		if not node.is_ready():
			view.free()
			finish()
			return
		expect(node.premultiplied_alpha == resource.get_premultiplied_alpha(), "node reports loaded texture representation")
		node.advance(0.05)
		# Dummy rendering cannot expose shader uniforms. Graphics runs require
		# real drawable materials and check every material's alpha setting.
		if DisplayServer.get_name() != "headless":
			expect(verify_materials(node, resource.get_premultiplied_alpha()) > 0, "native drawable materials present")
		var canvas := node.get_canvas_info()
		node.position = Vector2(128, 128)
		node.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
		nodes.append(node)
	var selected := nodes[1]
	var property_found := false
	for property: Dictionary in selected.get_property_list():
		if property.name == "premultiplied_alpha":
			property_found = true
			expect((property.usage & PROPERTY_USAGE_READ_ONLY) != 0 and (property.usage & PROPERTY_USAGE_STORAGE) == 0, "node alpha is read-only and derived from saved model")
	expect(property_found, "inspector alpha property exists")
	var scene := PackedScene.new()
	expect(scene.pack(selected) == OK and ResourceSaver.save(scene, "user://alpha-scene.tscn") == OK, "save alpha scene")
	var saved := ResourceLoader.load("user://alpha-scene.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if saved:
		var restored := saved.instantiate() as CubismModel2D
		view.add_child(restored)
		expect(restored.is_ready() and restored.premultiplied_alpha, "reopened scene inherits alpha from model")
		restored.free()
	else: expect(false, "load alpha scene")
	expect(DirAccess.remove_absolute("user://alpha-scene.tscn") == OK, "remove saved test scene")
	for resource: CubismModelResource in [straight, premultiplied]:
		var wrong := resource.duplicate(false) as CubismModelResource
		wrong.import_options = resource.import_options.duplicate()
		wrong.import_options["rendering/premultiplied_alpha"] = not resource.get_premultiplied_alpha()
		expect(selected.load_model(wrong) != OK and not selected.is_ready() and not selected.premultiplied_alpha, "reject encoding mismatch in either direction")
	var invalid := straight.duplicate(false) as CubismModelResource
	invalid.import_options = straight.import_options.duplicate()
	invalid.import_options["rendering/premultiplied_alpha"] = 1
	expect(selected.load_model(invalid) != OK and not selected.is_ready(), "reject nonboolean resource alpha")
	invalid = straight.duplicate(false) as CubismModelResource
	invalid.textures = straight.textures.duplicate()
	# PortableCompressedTexture2D.duplicate() sets size before its GL texture
	# exists on pinned Redot. Use an owned image texture for this invalid marker.
	invalid.textures[0] = ImageTexture.create_from_image(straight.textures[0].get_image())
	invalid.textures[0].set_meta("cubism_premultiplied_alpha", 1)
	expect(selected.load_model(invalid) != OK and not selected.is_ready(), "reject nonboolean texture encoding marker")
	var old := straight.duplicate(false) as CubismModelResource
	old.import_options = straight.import_options.duplicate()
	old.import_options.erase("rendering/premultiplied_alpha")
	expect(selected.load_model(old) == OK and not selected.premultiplied_alpha, "older unmarked straight resource remains valid")
	expect(selected.load_model(premultiplied) == OK and selected.premultiplied_alpha, "recover after invalid resource")
	selected.unload_model()
	expect(not selected.premultiplied_alpha, "unload clears alpha state")
	expect(selected.load_model(premultiplied) == OK and selected.reload_model() == OK and selected.premultiplied_alpha, "reload retains alpha encoding")
	expect(not nodes[0].premultiplied_alpha, "other instance retains independent encoding")
	if DisplayServer.get_name() != "headless":
		for node: CubismModel2D in nodes:
			for other: CubismModel2D in nodes: other.visible = other == node
			node.advance(0.05)
			for frame in 3: await RenderingServer.frame_post_draw
			var image := view.get_texture().get_image()
			expect(image.get_used_rect().has_area(), "alpha mode produces visible rendered pixels")
			expect(image.save_png("user://alpha-" + str(node.premultiplied_alpha) + ".png") == OK, "save native alpha capture")
	view.free()
	finish()

func finish() -> void:
	for failure: String in failures: printerr("ALPHA_RUNTIME_FAIL: ", failure)
	print("CUBISM_ALPHA_RUNTIME checks=", checks, " failures=", failures.size(), " graphics=", DisplayServer.get_name() != "headless")
	if failures.is_empty(): print("CUBISM_ALPHA_RUNTIME_PASS")
	quit(0 if failures.is_empty() else 1)
