# SPDX-License-Identifier: MIT
extends SceneTree

const FLAG := "CUBISM_TEST_UNCAPPED_MANUAL_STEP"
var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func make_model(preferred: bool, resource: CubismModelResource, steps: Array[float]) -> Node:
	var model: Node
	if preferred:
		model = CubismModel2D.new()
		model.set("enable_physics", false)
		model.set("enable_pose", false)
		var effect := CubismEffect.new()
		effect.effect_process.connect(func(_owner: Node, delta: float): steps.append(delta))
		model.add_child(effect)
	else:
		model = GDCubismUserModel.new()
		model.set("physics_evaluate", false)
		model.set("pose_update", false)
		var effect := GDCubismEffectCustom.new()
		effect.cubism_process.connect(func(_owner: Node, delta: float): steps.append(delta))
		model.add_child(effect)
	model.set("playback_process_mode", 2) # Both APIs use MANUAL=2.
	root.add_child(model)
	if preferred:
		expect(model.call("load_model", resource) == OK, "preferred fixture loads")
	else:
		model.set("model", resource)
		expect(model.call("is_initialized"), "legacy fixture loads")
	return model

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var had_flag := OS.has_environment(FLAG)
	var old_flag := OS.get_environment(FLAG)
	var old_fps := Engine.max_fps
	var old_scale := Engine.time_scale
	Engine.max_fps = 30
	Engine.time_scale = 20.0
	var resource := load("res://factory-model.res") as CubismModelResource
	for setting in [["", false], ["true", false], ["1", true]]:
		OS.set_environment(FLAG, setting[0])
		var uncapped: bool = setting[1]
		for preferred in [false, true]:
			var steps: Array[float] = []
			var model := make_model(preferred, resource, steps)
			var label := str(setting[0]) + (" preferred" if preferred else " legacy")
			model.set("speed_scale", 2.0)
			model.call("advance", 0.25)
			expect(steps.size() == 1 and is_equal_approx(steps[0], 0.5 if uncapped else 0.1), label + " manual scaled step")
			steps.clear()
			for delta: float in [NAN, INF, -INF, 0.0]: model.call("advance", delta)
			model.call("advance", 1e300) # Finite double, unrepresentable by the SDK float.
			expect(steps.is_empty() if uncapped else steps == [0.1], label + " invalid or oversized step")
			steps.clear()
			model.call("advance", 0.01)
			expect(steps.size() == 1 and is_equal_approx(steps[0], 0.02), label + " ordinary step")
			steps.clear()
			paused = true
			model.call("advance", 0.25)
			paused = false
			expect(steps.is_empty(), label + " tree pause")
			if preferred:
				model.set("paused", true)
				model.call("advance", 0.25)
				model.set("paused", false)
				expect(steps.is_empty(), label + " model pause")
			var modes := [CubismModel2D.IDLE, CubismModel2D.PHYSICS] if preferred else [GDCubismUserModel.IDLE, GDCubismUserModel.PHYSICS]
			for mode in modes:
				model.set("playback_process_mode", mode)
				steps.clear()
				model.call("advance", 0.25)
				expect(steps.is_empty(), label + " manual call ignored in automatic mode")
				for frame in 4: await process_frame
				var within_cap := steps.all(func(value: float): return value > 0 and value <= 0.10000001)
				var exercised_cap := steps.any(func(value: float): return is_equal_approx(value, 0.1))
				expect(within_cap and exercised_cap, label + " automatic mode %d retains cap: %s" % [mode, steps])
			model.free()
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	if had_flag: OS.set_environment(FLAG, old_flag)
	else: OS.unset_environment(FLAG)
	for failure in failures: printerr("CUBISM_MANUAL_STEP_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_MANUAL_STEP_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
