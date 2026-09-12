# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

class Recorder extends EditorExportPlugin:
	var files: PackedStringArray = []
	func _get_name() -> String:
		return "CubismSelectionOracle"
	func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
		files.clear()
	func _export_file(path: String, type: String, _features: PackedStringArray) -> void:
		if type == "CubismModelResource" or path.get_extension() in ["res", "tres", "tscn", "scn"]:
			files.append(path)
	func _export_end() -> void:
		files.sort()
		var report := FileAccess.open("res://selection-observed.json", FileAccess.WRITE)
		report.store_string(JSON.stringify(files))
		report.close()

var recorder := Recorder.new()

func _enter_tree() -> void:
	add_export_plugin(recorder)

func _exit_tree() -> void:
	remove_export_plugin(recorder)
