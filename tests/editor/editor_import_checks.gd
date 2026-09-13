# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	# Let the editor finish constructing and scanning before requesting shutdown.
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	assert(CubismModelImporter.import_model("res://hero.json", "res://invalid.res") == ERR_FILE_UNRECOGNIZED)
	assert(CubismModelImporter.import_model("res://not_model3.json.backup", "res://invalid.res") == ERR_FILE_UNRECOGNIZED)
	assert(CubismModelImporter.import_model(source, source) == ERR_INVALID_PARAMETER)
	assert(CubismModelImporter.import_model(source, "user://invalid.res") == ERR_FILE_BAD_PATH)
	assert(not FileAccess.file_exists("res://invalid.res"))
	assert(CubismModelImporter.import_model(source, "res://imported-model.res") == OK)
	var source_dialog: EditorFileDialog
	var save_dialog: EditorFileDialog
	for dialog: Node in EditorInterface.get_base_control().find_children("*", "EditorFileDialog", true, false):
		if dialog.title == "Import Cubism Model":
			source_dialog = dialog
		elif dialog.title == "Save Imported Cubism Resource":
			save_dialog = dialog
	assert(source_dialog != null and save_dialog != null)
	source_dialog.file_selected.emit(source)
	save_dialog.file_selected.emit("res://menu-model.res")
	save_dialog.hide()
	assert(ResourceLoader.load("res://menu-model.res") is CubismModelResource)
	assert(EditorInterface.get_inspector().get_edited_object() == ResourceLoader.load("res://menu-model.res"))
	assert(save_dialog.get_option_count() == 4)
	assert(save_dialog.get_option_name(3) == "Mask quality" and save_dialog.get_option_default(3) == 1)
	save_dialog.set_option_default(0, 1)
	save_dialog.set_option_default(1, 0)
	save_dialog.set_option_default(2, 0)
	save_dialog.set_option_default(3, 2)
	source_dialog.file_selected.emit(source)
	save_dialog.file_selected.emit("res://menu-options-model.res")
	save_dialog.hide()
	var menu_model := ResourceLoader.load("res://menu-options-model.res") as CubismModelResource
	assert(menu_model != null and menu_model.motion_groups.is_empty() and menu_model.expressions.is_empty())
	assert(menu_model.import_options["validation/strict_optional_files"] == true)
	assert(menu_model.get_mask_quality() == 2)
	var model := ResourceLoader.load("res://imported-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	assert(model is CubismModelResource)
	assert(model.source_hash == FileAccess.get_sha256(source))
	assert(not model.textures.is_empty())
	for texture: Texture2D in model.textures:
		assert(texture is PortableCompressedTexture2D and texture.resource_path.begins_with("res://cubism_generated/textures/"))
	assert(not ResourceLoader.get_dependencies("res://imported-model.res").is_empty())
	print("CUBISM_EDITOR_IMPORT_PASS")
	await get_tree().process_frame
	get_tree().quit()
