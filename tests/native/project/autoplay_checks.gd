# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func make_node(enabled: bool = true) -> CubismModel2D:
	var node := CubismModel2D.new()
	node.autoplay = enabled
	node.default_motion = &"Cue/0"
	node.default_expression = &"Add"
	node.playback_process_mode = CubismModel2D.MANUAL
	node.enable_physics = false
	node.enable_pose = false
	return node

func watch(node: CubismModel2D) -> Array[CubismMotionHandle]:
	var handles: Array[CubismMotionHandle] = []
	node.motion_started.connect(func(handle: CubismMotionHandle, _id: StringName): handles.append(handle))
	return handles

func steps(node: CubismModel2D, count: int) -> void:
	for index in count: node.advance(0.05)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var off := make_node(false)
	var off_handles := watch(off)
	root.add_child(off)
	off.model = resource
	await process_frame
	steps(off, 5)
	expect(off_handles.is_empty() and is_zero_approx(off.get_parameter_value(&"ParamAngleX")), "autoplay is opt in")
	off.free()
	var node := make_node()
	var handles := watch(node)
	var expressions: Array[StringName] = []
	node.expression_changed.connect(func(id: StringName): expressions.append(id))
	node.model = resource
	await process_frame
	expect(handles.is_empty() and expressions.is_empty(), "no autoplay outside scene tree")
	root.add_child(node)
	await process_frame
	expect(handles.size() == 1 and expressions == [&"Add"], "defaults start after entering with loaded model")
	steps(node, 24)
	await process_frame
	expect(handles.size() == 1 and handles[0].get_reason() == CubismMotionHandle.COMPLETED, "one-shot metadata and no frame retries")
	node.reload_model()
	await process_frame
	expect(handles.size() == 2 and expressions.size() == 2, "reload restarts defaults once")
	root.remove_child(node)
	expect(handles[1].get_reason() == CubismMotionHandle.UNLOADED, "tree exit terminates autoplay")
	root.add_child(node)
	await process_frame
	expect(handles.size() == 3 and expressions.size() == 3, "reentry restarts defaults once")
	node.unload_model()
	await process_frame
	expect(handles.size() == 3 and not node.is_ready(), "explicit unload cannot autoplay retained selection")
	node.model = null
	await process_frame
	expect(handles.size() == 3, "null assignment cannot autoplay")
	node.free()
	var explicit := make_node()
	root.add_child(explicit)
	explicit.model = resource
	var explicit_handles := watch(explicit)
	var requested := explicit.play_motion(&"Cue/1")
	explicit.set_expression(&"Overwrite", 0.0)
	await process_frame
	steps(explicit, 1)
	expect(explicit_handles == [requested] and not requested.is_finished(), "explicit motion before deferred ready wins")
	expect(is_equal_approx(explicit.get_parameter_value(&"ParamAngleX"), -10.0), "explicit expression before ready wins")
	explicit.free()
	var stopped := make_node()
	root.add_child(stopped)
	stopped.model = resource
	var stopped_handles := watch(stopped)
	stopped.stop_motion(0.0)
	stopped.clear_expression(0.0)
	await process_frame
	steps(stopped, 1)
	expect(stopped_handles.is_empty() and is_zero_approx(stopped.get_parameter_value(&"ParamAngleX")), "explicit stop and clear suppress defaults")
	stopped.free()
	var ready_override := make_node()
	root.add_child(ready_override)
	var ready_handles := watch(ready_override)
	ready_override.model_ready.connect(func(_resource: CubismModelResource):
		ready_override.play_motion(&"Cue/1")
		ready_override.set_expression(&"Overwrite", 0.0))
	ready_override.model = resource
	await process_frame
	steps(ready_override, 1)
	expect(ready_handles.size() == 2 and ready_handles[0].get_reason() == CubismMotionHandle.INTERRUPTED, "ready handler overrides idle-priority default")
	expect(ready_handles[1].get_motion_id() == &"Cue/1" and is_equal_approx(ready_override.get_parameter_value(&"ParamAngleX"), -10.0), "ready handler expression wins")
	ready_override.free()
	var bad := make_node()
	bad.default_motion = &"missing-motion"
	bad.default_expression = &"missing-expression"
	var warnings: Array[int] = []
	bad.runtime_warning.connect(func(code: int, _message: String): warnings.append(code))
	root.add_child(bad)
	bad.model = resource
	await process_frame
	steps(bad, 10)
	await process_frame
	expect(warnings == [ERR_DOES_NOT_EXIST, ERR_DOES_NOT_EXIST] and bad.is_ready(), "invalid defaults warn once and preserve model")
	bad.free()
	if OS.get_cmdline_user_args().has("--prepare-scene"):
		var saved := make_node()
		saved.name = "AutoplayCharacter"
		saved.default_motion = &"Cue/1"
		saved.model = resource
		var packed := PackedScene.new()
		expect(packed.pack(saved) == OK, "pack public autoplay node")
		expect(ResourceSaver.save(packed, "res://autoplay.tscn") == OK, "save autoplay settings")
		saved.free()
	var scene := load("res://autoplay.tscn") as PackedScene
	expect(scene != null, "load persisted autoplay scene")
	if scene != null:
		var reopened := scene.instantiate() as CubismModel2D
		expect(reopened.autoplay and reopened.default_motion == &"Cue/1" and reopened.default_expression == &"Add", "persisted startup settings")
		var reopened_handles := watch(reopened)
		root.add_child(reopened)
		await process_frame
		steps(reopened, 45)
		await process_frame
		expect(reopened_handles.size() == 1 and not reopened_handles[0].is_finished() and reopened_handles[0].get_loop_count() == 2, "persisted autoplay honors imported loop metadata")
		reopened.free()
	await process_frame
	print("CUBISM_AUTOPLAY checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("AUTOPLAY_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_AUTOPLAY_PASS")
	quit(0 if failures.is_empty() else 1)
