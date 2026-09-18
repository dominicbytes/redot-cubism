# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var model := load("res://imported-model.res") as CubismModelResource
	var source := model.source_model_path
	var other := source.get_base_dir().path_join("matrix-unselected.model3.json")
	var file := FileAccess.open(other, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(source))
	file.close()
	assert(CubismModelImporter.import_model(other, "res://matrix-unselected.res") == OK)
	for embedded: bool in [false, true]:
		var node := Node.new()
		node.name = "ExportSelection"
		node.set_meta("model", model.duplicate() if embedded else model)
		node.set_meta("checks", load("res://export_selection_checks.gd"))
		var scene := PackedScene.new()
		assert(scene.pack(node) == OK)
		node.free()
		assert(ResourceSaver.save(scene, "res://matrix-embedded.tscn" if embedded else "res://matrix-external.tscn") == OK)
	file = FileAccess.open("res://selection-expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"raw": CubismExportValidator.validate_file("res://imported-model.res").raw_hashes, "unselected": other}))
	file.close()
	print("CUBISM_EXPORT_SELECTION_PREPARED")
	get_tree().quit()
