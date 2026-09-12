# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func summary() -> Label:
	var panel := EditorInterface.get_inspector().find_child("CubismModelSummary", true, false)
	return panel.get_node("Summary") as Label if panel != null else null

func inspect(value: Resource) -> void:
	EditorInterface.edit_resource(value)
	await get_tree().process_frame
	await get_tree().process_frame

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var model := ResourceLoader.load("res://imported-model.res", "CubismModelResource") as CubismModelResource
	var saved := FileAccess.get_sha256("res://imported-model.res")
	await inspect(model)
	assert(summary() != null)
	assert(summary().text.contains(model.source_model_path))
	assert(summary().text.contains("Textures: " + str(model.textures.size())))
	assert(summary().text.contains("Expressions: " + str(model.expressions.size())))
	var motions := 0
	for group: Array in model.motion_groups.values():
		motions += group.size()
	assert(summary().text.contains("Motions: " + str(motions) + " in " + str(model.motion_groups.size()) + " groups"))
	var warnings := model.import_warnings
	model.import_warnings = PackedStringArray(["Missing optional expression: 表情 [b]plain text[/b]"])
	assert(summary().text.contains("表情 [b]plain text[/b]"))
	assert(summary().text.contains("Import warnings: 1"))
	model.import_warnings = warnings
	assert(not summary().text.contains("[b]plain text[/b]"))
	# Inspector switching must detach the old model's signal listener.
	var before: int = model.get_signal_connection_list("changed").size()
	for iteration in 10:
		await inspect(Resource.new())
		assert(summary() == null)
		await inspect(model)
		assert(summary() != null)
	assert(model.get_signal_connection_list("changed").size() == before)
	await inspect(CubismModelResource.new())
	assert(summary() != null and summary().text.contains("No imported source"))
	await inspect(model)
	assert(summary().text.contains(model.source_model_path))
	assert(FileAccess.get_sha256("res://imported-model.res") == saved)
	var options := model.import_options.duplicate()
	var expressions: int = model.expressions.size()
	assert(CubismModelImporter.import_model_with_options(model.source_model_path, "res://imported-model.res", {"expressions/import": false}) == OK)
	assert(model.expressions.is_empty() and summary().text.contains("Expressions: 0"))
	assert(CubismModelImporter.import_model_with_options(model.source_model_path, "res://imported-model.res", options) == OK)
	assert(summary().text.contains("Expressions: " + str(expressions)))
	var icon := load("res://addons/gd_cubism/res/icons/cubism_model_resource.svg") as Texture2D
	assert(icon != null and icon.get_width() == 16 and icon.get_height() == 16)
	print("CUBISM_MODEL_INSPECTOR_PASS")
	get_tree().quit()
