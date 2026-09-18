# SPDX-License-Identifier: MIT
extends SceneTree

const CASES := {
	"normal": true,
	"missing_physics": true,
	"missing_pose": true,
	"missing_userdata": true,
	"empty_physics": true,
	"empty_pose": true,
	"empty_userdata": true,
	"malformed_physics": false,
	"malformed_pose": false,
	"malformed_userdata": false,
	"svg_texture": true,
}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var results := {}
	var svg := ResourceLoader.load("res://fixture/texture.svg")
	results["svg_resource_is_texture2d"] = svg is Texture2D
	for case_name: String in CASES:
		var model := GDCubismUserModel.new()
		host.add_child(model)
		model.assets = "res://fixture/" + case_name + ".model3.json"
		results[case_name] = model.is_initialized()
		model.free()
	host.free()
	print("CUBISM_RAW_ASSET_PARITY:" + JSON.stringify(results))
	var success: bool = results["svg_resource_is_texture2d"]
	for case_name: String in CASES:
		if results[case_name] != CASES[case_name]:
			success = false
	quit(0 if success else 1)
