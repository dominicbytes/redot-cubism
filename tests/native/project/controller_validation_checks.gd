# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func wave() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(16000)
	stream.data = data
	return stream

func pair() -> Dictionary:
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	root.add_child(model)
	expect(model.load_model(resource) == OK, "safety fixture loads")
	var controller := CubismCharacterController.new()
	controller.manual_process = true
	controller.manual_audio_clock = true
	root.add_child(controller)
	expect(controller.set_target_model(model) == OK, "safety target attaches")
	return {"model": model, "controller": controller}

func dispose(value: Dictionary) -> void:
	if is_instance_valid(value.controller): value.controller.free()
	if is_instance_valid(value.model): value.model.free()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res")
	var current := pair()
	var cue: CubismSpeechHandle = current.controller.perform(&"Cue/0")
	var looping := wave()
	for mode: int in [AudioStreamWAV.LOOP_FORWARD, AudioStreamWAV.LOOP_PINGPONG, AudioStreamWAV.LOOP_BACKWARD]:
		looping.loop_mode = mode
		looping.loop_end = 7999
		expect(current.controller.speak(looping).get_error() == ERR_INVALID_PARAMETER and not cue.is_finished(), "looping WAV preserves cue")
	for compressed: AudioStream in [AudioStreamOggVorbis.new(), AudioStreamMP3.new()]:
		compressed.loop = true
		expect(current.controller.speak(compressed).get_error() == ERR_INVALID_PARAMETER and not cue.is_finished(), "looping compressed stream rejected before length and interruption")
	dispose(current)
	# Existing IDs can be present but unplayable because of invalid event data.
	var descriptor: CubismMotionDescriptor = resource.motion_groups["Cue"][1]
	var event: CubismMotionEvent = descriptor.events[0]
	var previous_time := event.time_seconds
	for bad_time: float in [NAN, 1.5]:
		event.time_seconds = bad_time
		current = pair()
		current.controller.idle_motion = &"Cue/1"
		var captured: Dictionary = current.controller.capture_state().state
		captured.idle_active = true
		captured.transform[4] = 123
		var before: Transform2D = current.model.transform
		cue = current.controller.perform(&"Cue/0")
		expect(current.controller.return_to_idle() == ERR_INVALID_DATA and not cue.is_finished(), "invalid idle preserves cue")
		expect(current.controller.restore_state(captured) == ERR_INVALID_DATA and not cue.is_finished() and current.model.transform == before, "invalid checkpoint idle preserves cue and presentation")
		dispose(current)
	event.time_seconds = previous_time
	await process_frame
	print("CUBISM_CONTROLLER_VALIDATION checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("CONTROLLER_VALIDATION_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_CONTROLLER_VALIDATION_PASS")
	quit(0 if failures.is_empty() else 1)
