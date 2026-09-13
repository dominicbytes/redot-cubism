# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	if not value: failures.append(label)

func finish() -> void:
	if failures.is_empty(): print("CUBISM_EXPORT_SELECTION_PASS ", OS.get_cmdline_user_args())
	else: printerr("CUBISM_EXPORT_SELECTION_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://selection-expected.json"))
	expect(FileAccess.file_exists(expected.unselected) == ("--all" in arguments), "unselected source follows export filter")
	var model: CubismModelResource
	if "--embedded" in arguments:
		expect(not ResourceLoader.exists("res://imported-model.res"), "standalone model excluded for embedded export")
		var node := (load("res://matrix-embedded.tscn") as PackedScene).instantiate()
		model = node.get_meta("model")
		node.free()
	else:
		model = load("res://imported-model.res") as CubismModelResource
	expect(model != null, "exported model loads")
	if model == null:
		finish()
		return
	for path: String in expected.raw:
		expect(FileAccess.get_sha256(path) == expected.raw[path], "raw dependency bytes: " + path)
	for name: String in ["mask", "mask_add", "mask_add_inv", "mask_mix", "mask_mix_inv", "mask_mul", "mask_mul_inv", "norm_add", "norm_mix", "norm_mul"]:
		expect(load("res://addons/gd_cubism/res/shader/2d_cubism_" + name + ".gdshader") is Shader, "exported shader: " + name)
	var runtime := GDCubismUserModel.new()
	runtime.playback_process_mode = GDCubismUserModel.MANUAL
	root.add_child(runtime)
	runtime.model = model
	expect(runtime.is_initialized(), "runtime initialized")
	if not runtime.is_initialized():
		runtime.free()
		finish()
		return
	var group: String = model.motion_groups.keys()[0]
	expect(runtime.start_motion(group, 0, GDCubismUserModel.PRIORITY_FORCE).get_error() == OK, "start exported motion")
	var before := PackedFloat64Array()
	for parameter: GDCubismParameter in runtime.get_parameters():
		before.append(parameter.value)
	var moved := false
	for frame in 120:
		runtime.advance(1.0 / 60.0)
		var parameters := runtime.get_parameters()
		for index in parameters.size():
			moved = moved or absf(parameters[index].value - before[index]) > 0.0001
	expect(moved, "exported native motion changes model parameters")
	runtime.free()
	finish()
