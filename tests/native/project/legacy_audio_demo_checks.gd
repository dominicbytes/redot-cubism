# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var resource := load("res://factory-model.res") as CubismModelResource
	expect(not resource.lip_sync_parameter_ids.is_empty(), "fixture supplies a mouth parameter")
	if resource.lip_sync_parameter_ids.is_empty():
		quit(1)
		return
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "LegacyDemoVoice")
	AudioServer.add_bus_effect(bus, AudioEffectSpectrumAnalyzer.new())
	var demo: Node2D = load("res://addons/gd_cubism/example/demo_effect_custom_03.gd").new()
	demo.set("audio_bus_name", "LegacyDemoVoice")
	demo.set("param_mouth_name", resource.lip_sync_parameter_ids[0])
	var model := GDCubismUserModel.new()
	model.name = "GDCubismUserModel"
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	var effect := GDCubismEffectCustom.new()
	effect.name = "GDCubismEffectCustom"
	model.add_child(effect)
	demo.add_child(model)
	model.assets = fixture.model
	root.add_child(demo)
	demo.set_process(false)
	expect(effect.cubism_init.is_connected(demo._on_cubism_init), "demo connects initialization")
	expect(effect.cubism_term.is_connected(demo._on_cubism_term), "demo connects termination")
	model.advance(0.016)
	expect(demo.get("lipsync_ready"), "configured analyzer initializes through native lifecycle")
	var mouth: GDCubismParameter = demo.get("param_mouth")
	if mouth != null:
		mouth.value = 1.0
		model.advance(0.016)
		expect(is_equal_approx(mouth.value, 0.8), "configured process updates the mouth from analyzer silence")
		for invalid: int in [0, -1]:
			demo.set("history_size", invalid)
			mouth.value = 1.0
			model.advance(0.016)
			expect(is_equal_approx(mouth.value, 1.0), "invalid history size skips processing")
		demo.set("history_size", 2)
		for invalid: float in [0.0, -1.0, NAN, INF]:
			demo.set("min_db", invalid)
			mouth.value = 1.0
			model.advance(0.016)
			expect(is_equal_approx(mouth.value, 1.0), "invalid dB range skips processing")
		demo.set("min_db", 60.0)
		mouth.value = 1.0
		model.advance(0.016)
		expect(is_equal_approx(mouth.value, 0.8), "resized history resumes processing")
	for config in [["MissingLegacyDemoBus", 0], ["LegacyDemoVoice", -1], ["LegacyDemoVoice", 1]]:
		demo.set("audio_bus_name", config[0])
		demo.set("audio_efx_index", config[1])
		demo._on_cubism_init(model)
		expect(not demo.get("lipsync_ready"), "missing bus or effect stays inactive")
	AudioServer.remove_bus_effect(bus, 0)
	AudioServer.add_bus_effect(bus, AudioEffectAmplify.new())
	demo.set("audio_bus_name", "LegacyDemoVoice")
	demo.set("audio_efx_index", 0)
	demo._on_cubism_init(model)
	expect(not demo.get("lipsync_ready"), "unrelated bus effect stays inactive")
	AudioServer.remove_bus_effect(bus, 0)
	AudioServer.add_bus_effect(bus, AudioEffectSpectrumAnalyzer.new())
	demo._on_cubism_init(model)
	expect(demo.get("lipsync_ready"), "valid analyzer can initialize again")
	model.unload_model()
	expect(not demo.get("lipsync_ready") and demo.get("param_mouth") == null and demo.get("spectrum") == null, "native termination clears demo state")
	demo.free()
	AudioServer.remove_bus(bus)
	for failure in failures: printerr("CUBISM_LEGACY_AUDIO_DEMO_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_LEGACY_AUDIO_DEMO_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
