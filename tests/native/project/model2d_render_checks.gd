# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://imported-model.res") as CubismModelResource
	var capture_dir: String = OS.get_cmdline_user_args()[0]
	var ok := true
	var poses := ["normal", "transformed"]
	if OS.get_cmdline_user_args().has("--motion"): poses.append_array(["motion", "expression", "expression-clear", "blink-closed", "breath", "look", "look-transformed", "lip-sync", "controller-fade"])
	for pose: String in poses:
		var transformed := pose in ["transformed", "look-transformed"]
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
				if pose in ["motion", "expression", "expression-clear", "blink-closed", "breath", "look", "look-transformed", "lip-sync"]: model.enable_pose = false
				model.model = resource
				node = model
			else:
				var model := GDCubismUserModel.new()
				model.mask_viewport_size = 1024 # Match the preferred node's medium default.
				model.playback_process_mode = GDCubismUserModel.MANUAL
				model.physics_evaluate = false
				if pose in ["motion", "expression", "expression-clear", "blink-closed", "breath", "look", "look-transformed", "lip-sync"]: model.pose_update = false
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
			if pose == "blink-closed":
				if preferred:
					(node as CubismModel2D).deterministic_seed = 17
					(node as CubismModel2D).enable_eye_blink = true
					for frame in 200:
						node.call("advance", 0.05)
						if is_zero_approx((node as CubismModel2D).get_parameter_value(&"ParamEyeLOpen")): break
					ok = ok and is_zero_approx((node as CubismModel2D).get_parameter_value(&"ParamEyeLOpen"))
				else:
					for parameter: GDCubismParameter in (node as GDCubismUserModel).get_parameters():
						if parameter.get_id() in ["ParamEyeLOpen", "ParamEyeROpen"]: parameter.value = 0.0
					node.call("advance", 0.05)
			if pose in ["look", "look-transformed"]:
				var target: GDCubismEffectTargetPoint
				if preferred: (node as CubismModel2D).set_look_target(Vector2.ZERO)
				else:
					target = GDCubismEffectTargetPoint.new()
					node.add_child(target)
				node.call("advance", 0.05)
				if preferred:
					var local := Vector2(canvas.size_in_pixels.x * 0.4, -canvas.size_in_pixels.y * 0.25)
					(node as CubismModel2D).set_look_target(local)
				else: target.set_target(Vector2(0.8, 0.5))
				for frame in 20: node.call("advance", 0.05)
			if pose == "lip-sync":
				if preferred:
					var lip := CubismLipSync.new()
					node.add_child(lip)
					lip.profile = CubismLipSyncProfile.new()
					lip.profile.attack = 0.0
					ok = ok and lip.set_target_model(node as CubismModel2D) == OK
					lip.submit_sample(0.5)
				else:
					for parameter: GDCubismParameter in (node as GDCubismUserModel).get_parameters():
						if parameter.get_id() == "ParamMouthOpenY": parameter.value = 0.4
				node.call("advance", 0.05)
			if pose == "breath":
				if preferred: (node as CubismModel2D).enable_breath = true
				else: node.add_child(GDCubismEffectBreath.new())
				for frame in 20: node.call("advance", 0.05)
			if pose == "motion":
				if preferred:
					var handle := (node as CubismModel2D).play_motion(&"Cue/0")
					ok = ok and handle.get_error() == OK
					for frame in 5: node.call("advance", 0.05)
				else:
					for parameter: GDCubismParameter in (node as GDCubismUserModel).get_parameters():
						if parameter.get_id() == "ParamAngleX": parameter.value = 5.0
					node.call("advance", 0.05)
			if pose in ["expression", "expression-clear"]:
				if preferred:
					ok = ok and (node as CubismModel2D).set_expression(&"Add" if pose == "expression" else &"Overwrite", 0.0) == OK
					node.call("advance", 0.05)
					if pose == "expression-clear":
						(node as CubismModel2D).clear_expression(0.2)
						for frame in 3: node.call("advance", 0.05)
				else:
					for parameter: GDCubismParameter in (node as GDCubismUserModel).get_parameters():
						if parameter.get_id() == "ParamAngleX": parameter.value = 10.0 if pose == "expression" else -5.0
					node.call("advance", 0.05)
			if transformed:
				if preferred:
					(node as CubismModel2D).enable_pose = false
					ok = ok and (node as CubismModel2D).set_part_opacity(StringName((node as CubismModel2D).get_part_ids()[0]), 0.5) == OK
				else:
					(node as GDCubismUserModel).pose_update = false
					(node as GDCubismUserModel).get_part_opacities()[0].value = 0.5
				node.call("advance", 1.0 / 60.0)
			if pose == "controller-fade":
				if preferred:
					var controller := CubismCharacterController.new()
					controller.manual_process = true
					node.add_child(controller)
					controller.target_model = node as CubismModel2D
					controller.transition_seconds = 0.2
					ok = ok and controller.hide_character(&"fade") == OK
					controller.advance(0.1)
				else: node.modulate.a = 0.5
			for frame in 4:
				await process_frame
				RenderingServer.force_draw(false)
			var image := viewport.get_texture().get_image()
			ok = ok and image.get_used_rect().size.x > 10 and image.get_used_rect().size.y > 10
			var label := pose + "-" + ("preferred" if preferred else "legacy")
			var saved := image.save_png(capture_dir.path_join(label + ".png"))
			ok = ok and saved == OK
			if preferred:
				ok = ok and reference.get_data() == image.get_data()
			else:
				reference = image
			viewport.free()
	print("CUBISM_MODEL2D_RENDER_PASS" if ok else "CUBISM_MODEL2D_RENDER_FAIL")
	quit(0 if ok else 1)
