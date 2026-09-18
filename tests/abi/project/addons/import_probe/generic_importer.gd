# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
# Test competitor only; the production Cubism importer must not claim generic JSON.
@tool
extends "res://addons/import_probe/importer.gd"

func _get_importer_name() -> String:
	return "cubism.abi.generic_competitor"

func _get_visible_name() -> String:
	return "ABI generic JSON competitor"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["json"])

func _get_resource_type() -> String:
	return "Resource"

func _get_priority() -> float:
	return 0.5

func _import(_source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var resource := Resource.new()
	resource.set_meta("generic_json", true)
	return ResourceSaver.save(resource, save_path + ".res")
