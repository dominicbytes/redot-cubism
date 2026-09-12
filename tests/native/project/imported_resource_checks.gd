# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	var model := ResourceLoader.load("res://imported-model.res", "CubismModelResource")
	if not model is CubismModelResource:
		printerr("IMPORTED_RESOURCE_MISSING")
		quit(1)
		return
	if model.source_hash != FileAccess.get_sha256(model.source_model_path) or model.textures.is_empty() or model.motion_groups.is_empty():
		printerr("IMPORTED_RESOURCE_DATA_MISMATCH")
		quit(1)
		return
	if not OS.has_feature("editor") and ClassDB.class_exists("CubismModelImporter"):
		printerr("EDITOR_IMPORTER_PRESENT_IN_TEMPLATE")
		quit(1)
		return
	print("CUBISM_IMPORTED_RESOURCE_PASS")
	quit()
