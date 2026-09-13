# SPDX-License-Identifier: MIT
extends SceneTree

# Backend-clock qualification, not physical device latency. Dummy's 4096-frame
# buffer at 44100 Hz is about 93 ms; the independently sampled clock is granular.
const CLOCK_TOLERANCE := 0.12
const MOUTH_TOLERANCE := CLOCK_TOLERANCE / 15.0 + 0.0001
var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func wave(seconds: float, amplitude: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var bytes := PackedByteArray()
	bytes.resize(int(seconds * 8000) * 2)
	for sample in int(seconds * 8000): bytes.encode_s16(sample * 2, int(amplitude * 32767))
	stream.data = bytes
	return stream

func pair(bus: StringName = &"Master") -> Dictionary:
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	root.add_child(model)
	expect(model.load_model(resource) == OK, "timing fixture loads")
	var controller := CubismCharacterController.new()
	controller.manual_process = true
	controller.voice_bus = bus
	root.add_child(controller)
	expect(controller.set_target_model(model) == OK, "timing target attaches")
	return {"model": model, "controller": controller}

func dispose(value: Dictionary) -> void:
	value.controller.free()
	value.model.free()

func mouth_at(seconds: float) -> float:
	return seconds / 15.0 if seconds <= 15 else (30 - seconds) / 15.0

func playbacks_released(first: WeakRef, second: WeakRef) -> bool:
	# Keep temporary strong references from get_ref() out of the awaiting frame.
	return first.get_ref() == null and second.get_ref() == null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var previous_fps := Engine.max_fps
	var stream := wave(30, 0.5)
	for fps: int in [15, 30, 60, 0]:
		Engine.max_fps = fps if fps > 0 else 240
		var current := pair()
		var controller: CubismCharacterController = current.controller
		var model: CubismModel2D = current.model
		var profile := CubismLipSyncProfile.new()
		profile.attack = 0
		profile.release = 0
		var speech := controller.speak(stream, &"LongCue/0", &"", profile)
		var player := controller.get_node("Voice") as AudioStreamPlayer
		var started := Time.get_ticks_usec()
		var last := started
		var frames := 0
		var samples := 0
		var stalls := 0
		var max_clock_error := 0.0
		var max_mouth_error := 0.0
		var max_buffer := 0.0
		var max_step := 0.0
		var minimum_position := 30.0
		var maximum_position := 0.0
		while not speech.is_finished() and Time.get_ticks_usec() - started < 60000000:
			if fps == 0:
				await create_timer([0.008, 0.04, 0.09, 0.017, 0.12][frames % 5]).timeout
				if frames > 0 and frames % 40 == 0:
					# Only the main thread stalls; the actual audio mixer keeps running.
					OS.delay_msec(250)
					stalls += 1
			else:
				await process_frame
			var now := Time.get_ticks_usec()
			var delta := float(now - last) / 1000000.0
			last = now
			max_step = maxf(max_step, delta)
			var before := player.get_playback_position()
			controller.advance(delta)
			var after := player.get_playback_position()
			var mix_before := AudioServer.get_time_since_last_mix()
			var next_mix := AudioServer.get_time_to_next_mix()
			var mix_after := AudioServer.get_time_since_last_mix()
			if mix_after >= mix_before: max_buffer = maxf(max_buffer, mix_after + next_mix)
			frames += 1
			# Do not use controller.get_audio_position() or its interpolation formula
			# as the oracle. Bracket the independently read stream position instead.
			if player.playing and before > 0.1 and after >= before and after < 29.8:
				var latency := AudioServer.get_output_latency()
				var low := maxf(0, before - latency)
				var high := maxf(low, after - latency)
				var elapsed := controller.get_motion_handle().get_elapsed_seconds()
				var distance := maxf(maxf(low - elapsed, elapsed - high), 0)
				max_clock_error = maxf(max_clock_error, distance)
				var mouth_low := minf(mouth_at(low), mouth_at(high))
				var mouth_high := 1.0 if low <= 15 and high >= 15 else maxf(mouth_at(low), mouth_at(high))
				var mouth := model.get_parameter_value(&"ParamMouthOpenY")
				max_mouth_error = maxf(max_mouth_error, maxf(maxf(mouth_low - mouth, mouth - mouth_high), 0))
				minimum_position = minf(minimum_position, before)
				maximum_position = maxf(maximum_position, after)
				samples += 1
		var label := str(fps) + " fps" if fps else "variable with stalls"
		expect(speech.is_finished() and speech.get_reason() == CubismSpeechHandle.COMPLETED, "real 30 second cue completes: " + label)
		expect(samples > 100 and minimum_position < 1 and maximum_position > 29, "samples span the full recorded line: " + label)
		expect(max_buffer > 0 and max_buffer < CLOCK_TOLERANCE, "mixer buffer fits declared timing budget: " + label)
		expect(max_clock_error <= CLOCK_TOLERANCE, "real voice/motion drift: " + label)
		expect(max_mouth_error <= MOUTH_TOLERANCE, "authored mouth follows real voice: " + label)
		if fps == 0: expect(stalls >= 3 and max_step >= 0.25, "variable schedule actually includes main-thread stalls")
		print("CUBISM_REAL_AUDIO_TIMING ", JSON.stringify({"fps": fps, "seconds": 30, "frames": frames, "samples": samples,
			"wall_seconds": float(Time.get_ticks_usec() - started) / 1000000.0, "stalls": stalls, "maximum_step": max_step,
			"maximum_buffer_seconds": max_buffer, "maximum_clock_error": max_clock_error, "maximum_mouth_error": max_mouth_error,
			"clock_tolerance": CLOCK_TOLERANCE, "mouth_tolerance": MOUTH_TOLERANCE, "reason": speech.get_reason()}))
		dispose(current)
	Engine.max_fps = 120
	await separate_buses()
	Engine.max_fps = previous_fps
	await process_frame
	print("CUBISM_CONTROLLER_AUDIO_TIMING checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("CONTROLLER_AUDIO_TIMING_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_CONTROLLER_AUDIO_TIMING_PASS")
	quit(0 if failures.is_empty() else 1)

func separate_buses() -> void:
	var initial_count := AudioServer.bus_count
	for bus: StringName in [&"ControllerVoiceA", &"ControllerVoiceB"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	var first := pair(&"ControllerVoiceA")
	var second := pair(&"ControllerVoiceB")
	var profile := CubismLipSyncProfile.new()
	profile.attack = 0
	profile.release = 0
	var a: CubismSpeechHandle = first.controller.speak(wave(2, 0.2), &"", &"", profile)
	var b: CubismSpeechHandle = second.controller.speak(wave(2, 0.8), &"", &"", profile)
	var playback_a: WeakRef = weakref(first.controller.get_node("Voice").get_stream_playback())
	var playback_b: WeakRef = weakref(second.controller.get_node("Voice").get_stream_playback())
	await create_timer(0.25).timeout
	first.controller.advance(0.25)
	second.controller.advance(0.25)
	expect(absf(first.model.get_parameter_value(&"ParamMouthOpenY") - 0.16) < 0.01, "first controller reads only its quiet voice bus")
	expect(absf(second.model.get_parameter_value(&"ParamMouthOpenY") - 0.64) < 0.01, "second controller reads only its loud voice bus")
	first.controller.paused = true
	var frozen: float = first.controller.get_model_time()
	var running: float = second.controller.get_model_time()
	await create_timer(0.2).timeout
	first.controller.advance(0.2)
	second.controller.advance(0.2)
	expect(first.controller.get_model_time() == frozen and not a.is_finished(), "pausing one voice freezes only its own cue")
	expect(second.controller.get_model_time() > running and not b.is_finished(), "other controller continues while first is paused")
	first.controller.stop_speaking(0)
	running = second.controller.get_model_time()
	await create_timer(0.2).timeout
	second.controller.advance(0.2)
	expect(a.get_reason() == CubismSpeechHandle.STOPPED and second.controller.get_model_time() > running and not b.is_finished(), "stopping one voice leaves the other cue active")
	expect(absf(second.model.get_parameter_value(&"ParamMouthOpenY") - 0.64) < 0.01, "other lip envelope survives first controller stop")
	dispose(first)
	dispose(second)
	# AudioServer removes stopped streams on its mixer thread and releases their
	# references on a later main-thread update. Verify that cleanup before quitting.
	var deadline := Time.get_ticks_msec() + 1000
	while not playbacks_released(playback_a, playback_b) and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	expect(playbacks_released(playback_a, playback_b), "disposed controller voice playbacks are released")
	while AudioServer.bus_count > initial_count: AudioServer.remove_bus(AudioServer.bus_count - 1)
