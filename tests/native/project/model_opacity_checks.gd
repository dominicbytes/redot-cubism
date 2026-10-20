# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.model))
	var directory: String = fixture.model.get_base_dir()
	var entries: Array = []
	for opacity: float in [1.0, 0.5, 0.0]:
		var filename := "test-opacity-%d.motion3.json" % entries.size()
		write_json(directory.path_join(filename), {"Version": 3,
			"Meta": {"Duration": 1.0, "Fps": 60.0, "Loop": false, "AreBeziersRestricted": true,
				"CurveCount": 1, "TotalSegmentCount": 1, "TotalPointCount": 2, "UserDataCount": 0, "TotalUserDataSize": 0},
			"Curves": [{"Target": "Model", "Id": "Opacity", "Segments": [0.0, opacity, 0, 1.0, opacity]}]})
		entries.append({"File": filename, "FadeInTime": 0.0, "FadeOutTime": 0.0})
	manifest.FileReferences.Motions = {"Opacity": entries}
	manifest.FileReferences.erase("Physics")
	manifest.FileReferences.erase("Pose")
	var source := directory.path_join("test-opacity.model3.json")
	write_json(source, manifest)
	var built := CubismModelFactory.build(source)
	expect(built.ok, "authored opacity fixture builds")
	if not built.ok:
		finish()
		return
	var straight: CubismModelResource = built.model
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for premultiplied: bool in [false, true]:
		var resource := straight.duplicate(false) as CubismModelResource
		resource.import_options = {"rendering/premultiplied_alpha": premultiplied}
		resource.textures = []
		for texture: Texture2D in straight.textures:
			var image := texture.get_image()
			if premultiplied: image.premultiply_alpha()
			var converted := ImageTexture.create_from_image(image)
			converted.set_meta("cubism_premultiplied_alpha", premultiplied)
			resource.textures.append(converted)
		for fallback: bool in [false, true]:
			var node := CubismModel2D.new()
			node.playback_process_mode = CubismModel2D.MANUAL
			node.enable_physics = false
			node.enable_pose = false
			node.rendering_mode = CubismModel2D.SUBVIEWPORT_FALLBACK if fallback else CubismModel2D.DIRECT
			view.add_child(node)
			expect(node.load_model(resource) == OK, "opacity fixture loads in each alpha/composition mode")
			if not node.is_ready():
				node.free()
				continue
			var canvas := node.get_canvas_info()
			node.position = Vector2(64, 64)
			node.scale = Vector2.ONE * 128.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
			var baseline: Dictionary = {}
			for index: int in 3:
				var opacity := [1.0, 0.5, 0.0][index] as float
				var handle := node.play_motion_from_group(&"Opacity", index, CubismMotionPriority.FORCE)
				expect(handle.get_error() == OK, "authored opacity motion starts")
				node.advance(0.05)
				if DisplayServer.get_name() == "headless": continue
				var materials := 0
				var runtime := node.get_node("CubismRuntime") as GDCubismUserModel
				for child: MeshInstance2D in runtime.get_meshes().values():
					var color: Vector4 = child.material.get_shader_parameter("color_base")
					if index == 0: baseline[child.name] = color
					var full: Vector4 = baseline[child.name]
					expect(absf(color.w - full.w * opacity) < 0.0001, "authored opacity multiplies final material alpha once")
					expect(absf(color.x - (full.x * opacity if premultiplied else full.x)) < 0.0001, "RGB follows texture alpha representation")
					materials += 1
				expect(materials > 0, "drawable opacity uniforms inspected")
				for frame in 3: await RenderingServer.frame_post_draw
				var image := view.get_texture().get_image()
				expect(image.get_used_rect().has_area() if opacity > 0 else not image.get_used_rect().has_area(), "authored zero opacity removes rendered coverage")
			node.free()
	view.free()
	if DisplayServer.get_name() != "headless":
		print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method()}))
	finish()

func finish() -> void:
	for failure: String in failures: printerr("CUBISM_MODEL_OPACITY_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_MODEL_OPACITY_PASS checks=", checks, " graphics=", DisplayServer.get_name() != "headless")
	quit(0 if failures.is_empty() else 1)
