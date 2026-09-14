# SPDX-License-Identifier: MIT
extends SceneTree

class OverrideProcess extends CubismModel2D:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://imported-model.res") as CubismModelResource
	var first := CubismModel2D.new()
	expect(first is Node2D and first.get_model_state() == CubismModel2D.UNLOADED, "new preferred node state")
	expect(first.set_parameter_value(&"ParamAngleX", 1.0) == ERR_UNCONFIGURED, "unloaded write rejected")
	first.playback_process_mode = CubismModel2D.MANUAL
	first.enable_physics = false
	first.enable_pose = false
	var events: Array[String] = []
	first.model_load_started.connect(func(value: CubismModelResource):
		expect(value == resource, "started resource identity")
		events.append("started"))
	first.model_ready.connect(func(value: CubismModelResource):
		expect(value == resource, "ready resource identity")
		events.append("ready"))
	expect(first.load_model(resource) == OK and first.is_ready(), "synchronous resource load outside tree")
	root.add_child(first)
	await process_frame
	expect(events == ["started", "ready"], "deferred ordered lifecycle signals")
	if not first.is_ready():
		first.free()
		finish()
		return
	expect(first.get_child_count() == 0, "runtime child hidden from normal scene APIs")
	expect(first.process_mode == Node.PROCESS_MODE_INHERIT, "scene-tree process mode preserved")
	expect(first.has_parameter(&"ParamAngleX") and not first.has_parameter(&"missing"), "real parameter IDs only")
	expect(first.get_parameter_ids().has("ParamAngleX") and not first.get_part_ids().is_empty(), "parameter and part catalogs")
	var original := first.get_parameter_value(&"ParamAngleX")
	expect(first.set_parameter_value(&"ParamAngleX", 10.0) == OK, "queue set")
	expect(first.add_parameter_value(&"ParamAngleX", 4.0, 0.5) == OK, "queue weighted add")
	expect(first.multiply_parameter_value(&"ParamAngleX", 2.0, 0.5) == OK, "queue weighted multiply")
	expect(first.get_parameter_value(&"ParamAngleX") == original, "getter reports evaluated value before advance")
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 18.0), "ordered writes evaluated once")
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), original), "write queue clears after step")
	first.set_parameter_value(&"ParamAngleX", 10.0, 0.5)
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), (original + 10.0) * 0.5), "weighted set")
	for value: float in [NAN, INF, -INF]:
		expect(first.set_parameter_value(&"ParamAngleX", value) == ERR_INVALID_PARAMETER, "nonfinite write rejected")
		expect(first.add_parameter_value(&"ParamAngleX", 1.0, value) == ERR_INVALID_PARAMETER, "nonfinite weight rejected")
	expect(first.set_parameter_value(&"missing", 1.0) == ERR_DOES_NOT_EXIST, "unknown parameter rejected")
	expect(first.set_parameter_value(&"ParamAngleX", 1.0, -0.1) == ERR_INVALID_PARAMETER, "negative weight rejected")
	expect(first.set_parameter_value(&"ParamAngleX", 1.0, 1.1) == ERR_INVALID_PARAMETER, "excess weight rejected")
	first.set_parameter_value(&"ParamAngleX", 1.0e300)
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 30.0), "extreme finite write clamps to Haru parameter range")
	first.enable_physics = true
	first.enable_pose = true
	first.set_parameter_value(&"ParamAngleX", 7.0)
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 7.0), "post-effect write follows physics and pose")
	first.paused = true
	first.set_parameter_value(&"ParamAngleX", 11.0)
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 7.0), "paused does not advance or consume writes")
	first.paused = false
	first.advance(NAN)
	first.advance(INF)
	first.advance(0.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 7.0), "invalid and zero delta preserve writes")
	first.speed_scale = 0.0
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 7.0), "zero speed pauses model")
	first.speed_scale = 1.0
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 11.0), "resume consumes pending write")
	paused = true
	first.set_parameter_value(&"ParamAngleX", 3.0)
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 11.0), "manual advance respects scene-tree pause")
	paused = false
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 3.0), "scene-tree resume")
	expect(first.set_part_opacity(StringName(first.get_part_ids()[0]), 0.5) == OK, "queue valid part opacity")
	expect(first.set_part_opacity(&"missing", 0.5) == ERR_DOES_NOT_EXIST, "unknown part rejected")
	expect(first.set_part_opacity(StringName(first.get_part_ids()[0]), NAN) == ERR_INVALID_PARAMETER, "nonfinite part opacity rejected")
	var runtime := first.get_child(0, true) as GDCubismUserModel
	var part: GDCubismPartOpacity = runtime.get_part_opacities()[0]
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(part.value, 0.5), "part accessor reports final opacity in the same update")
	var legacy_effect := GDCubismEffectCustom.new()
	var wrote_part := [false]
	runtime.add_child(legacy_effect)
	legacy_effect.cubism_epilogue.connect(func(_model: GDCubismUserModel, _delta: float):
		if not wrote_part[0]:
			part.value = 0.75
			wrote_part[0] = true)
	first.advance(1.0 / 60.0)
	expect(wrote_part[0] and is_equal_approx(part.value, 0.75), "epilogue part write survives final opacity refresh")
	first.enable_pose = false
	first.advance(1.0 / 60.0)
	expect(is_equal_approx(part.value, 0.75), "epilogue part write is consumed on the next update")
	legacy_effect.free()
	first.set_parameter_value(&"ParamAngleX", 23.0)
	first.unload_model()
	first.unload_model()
	expect(not first.is_ready() and first.model == resource and first.get_model_state() == CubismModel2D.DISPOSED, "idempotent unload retains selection")
	expect(first.reload_model() == OK, "explicit reload")
	first.advance(1.0 / 60.0)
	expect(not is_equal_approx(first.get_parameter_value(&"ParamAngleX"), 23.0), "unload discards queued writes")
	root.remove_child(first)
	expect(not first.is_ready(), "tree exit disposes runtime")
	root.add_child(first)
	expect(first.is_ready(), "tree reentry recreates runtime")
	var second := OverrideProcess.new()
	second.model = resource
	root.add_child(second)
	second.set_process(false)
	second.set_physics_process(false)
	second.set_parameter_value(&"ParamAngleX", 8.0)
	await process_frame
	expect(is_equal_approx(second.get_parameter_value(&"ParamAngleX"), 8.0), "native idle processing survives script override")
	second.playback_process_mode = CubismModel2D.PHYSICS
	await physics_frame
	second.set_parameter_value(&"ParamAngleX", 9.0)
	await physics_frame
	expect(is_equal_approx(second.get_parameter_value(&"ParamAngleX"), 9.0), "native physics processing survives script override")
	second.free()
	var failed: Array[int] = []
	var bad := CubismModel2D.new()
	root.add_child(bad)
	bad.model_failed.connect(func(code: int, message: String):
		failed.append(code)
		expect(not message.is_empty(), "failure diagnostic"))
	var invalid := resource.duplicate(true) as CubismModelResource
	invalid.moc_path = "res://../outside.moc3"
	expect(bad.load_model(invalid) != OK and bad.get_model_state() == CubismModel2D.ERROR, "invalid imported source fails")
	await process_frame
	expect(failed.size() == 1 and not bad.get_last_error().is_empty(), "typed failure signal")
	expect(bad.load_model(resource) == OK and bad.get_last_error().is_empty(), "recover from failed load")
	bad.free()
	var doomed := CubismModel2D.new()
	root.add_child(doomed)
	doomed.model_ready.connect(func(_value: CubismModelResource):
		root.remove_child(doomed)
		doomed.queue_free())
	doomed.model = resource
	await process_frame
	await process_frame
	expect(not is_instance_valid(doomed), "remove and queue-free during ready signal")
	var cancelled := CubismModel2D.new()
	var ready_after_cancel := [false]
	root.add_child(cancelled)
	cancelled.model_load_started.connect(func(_value: CubismModelResource): cancelled.unload_model())
	cancelled.model_ready.connect(func(_value: CubismModelResource): ready_after_cancel[0] = true)
	cancelled.model = resource
	await process_frame
	expect(not cancelled.is_ready() and not ready_after_cancel[0], "unload from started callback suppresses stale ready")
	cancelled.free()
	if "--prepare-scene" in OS.get_cmdline_user_args():
		var packed := PackedScene.new()
		expect(packed.pack(first) == OK and packed.get_state().get_node_count() == 1, "serialize public node without runtime children")
		expect(ResourceSaver.save(packed, "res://model2d.tscn") == OK, "save preferred scene")
	var restored := (load("res://model2d.tscn") as PackedScene).instantiate() as CubismModel2D
	root.add_child(restored)
	expect(restored.is_ready() and restored.model == resource, "saved scene loads shared imported resource")
	restored.set_parameter_value(&"ParamAngleX", -15.0)
	restored.advance(1.0 / 60.0)
	expect(not is_equal_approx(first.get_parameter_value(&"ParamAngleX"), -15.0), "shared-resource models remain independent")
	restored.free()
	first.free()
	finish()

func finish() -> void:
	for failure in failures: printerr("CUBISM_MODEL2D_FAIL: ", failure)
	print("CUBISM_MODEL2D_PASS" if failures.is_empty() else "CUBISM_MODEL2D_FAILED", " checks=", checks)
	quit(0 if failures.is_empty() else 1)
