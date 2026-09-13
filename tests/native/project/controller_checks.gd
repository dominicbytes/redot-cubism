# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func wave(seconds: float, amplitude := 0.0) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(int(seconds * 8000.0) * 2)
	if amplitude > 0:
		for frame in int(seconds * 8000.0): data.encode_s16(frame * 2, int(amplitude * 32767.0))
	stream.data = data
	return stream

func pair(fake := true) -> Dictionary:
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	root.add_child(model)
	expect(model.load_model(resource) == OK, "fixture loads")
	var controller := CubismCharacterController.new()
	controller.manual_process = true
	controller.manual_audio_clock = fake
	root.add_child(controller)
	expect(controller.set_target_model(model) == OK, "controller selects model")
	return {"model": model, "controller": controller}

func dispose(value: Dictionary) -> void:
	value.controller.free()
	value.model.free()

func clock_sample(controller: CubismCharacterController) -> Array:
	var player := controller.get_node("Voice") as AudioStreamPlayer
	return [player.get_playback_position(), player.playing, player.stream_paused, controller.get_audio_position(), AudioServer.get_time_since_last_mix(), AudioServer.get_time_to_next_mix()]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var p := pair()
	var controller: CubismCharacterController = p.controller
	var model: CubismModel2D = p.model
	var bad := controller.speak(null)
	expect(bad.is_finished() and bad.get_error() == ERR_INVALID_PARAMETER, "null stream fails before await")
	bad = controller.perform(&"Missing")
	expect(bad.is_finished() and bad.get_error() == ERR_DOES_NOT_EXIST, "unknown motion fails before await")
	model.speed_scale = 2
	var performance := controller.perform(&"Cue/0", &"Add")
	var terminals: Array[int] = []
	performance.finished.connect(func(reason: int): terminals.append(reason))
	expect(not performance.is_finished() and model.speed_scale == 1, "normal speed clock claimed")
	model.advance(0.1)
	expect(controller.get_motion_handle().get_elapsed_seconds() == 0, "external advance cannot double step controlled model")
	controller.advance(0.25)
	expect(absf(controller.get_motion_handle().get_elapsed_seconds() - 0.25) < 0.000001, "large frame is substepped without lost time")
	controller.paused = true
	controller.advance(0.5)
	expect(absf(controller.get_model_time() - 0.25) < 0.000001, "pause freezes no-audio cue")
	controller.paused = false
	controller.advance(0.85)
	await process_frame
	expect(performance.is_finished() and terminals == [CubismSpeechHandle.COMPLETED], "no audio performance completes once")
	performance.call("_dispatch_finished")
	expect(terminals == [CubismSpeechHandle.COMPLETED], "terminal dispatcher cannot repeat completion")
	expect(model.speed_scale == 2 and model.playback_process_mode == CubismModel2D.MANUAL, "clock settings restored")
	model.speed_scale = 1
	var voice := wave(2)
	var speech := controller.speak(voice, &"Lips/0")
	controller.submit_audio_clock(0.5)
	controller.advance(0.03)
	expect(absf(model.get_parameter_value(&"ParamMouthOpenY") - 0.25) < 0.00001, "voiced authored mouth pose")
	controller.submit_audio_clock(1.1)
	controller.advance(0.03)
	expect(controller.get_motion_handle().is_finished() and not speech.is_finished(), "motion end does not truncate voice")
	controller.submit_audio_clock(2, true)
	controller.advance(0.03)
	expect(speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED, "voice ends after motion")
	speech = controller.speak(wave(0.25), &"Cue/0")
	controller.submit_audio_clock(0.25, true)
	controller.advance(0.03)
	expect(not speech.is_finished(), "voice end does not truncate motion")
	controller.advance(0.8)
	expect(speech.is_finished(), "motion tail completes after voice")
	for offset: float in [0.2, -0.2]:
		controller.cue_offset_seconds = offset
		speech = controller.speak(voice, &"Cue/0")
		controller.submit_audio_clock(0.5)
		controller.advance(0.03)
		expect(absf(controller.get_motion_handle().get_elapsed_seconds() - (0.5 - offset)) < 0.000001, "signed cue offset aligns motion")
		controller.stop_speaking(0)
	controller.cue_offset_seconds = 0.2
	speech = controller.speak(wave(0.1))
	controller.submit_audio_clock(0.1, true)
	controller.advance(0.1)
	expect(speech.is_finished(), "motion offset does not delay voice-only completion")
	speech = controller.speak(voice, &"Cue/0")
	controller.submit_audio_clock(0.1)
	controller.advance(0.1)
	controller.stop_speaking(0.5)
	controller.advance(0.5)
	expect(controller.get_motion_handle() == null, "stopped delayed cue cannot start during outgoing fade")
	controller.cue_offset_seconds = 0
	speech = controller.perform(&"Cue/0")
	controller.advance(0.2)
	controller.stop_speaking(0.1)
	expect(speech.is_finished() and speech.get_reason() == CubismSpeechHandle.STOPPED, "fade cancellation terminal is immediate")
	controller.advance(0.1)
	expect(absf(controller.get_model_time() - 0.3) < 0.000001, "final fade frame is evaluated before clock release")
	var first := controller.speak(voice, &"Cue/0")
	var interrupted: Array[int] = []
	first.finished.connect(func(reason: int): interrupted.append(reason))
	speech = controller.perform(&"Cue/1")
	await process_frame
	expect(first.is_finished() and interrupted == [CubismSpeechHandle.INTERRUPTED], "replacement terminates old speech once")
	controller.stop_speaking(0)
	await process_frame
	expect(interrupted == [CubismSpeechHandle.INTERRUPTED], "later stop does not change old terminal")
	speech = controller.speak(voice, &"Cue/0")
	var second := CubismCharacterController.new()
	root.add_child(second)
	second.target_model = model
	expect(second.perform(&"Cue/0").get_error() == ERR_ALREADY_IN_USE, "second controller cannot own model clock")
	second.free()
	controller.submit_audio_clock(0.5)
	controller.advance(0.03)
	controller.submit_audio_clock(0.48)
	controller.advance(0.03)
	expect(not speech.is_finished() and is_equal_approx(controller.get_audio_position(), 0.5), "small backward jitter clamps monotonically")
	controller.submit_audio_clock(0.1)
	controller.advance(0.03)
	expect(speech.is_finished() and speech.get_error() == ERR_UNAVAILABLE, "unsupported backwards seek terminates explicitly")
	for action: String in ["hide", "reload", "controller_exit", "model_free", "controller_free"]:
		var current := pair()
		var handle: CubismSpeechHandle = current.controller.speak(voice, &"Cue/0")
		if action == "hide": current.model.hide()
		elif action == "reload": current.model.reload_model()
		elif action == "controller_exit": root.remove_child(current.controller)
		elif action == "model_free": current.model.free()
		else: current.controller.free()
		if is_instance_valid(current.controller): current.controller.advance(0.05)
		var reason := CubismSpeechHandle.HIDDEN if action == "hide" else (CubismSpeechHandle.MODEL_DISPOSED if action == "model_free" else (CubismSpeechHandle.CONTROLLER_DISPOSED if action == "controller_free" else CubismSpeechHandle.UNLOADED))
		expect(handle.is_finished() and handle.get_reason() == reason, "lifecycle terminates: " + action)
		if is_instance_valid(current.controller): current.controller.free()
		if is_instance_valid(current.model): current.model.free()
	dispose(p)
	# Long-line fake audio authority exercises the real controller/model integration.
	var long_voice := wave(30)
	for fps: int in [15, 30, 60]:
		p = pair()
		controller = p.controller
		speech = controller.speak(long_voice, &"LongCue/0")
		var maximum_error := 0.0
		var maximum_pose_error := 0.0
		for frame in 30 * fps:
			var position := float(frame + 1) / fps
			controller.submit_audio_clock(position, frame + 1 == 30 * fps)
			controller.advance(1.0 / fps)
			maximum_error = maxf(maximum_error, absf(controller.get_model_time() - position))
			maximum_error = maxf(maximum_error, absf(controller.get_motion_handle().get_elapsed_seconds() - position))
			var expected_mouth := position / 15.0 if position <= 15.0 else (30.0 - position) / 15.0
			maximum_pose_error = maxf(maximum_pose_error, absf(p.model.get_parameter_value(&"ParamMouthOpenY") - expected_mouth))
		expect(speech.is_finished() and maximum_error < 0.000001, "30 second fake clock drift at " + str(fps) + " fps")
		expect(maximum_pose_error < 0.00001, "30 second authored mouth poses at " + str(fps) + " fps")
		print("CUBISM_CUE_DRIFT fps=", fps, " seconds=30 maximum_seconds=", maximum_error, " maximum_mouth_error=", maximum_pose_error)
		dispose(p)
	# Real generated audio, with Dummy driver: no microphone or hardware needed.
	p = pair(false)
	controller = p.controller
	model = p.model
	var profile := CubismLipSyncProfile.new()
	profile.attack = 0
	profile.release = 0
	speech = controller.speak(wave(0.7, 0.5), &"", &"", profile)
	var saw_open := false
	var audio_trace: Array = []
	for frame in 120:
		await create_timer(0.01).timeout
		audio_trace.append(clock_sample(controller))
		if audio_trace.size() > 8: audio_trace.pop_front()
		controller.advance(0.01)
		if model.get_parameter_value(&"ParamMouthOpenY") > 0.1: saw_open = true
		if speech.is_finished(): break
	expect(saw_open and speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED, "real voice-only clock and envelope finish")
	if not (saw_open and speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED):
		print("CUBISM_AUDIO_DIAGNOSTIC saw_open=", saw_open, " terminal=", speech.is_finished(), " reason=", speech.get_reason(), " error=", speech.get_error(), " trace=", audio_trace)
	speech = controller.speak(wave(0.7, 0.5), &"Lips/0", &"", profile)
	await create_timer(0.15).timeout
	controller.advance(0.15)
	expect(absf(model.get_parameter_value(&"ParamMouthOpenY") - 0.25) < 0.00001, "real voiced cue protects authored mouth")
	controller.paused = true
	var paused_time := controller.get_model_time()
	await create_timer(0.12).timeout
	controller.advance(0.12)
	expect(controller.get_model_time() == paused_time and not speech.is_finished(), "real audio pause does not signal completion")
	controller.paused = false
	audio_trace.clear()
	for frame in 150:
		await create_timer(0.01).timeout
		audio_trace.append(clock_sample(controller))
		if audio_trace.size() > 8: audio_trace.pop_front()
		controller.advance(0.01)
		if speech.is_finished(): break
	expect(speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED, "real voiced cue resumes and completes")
	if not (speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED):
		print("CUBISM_RESUME_DIAGNOSTIC terminal=", speech.is_finished(), " reason=", speech.get_reason(), " error=", speech.get_error(), " trace=", audio_trace)
	controller.manual_process = false
	for repetition in 5:
		speech = controller.speak(wave(0.1), &"")
		for frame in 90:
			await process_frame
			if speech.is_finished(): break
		expect(speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED, "automatic short-voice end preserves clock")
	dispose(p)
	await process_frame
	print("CUBISM_CONTROLLER checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("CONTROLLER_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_CONTROLLER_PASS")
	quit(0 if failures.is_empty() else 1)
