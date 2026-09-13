# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

class Poison extends RefCounted:
	var converted := false
	func _to_string() -> String:
		converted = true
		return "Add"

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func plain(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not key is String or not plain(value[key]): return false
		return true
	if value is Array:
		for item in value:
			if not plain(item): return false
		return true
	return value is String or value is bool or value is int or (value is float and is_finite(value))

func pair() -> Dictionary:
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	root.add_child(model)
	expect(model.load_model(resource) == OK, "state fixture loads")
	var controller := CubismCharacterController.new()
	controller.manual_process = true
	root.add_child(controller)
	controller.target_model = model
	return {"model": model, "controller": controller}

func dispose(value: Dictionary) -> void:
	if is_instance_valid(value.controller): value.controller.free()
	if is_instance_valid(value.model): value.model.free()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var missing := CubismCharacterController.new()
	root.add_child(missing)
	expect(missing.capture_state().error == ERR_UNCONFIGURED and missing.restore_state({}) == ERR_UNCONFIGURED, "state requires a loaded target")
	missing.free()
	var original := pair()
	var controller: CubismCharacterController = original.controller
	var target: CubismModel2D = original.model
	controller.idle_motion = &"Cue/1"
	controller.auto_return_to_idle = true
	controller.cue_offset_seconds = 0.125
	controller.transition_seconds = 0.35
	target.transform = Transform2D(Vector2(-1.2, 0.3), Vector2(0.2, 0.8), Vector2(123, -54))
	target.modulate = Color(0.7, 0.5, 0.3, 0.8)
	target.set_expression(&"Add", 0)
	target.set_look_target(Vector2(300, -200), 0.6)
	expect(controller.return_to_idle() == OK, "checkpoint idle starts")
	controller.advance(0.25)
	controller.paused = true
	var captured := controller.capture_state()
	expect(captured.ok and captured.error == OK and plain(captured.state), "checkpoint contains only JSON values")
	var state: Dictionary = captured.state
	expect(state.expression_id == "Add" and state.idle_active and state.look_active, "capture records actual model expression and look choices")
	controller.idle_motion = &"Cue/0"
	expect(controller.capture_state().error == ERR_BUSY, "changed idle selection must be applied before capture")
	controller.idle_motion = &"Cue/1"
	var file := FileAccess.open("user://controller-state.json", FileAccess.WRITE)
	expect(file != null, "open checkpoint file")
	if file:
		file.store_string(JSON.stringify(state))
		file.close()
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://controller-state.json"))
	expect(decoded is Dictionary and plain(decoded), "checkpoint survives JSON file roundtrip")
	var restored := pair()
	var next: CubismCharacterController = restored.controller
	expect(next.restore_state(decoded) == OK, "restore checkpoint on a fresh character")
	var recaptured := next.capture_state()
	expect(recaptured.ok and JSON.stringify(recaptured.state) == JSON.stringify(state), "stable state roundtrip preserves every field")
	expect(next.is_idle() and next.get_motion_handle().get_elapsed_seconds() == 0, "restored idle receives a fresh handle at zero")
	next.advance(0.2)
	expect(next.get_model_time() == 0, "restored pause freezes idle")
	next.paused = false
	next.advance(0.25)
	var reference := pair()
	reference.model.set_expression(&"Add", 0)
	reference.model.set_look_target(Vector2(300, -200), 0.6)
	reference.model.play_motion(&"Cue/1", CubismMotionPriority.IDLE, true, 1)
	for step: float in [0.1, 0.1, 0.05]: reference.model.advance(step)
	for id: StringName in [&"ParamAngleX", &"ParamEyeBallX"]:
		expect(absf(restored.model.get_parameter_value(id) - reference.model.get_parameter_value(id)) < 0.00001, "restored expression/look/idle matches fresh native playback: " + id)
	dispose(reference)
	var peer := CubismCharacterController.new()
	root.add_child(peer)
	peer.target_model = restored.model
	expect(peer.capture_state().error == ERR_BUSY and peer.restore_state(state) == ERR_BUSY and next.is_idle(), "state cannot steal another controller clock")
	peer.free()
	var cue := next.perform(&"Cue/0")
	expect(next.capture_state().error == ERR_BUSY, "active cue cannot be captured as a checkpoint")
	var poison := Poison.new()
	var invalid: Array[Dictionary] = []
	for key in state:
		var without := state.duplicate(true)
		without.erase(key)
		invalid.append(without)
	for entry: Array in [["version", 2], ["version", NAN], ["paused", 1], ["cue_offset_seconds", 61], ["transition_seconds", -1], ["look_weight", INF], ["model_source", "res://another.model3.json"], ["model_fingerprint", "changed"], ["idle_motion", "Missing"], ["expression_id", "Missing"], ["voice_bus", "MissingBus"], ["expression_id", poison], ["modulate", [1, 1, 1]], ["transform", [1, 0, 0, 1, NAN, 0]], ["look_target", [poison, 0]], ["visible", false]]:
		var changed := state.duplicate(true)
		changed[entry[0]] = entry[1]
		invalid.append(changed)
	var extra := state.duplicate(true)
	extra.unknown = 1
	invalid.append(extra)
	var transform_before: Transform2D = restored.model.transform
	for bad in invalid:
		expect(next.restore_state(bad) != OK and not cue.is_finished() and restored.model.transform == transform_before, "invalid state preserves active playback and presentation")
	expect(not poison.converted, "state validation never converts object values")
	var terminals: Array[int] = []
	cue.finished.connect(func(reason: int): terminals.append(reason))
	expect(next.restore_state(state) == OK and cue.get_reason() == CubismSpeechHandle.INTERRUPTED, "valid restore interrupts an existing cue")
	await process_frame
	expect(terminals == [CubismSpeechHandle.INTERRUPTED], "restore completes the old await exactly once")
	next.hide_character(&"fade")
	expect(next.capture_state().error == ERR_BUSY, "visibility fade cannot be captured")
	next.show_character()
	next.stop_speaking(0)
	restored.model.clear_expression(0)
	restored.model.clear_look_target()
	var cleared := next.capture_state()
	expect(cleared.ok and cleared.state.expression_id == "" and not cleared.state.look_active, "cleared expression and look are represented")
	restored.model.hide()
	var hidden := next.capture_state()
	expect(hidden.ok and not hidden.state.visible and not hidden.state.idle_active, "hidden stable checkpoint is capturable")
	expect(controller.restore_state(hidden.state) == OK and not target.visible and not controller.is_idle(), "hidden checkpoint restores without starting idle")
	restored.model.show()
	restored.model.play_motion(&"Cue/0")
	expect(next.capture_state().error == ERR_BUSY, "external active motion is not silently discarded from a save")
	restored.model.stop_motion(0)
	restored.model.reload_model()
	expect(next.capture_state().state.expression_id == "" and not next.capture_state().state.look_active, "reload resets captured expression and look choices")
	var callback_results: Array[int] = []
	var effect := GDCubismEffectCustom.new()
	restored.model.get_node("CubismRuntime").add_child(effect)
	effect.cubism_process.connect(func(_runtime: GDCubismUserModel, _delta: float):
		callback_results.append(next.capture_state().error)
		callback_results.append(next.restore_state(state)), CONNECT_ONE_SHOT)
	restored.model.advance(0.01)
	expect(callback_results == [ERR_BUSY, ERR_BUSY], "native callback cannot capture or restore partially evaluated state")
	effect.free()
	dispose(original)
	dispose(restored)
	var mutable_pair := pair()
	mutable_pair.model.hide()
	var mutable_state := state.duplicate(true)
	mutable_pair.model.visibility_changed.connect(func(): mutable_state.idle_active = false, CONNECT_ONE_SHOT)
	expect(mutable_pair.controller.restore_state(mutable_state) == OK and mutable_pair.controller.is_idle(), "restore uses the validated snapshot despite caller mutation in a scene callback")
	dispose(mutable_pair)
	for action: String in ["queue_model", "reload_model", "queue_controller"]:
		var current := pair()
		current.model.hide()
		current.model.visibility_changed.connect(func():
			if action == "queue_model": current.model.queue_free()
			elif action == "reload_model": current.model.reload_model()
			else: current.controller.queue_free(), CONNECT_ONE_SHOT)
		expect(current.controller.restore_state(state) == ERR_UNAVAILABLE, "restore survives synchronous lifecycle change: " + action)
		await process_frame
		dispose(current)
	if OS.get_cmdline_user_args().has("--prepare-scene"): save_scene()
	var packed := load("res://controller-state.tscn") as PackedScene
	expect(packed != null, "saved native controller scene loads")
	if packed:
		var scene := packed.instantiate()
		root.add_child(scene)
		var component := scene.get_node("Controller") as CubismCharacterController
		var model := scene.get_node("Model") as CubismModel2D
		expect(component.target_model == model and component.manual_process and component.paused and component.auto_return_to_idle and component.idle_motion == &"Cue/1" and is_equal_approx(component.transition_seconds, 0.35), "scene restores native controller properties and target reference")
		expect(component.restore_state(state) == OK, "saved scene accepts the same portable checkpoint")
		component.paused = false
		component.advance(0.25)
		expect(component.is_idle() and is_equal_approx(component.get_motion_handle().get_elapsed_seconds(), 0.25), "restored scene evaluates native idle")
		scene.free()
	await process_frame
	print("CUBISM_CONTROLLER_STATE checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("CONTROLLER_STATE_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_CONTROLLER_STATE_PASS")
	quit(0 if failures.is_empty() else 1)

func save_scene() -> void:
	var scene := Node2D.new()
	scene.name = "Character"
	var model := CubismModel2D.new()
	model.name = "Model"
	scene.add_child(model)
	model.owner = scene
	model.model = resource
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	var controller := CubismCharacterController.new()
	controller.name = "Controller"
	scene.add_child(controller)
	controller.owner = scene
	controller.target_model = model
	controller.manual_process = true
	controller.paused = true
	controller.idle_motion = &"Cue/1"
	controller.auto_return_to_idle = true
	controller.transition_seconds = 0.35
	var packed := PackedScene.new()
	expect(packed.pack(scene) == OK and ResourceSaver.save(packed, "res://controller-state.tscn") == OK, "save native controller scene")
	scene.free()
	var text := FileAccess.get_file_as_string("res://controller-state.tscn")
	for forbidden: String in ["CubismRuntime", "AudioStreamPlayer", "CubismLipSync"]:
		expect(not text.contains(forbidden), "generated child absent from saved scene: " + forbidden)
