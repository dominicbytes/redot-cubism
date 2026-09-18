# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func model(seed_value: int, blink: bool = true, breath: bool = false) -> CubismModel2D:
	var node := CubismModel2D.new()
	node.playback_process_mode = CubismModel2D.MANUAL
	node.deterministic_seed = seed_value
	node.enable_eye_blink = blink
	node.enable_breath = breath
	node.enable_physics = false
	node.enable_pose = false
	root.add_child(node)
	expect(node.load_model(resource) == OK, "fixture loads")
	return node

func eye(node: CubismModel2D) -> float:
	return node.get_parameter_value(&"ParamEyeLOpen")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var second := model(17, true, true)
	var noise := model(99, true, true)
	var first := model(17, true, true)
	var baseline: Array[float] = []
	var other: Array[float] = []
	for frame in 400:
		if frame % 2 == 0:
			first.advance(0.05)
			noise.advance(0.05)
			second.advance(0.05)
		else:
			second.advance(0.05)
			noise.advance(0.05)
			first.advance(0.05)
		expect(eye(first) == eye(second), "blink independent of construction/update order")
		expect(first.get_parameter_value(&"ParamAngleX") == second.get_parameter_value(&"ParamAngleX"), "breath independent of update order")
		expect(eye(first) >= 0.0 and eye(first) <= 1.0, "blink finite unit range")
		expect(eye(first) == first.get_parameter_value(&"ParamEyeROpen"), "manifest eyes share blink phase")
		baseline.append(eye(first))
		other.append(eye(noise))
	expect(baseline.has(0.0) and baseline.has(1.0), "complete blink cycles occur")
	expect(baseline != other, "different seeds produce different schedules")
	var closing := baseline.find(0.5)
	expect(closing >= 0 and closing + 5 < baseline.size(), "closing phase sampled")
	if closing >= 0 and closing + 5 < baseline.size():
		var expected := [0.5, 0.0, 0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
		for index in expected.size():
			expect(absf(baseline[closing + index] - expected[index]) < 0.0001, "R5 close/hold/open default timing")
	first.paused = true
	var paused_eye := eye(first)
	var paused_angle := first.get_parameter_value(&"ParamAngleX")
	for frame in 10: first.advance(0.05)
	expect(eye(first) == paused_eye and first.get_parameter_value(&"ParamAngleX") == paused_angle, "pause freezes procedural clocks")
	first.paused = false
	first.advance(0.05)
	second.advance(0.05)
	expect(eye(first) == eye(second) and first.get_parameter_value(&"ParamAngleX") == second.get_parameter_value(&"ParamAngleX"), "resume continues same procedural phase")
	first.reload_model()
	var replay: Array[float] = []
	for frame in 400:
		first.advance(0.05)
		replay.append(eye(first))
	expect(replay == baseline, "reload resets deterministic blink stream")
	first.enable_eye_blink = false
	first.enable_breath = false
	first.advance(0.05)
	expect(is_equal_approx(eye(first), 1.0) and is_zero_approx(first.get_parameter_value(&"ParamAngleX")), "disabled effects release underlying pose")
	first.free()
	second.free()
	noise.free()
	var active := model(17)
	var idle := model(17)
	for frame in 5:
		active.advance(0.05)
		idle.advance(0.05)
	active.play_motion(&"Eyes/0", CubismMotionPriority.NORMAL, true)
	for frame in 100:
		active.advance(0.05)
		expect(is_equal_approx(eye(active), 0.25), "authored eyes retain ownership during motion")
	active.stop_motion(0.2)
	for frame in 2:
		active.advance(0.05)
		expect(is_equal_approx(eye(active), 0.25), "outgoing native fade retains eye ownership")
	active.stop_motion(0.0)
	active.advance(0.05)
	idle.advance(0.05)
	expect(eye(active) == eye(idle), "motion ownership suspends procedural blink clock")
	active.set_parameter_value(&"ParamEyeLOpen", 0.3)
	active.advance(0.05)
	expect(is_equal_approx(eye(active), 0.3), "post effect eye override wins")
	idle.advance(0.05)
	active.enable_eye_blink = false
	for frame in 20: active.advance(0.05)
	active.enable_eye_blink = true
	active.advance(0.05)
	idle.advance(0.05)
	expect(eye(active) == eye(idle), "disabled blink freezes its clock")
	active.free()
	idle.free()
	var reset := model(99)
	for frame in 100: reset.advance(0.05)
	reset.deterministic_seed = 17
	var reset_trace: Array[float] = []
	for frame in 400:
		reset.advance(0.05)
		reset_trace.append(eye(reset))
	expect(reset_trace == baseline, "setting seed resets instance blink only")
	reset.free()
	var preferred := model(17, false, true)
	var legacy := GDCubismUserModel.new()
	legacy.playback_process_mode = GDCubismUserModel.MANUAL
	legacy.physics_evaluate = false
	legacy.pose_update = false
	legacy.model = resource
	root.add_child(legacy)
	legacy.add_child(GDCubismEffectBreath.new())
	for frame in 100:
		preferred.advance(0.05)
		legacy.advance(0.05)
		for parameter: GDCubismParameter in legacy.get_parameters():
			if parameter.get_id() in ["ParamAngleX", "ParamAngleY", "ParamAngleZ", "ParamBodyAngleX", "ParamBreath"]:
				expect(absf(preferred.get_parameter_value(StringName(parameter.get_id())) - parameter.value) < 0.0001, "native breath trajectory matches SDK legacy profile")
	preferred.set_parameter_value(&"ParamAngleX", 7.0)
	preferred.advance(0.05)
	expect(is_equal_approx(preferred.get_parameter_value(&"ParamAngleX"), 7.0), "post effect override follows breath")
	preferred.free()
	legacy.free()
	await process_frame
	print("CUBISM_PROCEDURAL checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("PROCEDURAL_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_PROCEDURAL_PASS")
	quit(0 if failures.is_empty() else 1)
