# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var path := "res://mask-quality-model.res"
	if CubismModelImporter.import_model_with_options(fixture.model, path, {"rendering/mask_quality": 2}) != OK:
		get_tree().quit(1)
		return
	var model := ResourceLoader.load(path, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	if model == null or model.get_mask_quality() != 2 or not CubismExportValidator.validate_model(model).ok:
		get_tree().quit(1)
		return
	print("CUBISM_MASK_QUALITY_IMPORT_PASS")
	get_tree().quit()
