# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://imported-model.res") as CubismModelResource
	var capture_dir: String = OS.get_cmdline_user_args()[0]
	var ok := true
	for transformed: bool in [false, true]:
		var reference: Image
		for preferred: bool in [false, true]:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(256, 256)
			viewport.transparent_bg = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var node: Node2D
			if preferred:
				var model := CubismModel2D.new()
				model.playback_process_mode = CubismModel2D.MANUAL
				model.enable_physics = false
				model.model = resource
				node = model
			else:
				var model := GDCubismUserModel.new()
				model.playback_process_mode = GDCubismUserModel.MANUAL
				model.physics_evaluate = false
				model.model = resource
				node = model
			viewport.add_child(node)
			var canvas: Dictionary = node.call("get_canvas_info")
			node.position = Vector2(128, 128)
			node.scale = Vector2.ONE * 256.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
			if transformed:
				node.scale.x *= -1.0
				node.rotation = 0.2
			for frame in 60: node.call("advance", 1.0 / 60.0)
			if transformed:
				if preferred:
					(node as CubismModel2D).enable_pose = false
					ok = ok and (node as CubismModel2D).set_part_opacity(StringName((node as CubismModel2D).get_part_ids()[0]), 0.5) == OK
				else:
					(node as GDCubismUserModel).pose_update = false
					(node as GDCubismUserModel).get_part_opacities()[0].value = 0.5
				node.call("advance", 1.0 / 60.0)
			for frame in 4:
				await process_frame
				RenderingServer.force_draw(false)
			var image := viewport.get_texture().get_image()
			ok = ok and image.get_used_rect().size.x > 10 and image.get_used_rect().size.y > 10
			var label := ("transformed-" if transformed else "normal-") + ("preferred" if preferred else "legacy")
			var saved := image.save_png(capture_dir.path_join(label + ".png"))
			ok = ok and saved == OK
			if preferred:
				ok = ok and reference.get_data() == image.get_data()
			else:
				reference = image
			viewport.free()
	print("CUBISM_MODEL2D_RENDER_PASS" if ok else "CUBISM_MODEL2D_RENDER_FAIL")
	quit(0 if ok else 1)
