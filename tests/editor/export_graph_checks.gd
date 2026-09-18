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
	assert(model.runtime_extension is GDExtension)
	assert(model.runtime_extension.resource_path == "res://addons/gd_cubism/gd_cubism.gdextension")
	var extension_dependency := false
	for dependency: String in ResourceLoader.get_dependencies("res://imported-model.res"):
		extension_dependency = extension_dependency or dependency.ends_with("res://addons/gd_cubism/gd_cubism.gdextension")
	assert(extension_dependency)
	var direct := CubismExportValidator.validate_file("res://imported-model.res")
	assert(direct.ok and direct.models == 1 and direct.raw_hashes.has(model.moc_path))
	var wrapper := Resource.new()
	wrapper.set_meta("external", model)
	assert(ResourceSaver.save(wrapper, "res://graph-external.tres") == OK)
	var checked := CubismExportValidator.validate_file("res://graph-external.tres")
	assert(checked.ok and checked.models == 0 and checked.raw_hashes.is_empty())
	wrapper = Resource.new()
	wrapper.set_meta("nested", {"items": [model.duplicate()]})
	assert(ResourceSaver.save(wrapper, "res://graph-embedded.tres") == OK)
	checked = CubismExportValidator.validate_file("res://graph-embedded.tres")
	assert(checked.ok and checked.models == 1 and checked.raw_hashes == direct.raw_hashes)
	var node := Node.new()
	node.set_meta("model", model.duplicate())
	var scene := PackedScene.new()
	assert(scene.pack(node) == OK)
	node.free()
	assert(ResourceSaver.save(scene, "res://graph-embedded.tscn") == OK)
	checked = CubismExportValidator.validate_file("res://graph-embedded.tscn")
	assert(checked.ok and checked.models == 1 and checked.raw_hashes == direct.raw_hashes)
	var broken := model.duplicate() as CubismModelResource
	broken.import_fingerprint = "stale"
	wrapper = Resource.new()
	wrapper.set_meta("model", broken)
	assert(ResourceSaver.save(wrapper, "res://graph-invalid.tres") == OK)
	checked = CubismExportValidator.validate_file("res://graph-invalid.tres")
	assert(not checked.ok and checked.raw_hashes.is_empty())
	for path: String in ["res://graph-external.tres", "res://graph-embedded.tres", "res://graph-embedded.tscn", "res://graph-invalid.tres"]:
		DirAccess.remove_absolute(path)
	print("CUBISM_EXPORT_GRAPH_PASS")
	get_tree().quit()
