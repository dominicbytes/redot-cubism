# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func model() -> CubismModel2D:
	var value := CubismModel2D.new()
	value.playback_process_mode = CubismModel2D.MANUAL
	value.enable_physics = false
	value.enable_pose = false
	root.add_child(value)
	expect(value.load_model(resource) == OK, "utility fixture loads")
	return value

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var target := model()
	var controller := CubismCharacterController.new()
	controller.manual_process = true
	root.add_child(controller)
	controller.target_model = target
	expect(controller.return_to_idle() == ERR_UNCONFIGURED, "missing idle is explicit")
	controller.idle_motion = &"Cue/1"
	expect(controller.return_to_idle() == OK and controller.is_idle(), "explicit idle starts")
	controller.advance(0.25)
	var idle := controller.get_motion_handle()
	expect(absf(idle.get_elapsed_seconds() - 0.25) < 0.000001 and absf(target.get_parameter_value(&"ParamAngleX") + 5.0) < 0.001, "controller clock evaluates native idle")
	target.advance(0.1)
	expect(is_equal_approx(idle.get_elapsed_seconds(), 0.25), "idle has exclusive clock")
	expect(controller.return_to_idle() == OK and controller.get_motion_handle() == idle, "returning to same idle does not restart")
	controller.auto_return_to_idle = true
	var cue := controller.perform(&"Cue/0")
	expect(idle.is_finished() and not controller.is_idle(), "cue replaces idle")
	controller.advance(1.1)
	expect(cue.is_finished() and controller.is_idle(), "normal cue completion resumes idle")
	controller.advance(1.2)
	expect(controller.get_motion_handle().get_loop_count() == 1, "resumed idle loops")
	controller.stop_speaking(0)
	expect(not controller.is_idle(), "explicit stop does not restart idle")
	cue = controller.perform(&"Cue/0")
	controller.idle_motion = &"Missing"
	expect(controller.return_to_idle() == ERR_DOES_NOT_EXIST and not cue.is_finished(), "bad idle leaves valid cue intact")
	controller.idle_motion = &"Cue/1"
	expect(controller.return_to_idle() == OK and cue.get_reason() == CubismSpeechHandle.STOPPED, "explicit idle stops a cue")
	controller.paused = true
	target.hide()
	expect(not controller.is_idle(), "hidden idle cancels even while paused")
	controller.paused = false
	controller.auto_return_to_idle = false
	expect(controller.show_character() == OK and target.visible, "immediate show")
	target.modulate = Color(0.6, 0.7, 0.8, 0.8)
	cue = controller.perform(&"Cue/0")
	expect(controller.hide_character(&"invalid") == ERR_INVALID_PARAMETER and not cue.is_finished(), "unknown transition preserves cue")
	controller.transition_seconds = 0.2
	expect(controller.hide_character(&"fade") == OK and cue.get_reason() == CubismSpeechHandle.HIDDEN, "fade hide cancels cue immediately")
	controller.advance(0.1)
	expect(target.visible and is_equal_approx(target.modulate.a, 0.4) and is_equal_approx(target.modulate.r, 0.6), "hide fade preserves tint and interpolates alpha")
	controller.advance(0.1)
	expect(not target.visible and is_equal_approx(target.modulate.a, 0.8), "hide completes with reusable original alpha")
	expect(controller.show_character(&"fade") == OK and target.visible and is_zero_approx(target.modulate.a), "show fade starts transparent")
	controller.advance(0.1)
	controller.paused = true
	controller.advance(0.2)
	expect(is_equal_approx(target.modulate.a, 0.4), "pause freezes visibility fade")
	controller.paused = false
	controller.advance(0.1)
	expect(is_equal_approx(target.modulate.a, 0.8), "show restores original opacity")
	controller.hide_character(&"fade")
	controller.advance(0.05)
	controller.show_character(&"fade")
	controller.advance(0.1)
	expect(is_equal_approx(target.modulate.a, 0.7), "reversing fade keeps original opacity")
	controller.advance(0.1)
	expect(controller.set_transition_seconds(NAN) == ERR_INVALID_PARAMETER and is_equal_approx(controller.transition_seconds, 0.2), "invalid duration rejected")
	var other := model()
	controller.hide_character(&"fade")
	controller.advance(0.1)
	controller.target_model = other
	controller.advance(0.1)
	expect(is_equal_approx(target.modulate.a, 0.8) and other.modulate == Color.WHITE, "retarget cancels old fade without touching new opacity")
	controller.hide_character(&"fade")
	other.free()
	expect(controller.set_transition_seconds(0.2) == OK, "freed transition target cannot keep configuration busy")
	controller.target_model = target
	target.reload_model()
	var reference := model()
	var previous_canvas := root.canvas_transform
	root.canvas_transform = Transform2D(0.0, Vector2(150, -40))
	target.position = Vector2(80, 40)
	target.rotation = 0.4
	target.scale = Vector2(1.3, 0.7)
	var local := Vector2(300, -250)
	var screen := target.get_global_transform_with_canvas() * local
	expect(controller.look_at_screen_position(screen) == OK, "viewport look accepts transformed target")
	expect(controller.look_at_screen_position(Vector2(NAN, 0)) == ERR_INVALID_PARAMETER, "invalid viewport point preserves target")
	reference.set_look_target(local)
	for frame in 20:
		target.advance(0.05)
		reference.advance(0.05)
	expect(absf(target.get_parameter_value(&"ParamAngleX") - reference.get_parameter_value(&"ParamAngleX")) < 0.001, "viewport/canvas inverse matches local look")
	target.transform = Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	expect(controller.look_at_screen_position(screen) == ERR_INVALID_PARAMETER, "singular canvas transform rejected")
	root.canvas_transform = previous_canvas
	reference.free()
	controller.hide_character(&"fade")
	controller.advance(0.05)
	controller.free()
	expect(is_equal_approx(target.modulate.a, 0.8), "controller disposal restores interrupted fade opacity")
	target.free()
	await process_frame
	print("CUBISM_CONTROLLER_UTILITIES checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("CONTROLLER_UTILITY_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_CONTROLLER_UTILITIES_PASS")
	quit(0 if failures.is_empty() else 1)
