# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func make_pair() -> Dictionary:
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	root.add_child(model)
	expect(model.load_model(resource) == OK, "lip fixture loads")
	var lip := CubismLipSync.new()
	lip.profile = CubismLipSyncProfile.new()
	root.add_child(lip)
	expect(lip.set_target_model(model) == OK, "lip target attaches")
	return {"model": model, "lip": lip}

func mouth(model: CubismModel2D) -> float:
	return model.get_parameter_value(&"ParamMouthOpenY")

func dispose(pair: Dictionary) -> void:
	pair.model.free()
	expect(pair.lip.target_model == null, "model disposal clears component target")
	pair.lip.free()

func tone(bus: StringName, amplitude: float) -> AudioStreamPlayer:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 4409 # Redot's loop limit is the last valid sample frame.
	var data := PackedByteArray()
	data.resize(8820)
	for frame in 4410: data.encode_s16(frame * 2, int(amplitude * 32767.0))
	stream.data = data
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	root.add_child(player)
	player.play()
	return player

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res") as CubismModelResource
	var pair := make_pair()
	var node: CubismModel2D = pair.model
	var lip: CubismLipSync = pair.lip
	var profile := lip.profile
	profile.noise_gate = 0.1
	profile.attack = 0.1
	profile.release = 0.2
	var expected := 0.0
	for sample: float in [0.0, 0.09, 0.5, 1.0, 1.0, 0.0, 0.0, 0.0]:
		expect(lip.submit_sample(sample) == OK, "manual amplitude accepted")
		var desired := sample if sample >= 0.1 else 0.0
		var seconds := 0.1 if desired > expected else 0.2
		expected = desired + (expected - desired) * exp(-0.05 / seconds)
		node.advance(0.05)
		expect(absf(lip.get_envelope() - expected) < 0.000001, "known attack/release envelope")
		expect(absf(mouth(node) - expected * 0.8) < 0.000001, "SDK default additive lip range")
	lip.reset()
	lip.submit_sample(1.0)
	node.speed_scale = 2.0
	node.advance(0.025)
	expect(absf(lip.get_envelope() - (1.0 - exp(-0.5))) < 0.000001, "model speed scales envelope time")
	node.speed_scale = 1.0
	var previous := lip.get_envelope()
	node.paused = true
	lip.submit_sample(1.0)
	node.advance(0.05)
	expect(lip.get_envelope() == previous, "model pause freezes envelope")
	node.paused = false
	node.enable_lip_sync = false
	node.advance(0.05)
	expect(lip.get_envelope() == previous and is_zero_approx(mouth(node)), "model effect switch freezes and releases")
	node.enable_lip_sync = true
	profile.attack = 0.0
	profile.release = 0.0
	profile.gain = 2.0
	lip.submit_sample(1.0e300)
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.8), "finite extreme sample and gain clamp")
	expect(profile.set_gain(NAN) == ERR_INVALID_PARAMETER and profile.gain == 2.0, "invalid gain rejected")
	expect(profile.set_attack(-1.0) == ERR_INVALID_PARAMETER and profile.set_maximum(-1.0) == ERR_INVALID_PARAMETER, "invalid time/range rejected")
	profile.minimum = 0.2
	lip.submit_sample(0.0)
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.2), "profile minimum maps silence")
	profile.minimum = 0.0
	profile.gain = 1.0
	lip.submit_sample(0.5)
	for invalid: float in [-1.0, NAN, INF]: expect(lip.submit_sample(invalid) == ERR_INVALID_PARAMETER, "invalid amplitude rejected")
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.4), "invalid samples preserve prior input")
	profile.noise_gate = 0.0
	expect(lip.submit_peak_db(-20.0, -40.0) == OK, "manual dB accepted")
	node.advance(0.05)
	expect(absf(mouth(node) - 0.08) < 0.000001, "dB peak converts stereo maximum")
	expect(lip.submit_peak_db(NAN, 0.0) == ERR_INVALID_PARAMETER and lip.submit_peak_db(INF, 0.0) == ERR_INVALID_PARAMETER, "invalid dB rejected")
	expect(lip.submit_peak_db(-INF, -INF) == OK, "negative infinite dB is silence")
	node.advance(0.05)
	expect(is_zero_approx(mouth(node)), "silence finite and closed")
	profile.parameter_ids = PackedStringArray(["ParamMouthOpenY", "ParamAngleY", "ParamMouthOpenY", "Missing"])
	profile.mouth_form_parameter = &"ParamMouthForm"
	profile.mouth_form_value = -0.5
	lip.submit_sample(0.5)
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.4) and is_equal_approx(node.get_parameter_value(&"ParamAngleY"), 0.4), "multiple parameters and duplicate suppression")
	expect(lip.get_last_error() == ERR_DOES_NOT_EXIST, "missing parameter reported")
	expect(is_equal_approx(node.get_parameter_value(&"ParamMouthForm"), -0.5), "optional mouth form")
	node.set_parameter_value(&"ParamMouthOpenY", 0.15)
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.15), "post effect override wins over lip sync")
	var other := CubismLipSync.new()
	root.add_child(other)
	expect(other.set_target_model(node) == ERR_ALREADY_IN_USE, "second writer rejected deterministically")
	other.free()
	lip.enabled = false
	node.advance(0.05)
	expect(is_zero_approx(mouth(node)) and is_zero_approx(lip.get_envelope()), "disabling stops and resets")
	lip.enabled = true
	lip.submit_sample(1.0)
	node.reload_model()
	node.advance(0.05)
	expect(is_zero_approx(mouth(node)) and is_zero_approx(lip.get_envelope()), "reload clears envelope and sample")
	root.remove_child(lip)
	root.add_child(lip)
	expect(lip.target_model == node, "component reentry retains target selection")
	dispose(pair)
	for motion: StringName in [&"Lips/0", &"ModelLips/0"]:
		pair = make_pair()
		node = pair.model
		lip = pair.lip
		lip.profile.attack = 0.0
		lip.submit_sample(1.0)
		expect(node.play_motion(motion, CubismMotionPriority.NORMAL, true).get_error() == OK, "authored mouth motion starts")
		for frame in 10:
			node.advance(0.05)
			expect(is_equal_approx(mouth(node), 0.25), "authored parameter/model lip curves own mouth")
		node.stop_motion(0.2)
		for frame in 2:
			node.advance(0.05)
			expect(is_equal_approx(mouth(node), 0.25), "outgoing motion fade retains mouth ownership")
		lip.profile.blend_with_authored = true
		node.advance(0.05)
		expect(is_equal_approx(mouth(node), 1.0), "explicit additive authored blend")
		dispose(pair)
	pair = make_pair()
	node = pair.model
	lip = pair.lip
	lip.profile.attack = 0.0
	lip.submit_sample(1.0)
	expect(node.set_expression(&"Mouth", 0.0) == OK, "mouth expression starts")
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.3), "expression owns mouth")
	node.clear_expression(0.2)
	node.advance(0.05)
	node.advance(0.05)
	expect(mouth(node) < 0.3, "fading expression retains ownership")
	node.clear_expression(0.0)
	node.advance(0.05)
	expect(is_equal_approx(mouth(node), 0.8), "cleared expression releases ownership")
	dispose(pair)
	var first := make_pair()
	var second := make_pair()
	first.lip.profile.attack = 0.1
	second.lip.profile = first.lip.profile
	for frame in 30:
		first.lip.submit_sample(float(frame % 5) / 4.0)
		second.lip.submit_sample(float(frame % 5) / 4.0)
		second.model.advance(0.05)
		first.model.advance(0.05)
		expect(first.lip.get_envelope() == second.lip.get_envelope(), "shared profile keeps independent clocks")
	first.lip.reset()
	expect(second.lip.get_envelope() > 0.0, "one character reset does not reset another")
	for bus: StringName in [&"CubismTestA", &"CubismTestB"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	first.lip.input_mode = CubismLipSync.AUDIO_BUS_PEAK
	second.lip.input_mode = CubismLipSync.AUDIO_BUS_PEAK
	first.lip.audio_bus = &"CubismTestA"
	second.lip.audio_bus = &"CubismTestB"
	first.lip.profile.attack = 0.0
	first.lip.profile.release = 0.0
	var voice_a := tone(&"CubismTestA", 0.25)
	var voice_b := tone(&"CubismTestB", 0.75)
	await create_timer(0.3).timeout
	first.model.advance(0.05)
	second.model.advance(0.05)
	expect(absf(mouth(first.model) - 0.2) < 0.01 and absf(mouth(second.model) - 0.6) < 0.01, "two generated voices use independent bus meters without audio hardware")
	voice_a.stop()
	voice_b.stop()
	await create_timer(0.3).timeout
	first.model.advance(0.05)
	second.model.advance(0.05)
	expect(is_zero_approx(mouth(first.model)) and is_zero_approx(mouth(second.model)), "audio stop closes mouths")
	first.lip.audio_bus = &"MissingBus"
	first.model.advance(0.05)
	expect(first.lip.get_last_error() == ERR_DOES_NOT_EXIST and is_zero_approx(mouth(first.model)), "missing audio bus is silent and reported")
	voice_a.free()
	voice_b.free()
	dispose(first)
	dispose(second)
	AudioServer.remove_bus(AudioServer.get_bus_index(&"CubismTestB"))
	AudioServer.remove_bus(AudioServer.get_bus_index(&"CubismTestA"))
	if OS.get_cmdline_user_args().has("--prepare-scene"):
		var saved := CubismModel2D.new()
		saved.name = "SpeakingCharacter"
		saved.playback_process_mode = CubismModel2D.MANUAL
		saved.enable_physics = false
		saved.enable_pose = false
		saved.model = resource
		var component := CubismLipSync.new()
		component.name = "Envelope"
		saved.add_child(component)
		component.owner = saved
		expect(component.set_target_model(saved) == OK, "saved component target")
		component.profile = CubismLipSyncProfile.new()
		component.profile.gain = 1.75
		component.profile.maximum = 0.9
		component.profile.attack = 0.0
		var packed := PackedScene.new()
		expect(packed.pack(saved) == OK and ResourceSaver.save(packed, "res://lip-sync.tscn") == OK, "save native component and profile")
		saved.free()
	var scene := load("res://lip-sync.tscn") as PackedScene
	expect(scene != null, "load component scene")
	if scene:
		var reopened := scene.instantiate() as CubismModel2D
		root.add_child(reopened)
		var component := reopened.get_node("Envelope") as CubismLipSync
		expect(component.target_model == reopened and component.profile.gain == 1.75 and is_equal_approx(component.profile.maximum, 0.9), "persisted target and profile")
		component.submit_sample(0.4)
		reopened.advance(0.05)
		expect(absf(mouth(reopened) - 0.63) < 0.00001, "restored component drives loaded model")
		reopened.free()
	await process_frame
	print("CUBISM_LIP_SYNC checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("LIP_SYNC_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_LIP_SYNC_PASS")
	quit(0 if failures.is_empty() else 1)
