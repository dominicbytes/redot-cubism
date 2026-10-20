# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
const CHANNELS := ["head_angle_x", "head_angle_y", "head_angle_z", "body_angle_x", "eyes_ball_x", "eyes_ball_y"]

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func values(model: GDCubismUserModel) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for parameter: GDCubismParameter in model.get_parameters(): result.append(parameter.value)
	return result

func check_tracking(model: GDCubismUserModel, effect: GDCubismEffectTargetPoint, label: String) -> void:
	effect.set_target(Vector2(1.0, 1.0))
	for step in 90: model.advance(1.0 / 60.0)
	var target := effect.get_target()
	expect(target.distance_to(Vector2.ONE) < 0.02, label + " target converges within SDK tolerance")
	expect(is_equal_approx(model.get("ParamBodyAngleX"), target.x * effect.body_range), label + " body tracking")
	expect(is_equal_approx(model.get("ParamEyeBallX"), target.x * effect.eyes_range), label + " horizontal eye tracking")
	expect(is_equal_approx(model.get("ParamEyeBallY"), target.y * effect.eyes_range), label + " vertical eye tracking")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://factory-model.res") as CubismModelResource
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	var effect := GDCubismEffectTargetPoint.new()
	model.add_child(effect)
	root.add_child(model)
	model.model = resource
	expect(model.is_initialized(), "fixture loads")
	if model.is_initialized():
		model.advance(0.016)
		check_tracking(model, effect, "initial")
		var other := GDCubismEffectCustom.new()
		model.add_child(other)
		model.advance(0.016)
		check_tracking(model, effect, "effect added")
		other.free()
		model.advance(0.016)
		check_tracking(model, effect, "effect removed")
		model.model = resource
		model.advance(0.016)
		check_tracking(model, effect, "model reloaded")
		root.remove_child(model)
		root.add_child(model)
		model.advance(0.016)
		check_tracking(model, effect, "tree reentered")
		for channel: String in CHANNELS: effect.set(channel, "")
		model.model = resource
		model.advance(0.016)
		var baseline := values(model)
		effect.set_target(Vector2(1.0, 1.0))
		for step in 90: model.advance(1.0 / 60.0)
		expect(values(model) == baseline, "absent channels preserve every native parameter")
		effect.head_angle_x = "MissingLegacyTarget"
		model.advance(0.016)
		expect(values(model) == baseline, "undefined nonempty ID does not write an invalid index")
		effect.body_angle_x = "ParamBodyAngleX"
		model.advance(0.016)
		expect(is_equal_approx(model.get("ParamBodyAngleX"), effect.get_target().x * effect.body_range), "valid channel works alongside absent channels")
	model.free()
	for failure in failures: printerr("CUBISM_LEGACY_TARGET_POINT_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_LEGACY_TARGET_POINT_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
