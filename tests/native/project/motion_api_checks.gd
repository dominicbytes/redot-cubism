# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func near(value: float, expected: float, label: String) -> void:
	expect(absf(value - expected) < 0.001, label + " (actual=" + str(value) + ", expected=" + str(expected) + ")")

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

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var node := model()
	expect(node.get_motion_ids() == PackedStringArray(["Cue/0", "Cue/1", "Eyes/0", "Lips/0", "LongCue/0", "ModelLips/0"]), "stable motion catalog")
	var rejected := node.play_motion(&"missing")
	expect(rejected.is_finished() and rejected.get_reason() == CubismMotionHandle.FAILED and rejected.get_error() == ERR_DOES_NOT_EXIST, "missing motion terminal failure")
	expect(node.play_motion_from_group(&"Cue", -1).get_error() == ERR_DOES_NOT_EXIST, "invalid group index")
	for speed: float in [0.0, -1.0, NAN, INF, 257.0]:
		expect(node.play_motion(&"Cue/0", CubismMotionPriority.NORMAL, false, speed).get_error() == ERR_INVALID_PARAMETER, "invalid speed")
	var order: Array[String] = []
	var node_finishes: Array[int] = []
	var node_terminals: Dictionary = {}
	var node_loops: Dictionary = {}
	node.motion_started.connect(func(handle: CubismMotionHandle, id: StringName):
		expect(handle.get_motion_id() == id, "started identity")
		order.append("started"))
	node.motion_event.connect(func(_handle: CubismMotionHandle, value: String): order.append(value))
	node.motion_looped.connect(func(handle: CubismMotionHandle, count: int):
		if not node_loops.has(handle.get_id()): node_loops[handle.get_id()] = []
		node_loops[handle.get_id()].append(count))
	node.motion_finished.connect(func(handle: CubismMotionHandle, id: StringName, reason: int):
		expect(handle.get_motion_id() == id and handle.get_reason() == reason, "finished identity")
		if not node_terminals.has(handle.get_id()): node_terminals[handle.get_id()] = []
		node_terminals[handle.get_id()].append(reason)
		node_finishes.append(reason)
		order.append("finished"))
	var handle := node.play_motion_from_group(&"Cue", 0)
	var terminal: Array[int] = []
	handle.finished.connect(func(reason: int): terminal.append(reason))
	expect(handle.get_state() == CubismMotionHandle.PLAYING and handle.get_error() == OK, "accepted handle")
	steps(node, 5)
	near(node.get_parameter_value(&"ParamAngleX"), 5.0, "native linear curve at quarter second")
	near(handle.get_elapsed_seconds(), 0.25, "handle clock")
	steps(node, 18)
	await process_frame
	expect(handle.is_finished() and terminal == [CubismMotionHandle.COMPLETED], "one shot completes exactly once")
	expect(order == ["started", "start", "半分_😀", "end", "finished"], "ordered Unicode events and terminal signal")
	expect(node_finishes == [CubismMotionHandle.COMPLETED], "node terminal once")
	expect(node_terminals.get(handle.get_id(), []) == [CubismMotionHandle.COMPLETED], "completed node terminal once")
	near(handle.get_elapsed_seconds(), 1.0, "completed elapsed clamped")
	var slow := model()
	var fast := model()
	var slow_handle := slow.play_motion(&"Cue/0")
	var fast_handle := fast.play_motion(&"Cue/0", CubismMotionPriority.NORMAL, false, 2.0)
	var fast_events: Array[String] = []
	var fast_event_times: Array[float] = []
	fast.motion_event.connect(func(event_handle: CubismMotionHandle, value: String):
		expect(event_handle.get_id() == fast_handle.get_id(), "2x event identity")
		fast_events.append(value)
		fast_event_times.append(event_handle.get_elapsed_seconds()))
	expect(slow_handle.get_id() != fast_handle.get_id(), "globally unique handle IDs")
	steps(slow, 4)
	steps(fast, 1)
	await process_frame
	expect(fast_events == ["start"], "2x start event on first update")
	near(fast_event_times[0], 0.1, "2x start event time")
	steps(fast, 1)
	near(slow.get_parameter_value(&"ParamAngleX"), fast.get_parameter_value(&"ParamAngleX"), "independent per-playback speed")
	fast.paused = true
	steps(fast, 3)
	near(fast_handle.get_elapsed_seconds(), 0.2, "pause freezes motion")
	fast.paused = false
	fast.speed_scale = 0.5
	steps(fast, 2)
	near(fast_handle.get_elapsed_seconds(), 0.3, "global and local speed multiply")
	steps(fast, 3)
	await process_frame
	expect(fast_events == ["start"], "2x half event waits for motion time")
	fast.advance(0.06)
	await process_frame
	expect(fast_events == ["start", "半分_😀"], "2x half event after motion time 0.5")
	if fast_event_times.size() > 1: near(fast_event_times[1], 0.51, "2x half event time")
	steps(fast, 9)
	await process_frame
	expect(fast_events == ["start", "半分_😀"], "2x end event waits for motion time")
	steps(fast, 1)
	await process_frame
	expect(fast_events == ["start", "半分_😀", "end"], "2x event order and completion")
	if fast_event_times.size() > 2: near(fast_event_times[2], 1.0, "2x end event time")
	slow.free()
	fast.free()
	var looping := node.play_motion(&"Cue/0", CubismMotionPriority.NORMAL, true)
	var loops: Array[int] = []
	var loop_events: Array[String] = []
	looping.looped.connect(func(count: int): loops.append(count))
	looping.event.connect(func(value: String): loop_events.append(value))
	steps(node, 44)
	await process_frame
	expect(not looping.is_finished() and looping.get_loop_count() == 2 and loops == [1, 2], "R5 loop period includes source frame")
	expect(node_loops.get(looping.get_id(), []) == [1, 2], "node loop boundaries once each")
	expect(not node_terminals.has(looping.get_id()), "loop boundaries are not terminal")
	expect(loop_events == ["start", "半分_😀", "end", "start", "半分_😀", "end", "start"], "events repeat once each cycle")
	expect(node.play_motion(&"Cue/1").get_error() == ERR_BUSY, "equal priority rejected")
	expect(node.play_motion(&"Cue/1", CubismMotionPriority.IDLE).get_error() == ERR_BUSY, "lower priority rejected")
	expect(not looping.is_finished(), "rejection preserves current playback")
	var replacement := node.play_motion(&"Cue/1", CubismMotionPriority.FORCE, false, 2.0)
	expect(looping.get_reason() == CubismMotionHandle.INTERRUPTED and replacement.get_error() == OK, "force interrupts")
	steps(node, 4)
	near(node.get_parameter_value(&"ParamAngleX"), -8.0, "replacement uses own curve and speed")
	var stopped: Array[int] = []
	replacement.finished.connect(func(reason: int): stopped.append(reason))
	node.stop_motion(0.0)
	node.stop_motion(0.0)
	await process_frame
	expect(stopped == [CubismMotionHandle.STOPPED], "repeat stop terminates once")
	expect(node_terminals.get(looping.get_id(), []) == [CubismMotionHandle.INTERRUPTED], "interrupted node terminal once")
	expect(node_terminals.get(replacement.get_id(), []) == [CubismMotionHandle.STOPPED], "stopped node terminal once")
	var angle := node.get_parameter_value(&"ParamAngleX")
	steps(node, 5)
	near(node.get_parameter_value(&"ParamAngleX"), angle, "zero fade removes native motion immediately")
	var fading := model()
	var fade_handle := fading.play_motion(&"Cue/0")
	var fade_terminals: Array[int] = []
	fading.motion_finished.connect(func(_handle: CubismMotionHandle, _id: StringName, reason: int): fade_terminals.append(reason))
	steps(fading, 5)
	fading.stop_motion(0.2)
	await process_frame
	expect(fade_terminals == [CubismMotionHandle.STOPPED], "fading node terminal once")
	steps(fading, 2)
	expect(fade_handle.get_reason() == CubismMotionHandle.STOPPED, "fade has immediate terminal status")
	var fade_angle := fading.get_parameter_value(&"ParamAngleX")
	expect(fade_angle > 5.0 and fade_angle < 7.0, "outgoing SDK fade blends native curve")
	steps(fading, 4)
	fade_angle = fading.get_parameter_value(&"ParamAngleX")
	steps(fading, 4)
	near(fading.get_parameter_value(&"ParamAngleX"), fade_angle, "fade expires")
	fading.free()
	var overlap := model()
	overlap.play_motion(&"Cue/0", CubismMotionPriority.NORMAL, true)
	steps(overlap, 2)
	overlap.play_motion(&"Cue/1", CubismMotionPriority.FORCE)
	overlap.stop_motion(0.0)
	var overlap_angle := overlap.get_parameter_value(&"ParamAngleX")
	steps(overlap, 1)
	near(overlap.get_parameter_value(&"ParamAngleX"), overlap_angle, "zero stop also removes interrupted fading influence")
	overlap.free()
	# Replaying the same cached source before its first tick must not share loop state.
	var old := node.play_motion(&"Cue/0", CubismMotionPriority.NORMAL, true)
	var fresh := node.play_motion(&"Cue/0", CubismMotionPriority.FORCE, false)
	steps(node, 24)
	await process_frame
	expect(old.get_reason() == CubismMotionHandle.INTERRUPTED and fresh.get_reason() == CubismMotionHandle.COMPLETED, "zero tick replay has independent loop state")
	expect(node_terminals.get(old.get_id(), []) == [CubismMotionHandle.INTERRUPTED], "replayed loop node terminal once")
	expect(node_terminals.get(fresh.get_id(), []) == [CubismMotionHandle.COMPLETED], "replay node terminal once")
	var unloading := node.play_motion(&"Cue/0", CubismMotionPriority.NORMAL, true)
	node.unload_model()
	expect(unloading.get_reason() == CubismMotionHandle.UNLOADED, "unload terminates looping handle")
	expect(node.play_motion(&"Cue/0").get_error() == ERR_UNCONFIGURED, "unloaded play failure")
	node.load_model(resource)
	var reloading := node.play_motion(&"Cue/0")
	node.reload_model()
	expect(reloading.get_reason() == CubismMotionHandle.RELOADED, "reload reason")
	var exiting := node.play_motion(&"Cue/0")
	root.remove_child(node)
	expect(exiting.get_reason() == CubismMotionHandle.UNLOADED, "tree exit terminates handle")
	await process_frame
	expect(node_terminals.get(unloading.get_id(), []) == [CubismMotionHandle.UNLOADED], "unloaded node terminal once")
	expect(node_terminals.get(reloading.get_id(), []) == [CubismMotionHandle.RELOADED], "reloaded node terminal once")
	expect(node_terminals.get(exiting.get_id(), []) == [CubismMotionHandle.UNLOADED], "tree exit node terminal once")
	node.free()
	var doomed := model()
	var retained := doomed.play_motion(&"Cue/0")
	var disposed: Array[int] = []
	retained.finished.connect(func(reason: int): disposed.append(reason))
	doomed.free()
	await process_frame
	expect(retained.get_reason() == CubismMotionHandle.MODEL_DISPOSED and disposed == [CubismMotionHandle.MODEL_DISPOSED], "retained handle survives owner disposal")
	var callback_model := model()
	var callback_handle := callback_model.play_motion(&"Cue/0")
	var callback_terminals: Array[int] = []
	callback_model.motion_finished.connect(func(_handle: CubismMotionHandle, _id: StringName, reason: int): callback_terminals.append(reason))
	callback_handle.event.connect(func(_value: String): callback_model.unload_model(), CONNECT_ONE_SHOT)
	steps(callback_model, 1)
	await process_frame
	await process_frame
	expect(callback_handle.get_reason() == CubismMotionHandle.UNLOADED, "event callback safely unloads model")
	expect(callback_terminals == [CubismMotionHandle.UNLOADED], "callback unload node terminal once")
	callback_model.free()
	var snapshot := model()
	var descriptor := resource.motion_groups["Cue"][0] as CubismMotionDescriptor
	var event := descriptor.events[0] as CubismMotionEvent
	var saved_id := descriptor.id
	var saved_value := event.value
	descriptor.id = &"mutated"
	event.value = "mutated"
	var snapshot_handle := snapshot.play_motion(&"Cue/0")
	var snapshot_events: Array[String] = []
	snapshot_handle.event.connect(func(value: String): snapshot_events.append(value))
	steps(snapshot, 1)
	await process_frame
	expect(snapshot_handle.get_error() == OK and snapshot_events == ["start"], "loaded catalog snapshots descriptor identity and events")
	descriptor.id = saved_id
	event.value = saved_value
	snapshot.free()
	var saved_time := event.time_seconds
	for invalid_time: float in [-1.0, NAN, 1.5]:
		event.time_seconds = invalid_time
		var invalid := model()
		expect(invalid.play_motion(&"Cue/0").get_error() == ERR_INVALID_DATA, "invalid event timing rejected before playback")
		invalid.free()
	event.time_seconds = saved_time
	var other_descriptor := resource.motion_groups["Cue"][1] as CubismMotionDescriptor
	var other_id := other_descriptor.id
	other_descriptor.id = descriptor.id
	var duplicate := model()
	expect(duplicate.play_motion(descriptor.id).get_error() == ERR_INVALID_DATA, "ambiguous motion identity rejected")
	duplicate.free()
	other_descriptor.id = other_id
	await process_frame
	print("CUBISM_MOTION_API checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("MOTION_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_MOTION_API_PASS")
	quit(0 if failures.is_empty() else 1)
