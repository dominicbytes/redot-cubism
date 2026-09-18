# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin
## Serialized legacy inputs are deliberate: instantiating them would run game code.

func _enter_tree() -> void:
	_run.call_deferred()

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var source: String = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json")).model
	var raw := "assets = " + JSON.stringify(source) + "\n"
	var header := "[gd_scene format=3]\n"
	_write("res://legacy-direct.tscn", header + '[node name="Legacy" type="GDCubismUserModel"]\n' + raw)
	_write("res://legacy-empty.tscn", header + '[node name="Empty" type="GDCubismUserModel"]\n')
	_write("res://legacy-base.tscn", header + '[node name="Root" type="Node"]\n[node name="Model" type="GDCubismUserModel" parent="."]\n')
	_write("res://legacy-inherited.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://legacy-base.tscn" id="1"]\n[node name="Root" instance=ExtResource("1")]\n[node name="Model" parent="." index="0"]\n' + raw)
	_write("res://legacy-instance.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://legacy-base.tscn" id="1"]\n[node name="Root" type="Node"]\n[node name="Instance" parent="." instance=ExtResource("1")]\n[node name="Model" parent="Instance" index="0"]\n' + raw)
	_write("res://legacy-root-instance.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://legacy-empty.tscn" id="1"]\n[node name="Root" instance=ExtResource("1")]\n' + raw)
	_write("res://legacy-unrelated.gd", '@tool\nextends Node\n@export var assets: String\nfunc _init():\n\tFileAccess.open("res://unexpected-instantiation", FileAccess.WRITE).store_string("ran")\n')
	_write("res://legacy-unrelated.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://legacy-unrelated.gd" id="1"]\n[node name="Root" type="Node"]\nscript = ExtResource("1")\n' + raw)
	var wrapper := Resource.new()
	wrapper.set_meta("scene", load("res://legacy-direct.tscn").duplicate(true))
	assert(ResourceSaver.save(wrapper, "res://legacy-embedded.tres") == OK)
	var checks: Array[Dictionary] = []
	for name: String in ["direct", "inherited", "instance", "root-instance", "embedded", "empty", "unrelated"]:
		var path := "res://legacy-" + name + (".tres" if name == "embedded" else ".tscn")
		var before := FileAccess.get_sha256(path)
		var result := CubismExportValidator.validate_file(path)
		var should_reject := name not in ["empty", "unrelated"]
		var passed: bool = not result.ok and not result.diagnostics.is_empty() and result.raw_hashes.is_empty() if should_reject else result.ok
		passed = passed and before == FileAccess.get_sha256(path) and not FileAccess.file_exists("res://unexpected-instantiation")
		checks.append({"test": name, "status": "PASS" if passed else "FAIL", "result": result})
	_write("res://legacy-export-report.json", JSON.stringify({"checks": checks}, "\t") + "\n")
	print("CUBISM_LEGACY_EXPORT_OBSERVED")
	get_tree().quit()
