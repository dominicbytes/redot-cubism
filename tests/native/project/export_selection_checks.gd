# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://selection-expected.json"))
	assert(FileAccess.file_exists(expected.unselected) == ("--all" in arguments))
	var model: CubismModelResource
	if "--embedded" in arguments:
		assert(not ResourceLoader.exists("res://imported-model.res"))
		var node := (load("res://matrix-embedded.tscn") as PackedScene).instantiate()
		model = node.get_meta("model")
		node.free()
	else:
		model = load("res://imported-model.res") as CubismModelResource
	assert(model != null)
	for path: String in expected.raw:
		assert(FileAccess.get_sha256(path) == expected.raw[path])
	for name: String in ["mask", "mask_add", "mask_add_inv", "mask_mix", "mask_mix_inv", "mask_mul", "mask_mul_inv", "norm_add", "norm_mix", "norm_mul"]:
		assert(load("res://addons/gd_cubism/res/shader/2d_cubism_" + name + ".gdshader") is Shader)
	var runtime := GDCubismUserModel.new()
	runtime.playback_process_mode = GDCubismUserModel.MANUAL
	root.add_child(runtime)
	runtime.model = model
	assert(runtime.is_initialized())
	var group: String = model.motion_groups.keys()[0]
	assert(runtime.start_motion(group, 0, GDCubismUserModel.PRIORITY_FORCE).get_error() == OK)
	var before := PackedFloat64Array()
	for parameter: GDCubismParameter in runtime.get_parameters():
		before.append(parameter.value)
	var moved := false
	for frame in 120:
		runtime.advance(1.0 / 60.0)
		var parameters := runtime.get_parameters()
		for index in parameters.size():
			moved = moved or absf(parameters[index].value - before[index]) > 0.0001
	assert(moved, "Exported native motion must change model parameters")
	runtime.free()
	print("CUBISM_EXPORT_SELECTION_PASS ", arguments)
	quit()
