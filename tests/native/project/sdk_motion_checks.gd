# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func effects_match(resource: CubismModelResource, fixture: Dictionary) -> bool:
	if fixture.physics and (resource.physics_path.is_empty() or FileAccess.get_sha256(resource.physics_path) != fixture.physics_sha256): return false
	if fixture.pose and (resource.pose_path.is_empty() or FileAccess.get_sha256(resource.pose_path) != fixture.pose_sha256): return false
	if not fixture.expression.is_empty():
		var matches := 0
		for expression: CubismExpressionDescriptor in resource.expressions:
			if String(expression.id) == fixture.expression and FileAccess.get_sha256(expression.source_path) == fixture.expression_sha256:
				matches += 1
		if matches != 1: return false
	return true

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var results: Array[Dictionary] = []
	var failed := false
	for fixture: Dictionary in reference.cases:
		var result := {"resource": fixture.resource, "group": fixture.group, "index": fixture.index,
			"steps": fixture.steps, "fps": fixture.fps, "loop": fixture.loop, "expression": fixture.expression,
			"physics": fixture.physics, "pose": fixture.pose, "breath": fixture.breath, "look": fixture.look,
			"status": "FAIL", "parameters": {}, "parts": {}}
		var resource := load(fixture.resource) as CubismModelResource
		if resource == null or resource.source_hash != fixture.manifest_sha256 or FileAccess.get_sha256(resource.moc_path) != fixture.moc_sha256:
			result.error = "Imported resource does not match the reference manifest/MOC"
		else:
			var motions: Array = resource.motion_groups.get(fixture.group, [])
			if int(fixture.index) >= motions.size() or FileAccess.get_sha256(motions[int(fixture.index)].source_path) != fixture.motion_sha256:
				result.error = "Imported motion does not match the reference motion"
			elif not effects_match(resource, fixture):
				result.error = "Imported effect does not match the reference file"
			else:
				var model := CubismModel2D.new()
				model.playback_process_mode = CubismModel2D.MANUAL
				model.enable_physics = fixture.physics
				model.enable_pose = fixture.pose
				model.enable_eye_blink = false
				model.enable_breath = fixture.breath
				root.add_child(model)
				if model.load_model(resource) != OK:
					result.error = model.get_last_error()
				else:
					var handle := model.play_motion_from_group(fixture.group, int(fixture.index), CubismMotionPriority.NORMAL, fixture.loop)
					if handle.get_error() != OK:
						result.error = "Motion playback rejected"
					elif not fixture.expression.is_empty() and model.set_expression(fixture.expression) != OK:
						result.error = "Expression playback rejected"
					else:
						if not fixture.look.is_empty(): model.set_look_target(Vector2(fixture.look[0], fixture.look[1]))
						for step in int(fixture.steps): model.advance(1.0 / float(fixture.fps))
						for id: String in model.get_parameter_ids(): result.parameters[id] = model.get_parameter_value(id)
						# There is no public part-opacity getter; inspect the native model for this oracle.
						var runtime := model.get_child(0, true) as GDCubismUserModel
						for part: GDCubismPartOpacity in runtime.get_part_opacities(): result.parts[part.id] = part.value
						result.status = "PASS"
				model.free()
		if result.status != "PASS": failed = true
		results.append(result)
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	if output == null:
		push_error("Cannot save SDK motion results")
		quit(1)
		return
	output.store_string(JSON.stringify({"status": "FAIL" if failed else "PASS", "cases": results}, "  "))
	output.close()
	print("CUBISM_SDK_MOTION_FAIL" if failed else "CUBISM_SDK_MOTION_PASS")
	quit(1 if failed else 0)
