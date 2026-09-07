# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
@tool
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "cubism.abi.synthetic"

func _get_visible_name() -> String:
	return "Cubism ABI synthetic"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["model3.json"])

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	return "CubismAbiResource"

func _get_priority() -> float:
	return 1.0

func _get_preset_count() -> int:
	return 0

func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []

func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	if not source_file.ends_with(".model3.json"):
		return ERR_FILE_UNRECOGNIZED
	var resource := CubismAbiResource.new()
	resource.source = source_file
	print("CUBISM_ABI_IMPORTED:", source_file)
	return ResourceSaver.save(resource, save_path + ".res")
