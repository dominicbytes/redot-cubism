# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "CubismAbiExportProbe"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	add_file("res://probe.raw", FileAccess.get_file_as_bytes("res://probe.raw"), false)
	print("CUBISM_ABI_EXPORT_INJECTED")
