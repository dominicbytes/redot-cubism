# SPDX-License-Identifier: MIT
extends SceneTree

const IDS := [&"ParamAngleX", &"ParamAngleY", &"ParamAngleZ", &"ParamBodyAngleX", &"ParamEyeBallX", &"ParamEyeBallY"]
var failures: Array[String] = []
var checks := 0
var warnings: Array[int] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func pose(node: CubismModel2D) -> Array[float]:
	var values: Array[float] = []
	for id: StringName in IDS: values.append(node.get_parameter_value(id))
	return values

func compare(node: CubismModel2D, legacy: GDCubismUserModel, label: String) -> void:
	for parameter: GDCubismParameter in legacy.get_parameters():
		if StringName(parameter.get_id()) in IDS:
			expect(absf(node.get_parameter_value(StringName(parameter.get_id())) - parameter.value) < 0.0002, label + ": " + parameter.get_id())

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source := load("res://imported-model.res") as CubismModelResource
	for with_layout: bool in [false, true]:
		var resource := source.duplicate(true) as CubismModelResource
		resource.layout = {"width": 4.0, "x": 0.5, "y": -0.25} if with_layout else {}
		var node := CubismModel2D.new()
		node.playback_process_mode = CubismModel2D.MANUAL
		node.enable_physics = false
		node.enable_pose = false
		root.add_child(node)
		expect(node.load_model(resource) == OK, "look fixture loads")
		node.runtime_warning.connect(func(code: int, _message: String): warnings.append(code))
		var legacy := GDCubismUserModel.new()
		legacy.playback_process_mode = GDCubismUserModel.MANUAL
		legacy.physics_evaluate = false
		legacy.pose_update = false
		legacy.model = resource
		root.add_child(legacy)
		var target := GDCubismEffectTargetPoint.new()
		legacy.add_child(target)
		var canvas: Vector2 = node.get_canvas_info().size_in_pixels
		var layout_scale := 2.0 * canvas.y / canvas.x if with_layout else 1.0
		var translation := Vector2(0.5, 0.25) * canvas.y * 0.5 if with_layout else Vector2.ZERO
		node.position = Vector2(321, -157)
		node.rotation = 0.7
		node.scale = Vector2(-0.6, 1.7)
		node.set_look_target(translation)
		node.advance(0.05)
		legacy.advance(0.05)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "neutral target and first SDK tick")
		for direction: Vector2 in [Vector2(1.0, 0.5), Vector2(-0.4, -0.3), Vector2(4, -3)]:
			var local := Vector2(direction.x * canvas.x, -direction.y * canvas.y) * 0.5 * layout_scale + translation
			node.set_look_target(node.to_local(node.to_global(local)))
			target.set_target(direction)
			for frame in 40:
				node.advance(0.05)
				legacy.advance(0.05)
				compare(node, legacy, "SDK trajectory including layout, mirror, clamp")
		var local := Vector2(-0.2 * canvas.x, 0.15 * canvas.y) * layout_scale + translation
		target.head_range = 7.5
		target.body_range = 2.5
		target.eyes_range = 0.25
		node.set_look_target(local, 0.25)
		target.set_target(Vector2(-0.4, -0.3))
		for frame in 40:
			node.advance(0.05)
			legacy.advance(0.05)
			compare(node, legacy, "weighted SDK contribution")
		node.set_look_target(translation, 0.25)
		target.set_target(Vector2.ZERO)
		node.advance(0.05)
		legacy.advance(0.05)
		var saved_pose := pose(node)
		node.paused = true
		for frame in 10: node.advance(0.05)
		expect(pose(node) == saved_pose, "pause holds pose")
		node.paused = false
		node.enable_look_target = false
		for frame in 10: node.advance(0.05)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "disable releases contribution")
		node.enable_look_target = true
		node.advance(0.05)
		legacy.advance(0.05)
		compare(node, legacy, "disabled and paused clock resume")
		var warning_count := warnings.size()
		node.set_look_target(Vector2(NAN, 0))
		node.set_look_target(Vector2(0, INF))
		node.set_look_target(local, NAN)
		node.set_look_target(local, -0.1)
		node.set_look_target(local, 1.1)
		await process_frame
		expect(warnings.size() == warning_count + 5, "invalid inputs signal warnings")
		for code: int in warnings.slice(warning_count): expect(code == ERR_INVALID_PARAMETER, "invalid target error code")
		node.advance(0.05)
		legacy.advance(0.05)
		compare(node, legacy, "invalid inputs preserve target")
		target.head_range = 30.0
		target.body_range = 10.0
		target.eyes_range = 1.0
		node.speed_scale = 2.0
		node.set_look_target(translation)
		target.set_target(Vector2.ZERO)
		for frame in 10:
			node.advance(0.025)
			legacy.advance(0.05)
			compare(node, legacy, "speed scale controls look clock")
		node.set_parameter_value(&"ParamAngleX", 7.0)
		node.advance(0.025)
		expect(is_equal_approx(node.get_parameter_value(&"ParamAngleX"), 7.0), "manual post effect override wins")
		node.clear_look_target()
		node.advance(0.025)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "clear releases contribution")
		node.set_look_target(local)
		node.advance(0.025)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "clear resets SDK clock and velocity")
		node.advance(0.025)
		expect(not is_zero_approx(node.get_parameter_value(&"ParamAngleX")), "new target moves after first tick")
		var packed := PackedScene.new()
		expect(packed.pack(node) == OK, "pack node with active look target")
		var reopened := packed.instantiate() as CubismModel2D
		root.add_child(reopened)
		reopened.advance(0.025)
		expect(reopened.enable_look_target and pose(reopened) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "scene restores enable flag without transient target")
		reopened.free()
		node.set_look_target(local, 0.0)
		node.advance(0.025)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "zero weight releases contribution")
		node.set_look_target(local)
		node.enable_look_target = false
		expect(node.reload_model() == OK and not node.enable_look_target, "reload retains enable flag")
		node.enable_look_target = true
		node.advance(0.025)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "reload discards transient target")
		node.set_look_target(local)
		for frame in 10: node.advance(0.025)
		root.remove_child(node)
		root.add_child(node)
		node.advance(0.025)
		expect(pose(node) == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "tree reentry discards target")
		node.unload_model()
		node.clear_look_target()
		node.set_look_target(local)
		await process_frame
		expect(warnings.back() == ERR_UNCONFIGURED, "unloaded target warns safely")
		node.free()
		legacy.free()
	await process_frame
	print("CUBISM_LOOK checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("LOOK_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_LOOK_PASS")
	quit(0 if failures.is_empty() else 1)
