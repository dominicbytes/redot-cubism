# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func near(value: float, expected: float, label: String) -> void:
	expect(absf(value - expected) < 0.002, label + " (actual=" + str(value) + ", expected=" + str(expected) + ")")

func model() -> CubismModel2D:
	var node := CubismModel2D.new()
	node.playback_process_mode = CubismModel2D.MANUAL
	node.enable_physics = false
	node.enable_pose = false
	root.add_child(node)
	expect(node.load_model(resource) == OK and node.is_ready(), "fixture loads")
	return node

func steps(node: CubismModel2D, count: int) -> void:
	for index in count: node.advance(0.05)

func angle(node: CubismModel2D) -> float:
	return node.get_parameter_value(&"ParamAngleX")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var node := model()
	expect(node.get_expression_ids() == PackedStringArray(["Add", "Multiply", "Overwrite"]), "expression catalog")
	expect(node.set_expression(&"missing") == ERR_DOES_NOT_EXIST, "unknown ID rejected")
	for fade: float in [-2.0, NAN, INF, 1.0e300]:
		expect(node.set_expression(&"Add", fade) == ERR_INVALID_PARAMETER, "invalid fade rejected")
	var changes: Array[StringName] = []
	node.expression_changed.connect(func(id: StringName): changes.append(id))
	expect(node.set_expression(&"Add", 0.0) == OK, "add expression accepted")
	expect(changes.is_empty(), "change signal deferred")
	steps(node, 1)
	near(angle(node), 10.0, "native additive expression")
	steps(node, 5)
	near(angle(node), 10.0, "expression does not accumulate each step")
	await process_frame
	expect(changes == [&"Add"], "typed changed signal once")
	node.play_motion(&"Cue/0")
	steps(node, 5)
	near(angle(node), 15.0, "expression follows primary motion")
	node.set_expression(&"Multiply", 0.0)
	steps(node, 1)
	near(angle(node), 12.0, "native multiply over motion")
	node.set_expression(&"Overwrite", 0.0)
	steps(node, 1)
	near(angle(node), -10.0, "native overwrite over motion")
	node.set_parameter_value(&"ParamAngleX", 7.0)
	steps(node, 1)
	near(angle(node), 7.0, "post effect parameter write wins once")
	steps(node, 1)
	near(angle(node), -10.0, "expression resumes after one-shot override")
	node.stop_motion(0.0)
	node.clear_expression(0.0)
	steps(node, 1)
	near(angle(node), 9.0, "immediate clear reveals saved primary pose")
	node.free()
	var fade_node := model()
	fade_node.set_expression(&"Add", 0.0)
	steps(fade_node, 1)
	fade_node.set_expression(&"Overwrite", 0.2)
	steps(fade_node, 1)
	near(angle(fade_node), 10.0, "SDK incoming fade starts on first evaluation")
	steps(fade_node, 2)
	near(angle(fade_node), 0.0, "native expression crossfade midpoint")
	steps(fade_node, 3)
	near(angle(fade_node), -10.0, "native expression crossfade endpoint")
	fade_node.clear_expression(0.2)
	steps(fade_node, 1)
	near(angle(fade_node), -10.0, "neutral fade preserves starting expression")
	steps(fade_node, 2)
	near(angle(fade_node), -5.0, "neutral fade midpoint")
	steps(fade_node, 3)
	near(angle(fade_node), 0.0, "neutral fade restores underlying pose")
	steps(fade_node, 4)
	near(angle(fade_node), 0.0, "cleared state remains neutral")
	# Clearing and replaying must not reuse R5's private fade-weight bookkeeping.
	for iteration in 4:
		fade_node.set_expression(&"Add", 0.0)
		fade_node.set_expression(&"Overwrite", 0.0)
		fade_node.clear_expression(0.0)
		fade_node.set_expression(&"Add")
		steps(fade_node, 5)
		near(angle(fade_node), 5.0, "default fade remains correct after manager reset")
		fade_node.clear_expression(0.0)
		steps(fade_node, 1)
	fade_node.set_expression(&"Add", 0.0)
	steps(fade_node, 1)
	fade_node.clear_expression(0.4)
	steps(fade_node, 1)
	fade_node.paused = true
	steps(fade_node, 5)
	near(angle(fade_node), 10.0, "pause freezes expression fade")
	fade_node.paused = false
	fade_node.speed_scale = 2.0
	steps(fade_node, 2)
	near(angle(fade_node), 5.0, "model speed scales expression fade")
	fade_node.free()
	var resumed := model()
	resumed.set_expression(&"Add", 0.0)
	steps(resumed, 1)
	resumed.clear_expression(0.2)
	steps(resumed, 3)
	near(angle(resumed), 5.0, "add clear midpoint")
	resumed.set_expression(&"Add", 0.2)
	steps(resumed, 1)
	near(angle(resumed), 5.0, "replay during clear preserves partial influence")
	steps(resumed, 2)
	near(angle(resumed), 7.5, "interrupted clear recovers over incoming fade")
	steps(resumed, 3)
	near(angle(resumed), 10.0, "interrupted clear recovers full expression")
	resumed.clear_expression()
	steps(resumed, 3)
	near(angle(resumed), 5.0, "default clear uses last expression fade out")
	resumed.free()
	var moving := model()
	moving.play_motion(&"Cue/0")
	steps(moving, 5)
	moving.set_expression(&"Overwrite", 0.0)
	steps(moving, 1)
	moving.clear_expression(0.2)
	steps(moving, 3)
	near(angle(moving), -0.5, "clear blends against advancing primary pose")
	steps(moving, 3)
	near(angle(moving), 12.0, "clear restores current rather than old primary pose")
	moving.free()
	var snapshot := model()
	var descriptor := resource.expressions[0] as CubismExpressionDescriptor
	var original_id := descriptor.id
	descriptor.id = &"edited"
	expect(snapshot.set_expression(original_id, 0.0) == OK, "loaded expression identity snapshot")
	steps(snapshot, 1)
	near(angle(snapshot), 10.0, "loaded expression bytes retained")
	expect(snapshot.set_expression(&"missing", 0.0) == ERR_DOES_NOT_EXIST, "rejection during playback")
	steps(snapshot, 1)
	near(angle(snapshot), 10.0, "rejected request preserves expression")
	descriptor.id = original_id
	snapshot.free()
	var legacy := GDCubismUserModel.new()
	legacy.playback_process_mode = GDCubismUserModel.MANUAL
	legacy.physics_evaluate = false
	legacy.pose_update = false
	legacy.model = resource
	root.add_child(legacy)
	var compare := model()
	legacy.start_expression("Add")
	compare.set_expression(&"Add")
	for frame in 10:
		legacy.advance(0.05)
		compare.advance(0.05)
		var legacy_angle := 0.0
		for parameter: GDCubismParameter in legacy.get_parameters():
			if parameter.get_id() == "ParamAngleX": legacy_angle = parameter.value
		near(angle(compare), legacy_angle, "SDK legacy expression trajectory")
	legacy.free()
	compare.free()
	var lifecycle := model()
	var stale: Array[StringName] = []
	lifecycle.expression_changed.connect(func(id: StringName): stale.append(id))
	lifecycle.set_expression(&"Add", 0.0)
	lifecycle.reload_model()
	steps(lifecycle, 1)
	await process_frame
	near(angle(lifecycle), 0.0, "reload clears expression state")
	expect(stale.is_empty(), "reload suppresses stale expression notification")
	lifecycle.set_expression(&"Add", 0.0)
	lifecycle.expression_changed.connect(func(_id: StringName): lifecycle.unload_model(), CONNECT_ONE_SHOT)
	await process_frame
	expect(not lifecycle.is_ready(), "expression callback safely unloads")
	expect(lifecycle.set_expression(&"Add") == ERR_UNCONFIGURED and lifecycle.get_expression_ids().is_empty(), "unloaded expression API")
	lifecycle.free()
	await process_frame
	print("CUBISM_EXPRESSION_API checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("EXPRESSION_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_EXPRESSION_API_PASS")
	quit(0 if failures.is_empty() else 1)
