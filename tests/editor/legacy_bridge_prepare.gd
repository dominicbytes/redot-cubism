# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

var checks: Array[String] = []

class ForeignImporter extends EditorImportPlugin:
	func _get_importer_name() -> String: return "cubism.test.foreign"
	func _get_visible_name() -> String: return "Foreign importer test"
	func _get_recognized_extensions() -> PackedStringArray: return PackedStringArray(["foreign.model3.json"])
	func _get_save_extension() -> String: return "res"
	func _get_resource_type() -> String: return "Resource"
	func _get_priority() -> float: return 10.0
	func _get_preset_count() -> int: return 0
	func _get_import_options(_path: String, _preset: int) -> Array[Dictionary]: return []
	func _import(_source: String, destination: String, _options: Dictionary, _variants: Array[String], _files: Array[String]) -> Error:
		return ResourceSaver.save(Resource.new(), destination + ".res")

func _enter_tree() -> void:
	_run.call_deferred()

func _menu(node: Node) -> PopupMenu:
	if node is PopupMenu:
		for index in node.item_count:
			if node.get_item_text(index) == "Prepare Legacy Cubism Model":
				return node
	for child: Node in node.get_children():
		var found := _menu(child)
		if found != null:
			return found
	return null

func _dialog(node: Node) -> EditorFileDialog:
	if node is EditorFileDialog and node.title == "Prepare Legacy Cubism Model":
		return node
	for child: Node in node.get_children():
		var found := _dialog(child)
		if found != null:
			return found
	return null

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://bridge-fixture.json"))
	var sources: Array = fixture.sources
	for source: String in sources:
		_write(source, FileAccess.get_file_as_string(source + ".fixture"))
	assert(not FileAccess.file_exists(str(sources[0]) + ".import"))
	var raw := GDCubismUserModel.new()
	raw.assets = sources[0]
	assert(raw.is_initialized() and raw.model == null and raw.get("_legacy_model") == null)
	raw.free()
	checks.append("unprepared raw-path fallback")
	assert(CubismModelImporter.import_source("res://ordinary.json") == ERR_FILE_UNRECOGNIZED)
	assert(CubismModelImporter.import_source("res://../outside.model3.json") == ERR_FILE_BAD_PATH)
	checks.append("invalid source rejection")
	var foreign_source := str(sources[0]).get_base_dir().path_join("foreign.model3.json")
	_write(foreign_source, FileAccess.get_file_as_string(sources[0]))
	var foreign_importer := ForeignImporter.new()
	add_import_plugin(foreign_importer)
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.update_file(foreign_source)
	filesystem.reimport_files(PackedStringArray([foreign_source]))
	var foreign_hash := FileAccess.get_sha256(foreign_source + ".import")
	assert(CubismModelImporter.import_source(foreign_source) == ERR_ALREADY_IN_USE)
	assert(FileAccess.get_sha256(foreign_source + ".import") == foreign_hash)
	remove_import_plugin(foreign_importer)
	# Remove this private test's source through the editor, which owns cleanup of
	# its generated import metadata. It must not outlive the temporary importer.
	assert(DirAccess.remove_absolute(foreign_source) == OK)
	filesystem.update_file(foreign_source)
	checks.append("foreign importer ownership preserved")
	var menu := _menu(get_tree().root)
	assert(menu != null)
	for index in menu.item_count:
		if menu.get_item_text(index) == "Prepare Legacy Cubism Model":
			menu.index_pressed.emit(index)
			break
	var dialog := _dialog(get_tree().root)
	assert(dialog != null and dialog.visible)
	dialog.hide()
	dialog.file_selected.emit(sources[0])
	assert(FileAccess.file_exists(str(sources[0]) + ".import"))
	checks.append("native preparation menu")
	assert(CubismModelImporter.import_source(sources[1]) == OK)
	var paths: Array[String] = []
	for index in sources.size():
		var source: String = sources[index]
		var imported := ResourceLoader.load(source, "CubismModelResource") as CubismModelResource
		assert(imported != null and imported.resource_path == source)
		assert(CubismExportValidator.validate_model(imported).ok)
		var path := "res://bridge-" + str(index) + ".tscn"
		_write(path, '[gd_scene format=3]\n[node name="Legacy" type="GDCubismUserModel"]\nassets = ' + JSON.stringify(source) + '\n')
		var legacy := (load(path) as PackedScene).instantiate() as GDCubismUserModel
		assert(legacy.assets == source and legacy.model == null and legacy.is_initialized())
		assert(legacy.get("_legacy_model") == imported)
		var packed := PackedScene.new()
		assert(packed.pack(legacy) == OK)
		assert(packed.get_state().get_node_count() == 1, "Generated renderer children must not be saved")
		legacy.free()
		assert(ResourceSaver.save(packed, path) == OK)
		var edge := false
		for dependency: String in ResourceLoader.get_dependencies(path):
			edge = edge or dependency.ends_with(source)
		assert(edge, "Saved legacy scenes must retain an imported-resource edge")
		assert(CubismExportValidator.validate_file(path).ok)
		paths.append(path)
		checks.append("saved bridge " + str(index))
	var first := (ResourceLoader.load(paths[0], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as GDCubismUserModel
	assert(first.get("_legacy_model") != null and first.assets == sources[0])
	first.assets = sources[1]
	assert(first.get("_legacy_model").source_model_path == sources[1] and first.model == null)
	first.model = load(sources[0])
	assert(first.assets.is_empty() and first.get("_legacy_model") == null and first.model != null)
	first.assets = ""
	assert(not first.is_initialized() and first.model == null and first.get("_legacy_model") == null)
	first.free()
	checks.append("reload, source switch, explicit model and clear")
	_write("res://bridge-mismatched.tscn", '[gd_scene load_steps=2 format=3]\n[ext_resource type="CubismModelResource" path=' + JSON.stringify(sources[0]) + ' id="1"]\n[node name="Legacy" type="GDCubismUserModel"]\nassets = ' + JSON.stringify(sources[1]) + '\n_legacy_model = ExtResource("1")\n')
	assert(not CubismExportValidator.validate_file("res://bridge-mismatched.tscn").ok)
	checks.append("mismatched bridge rejected")
	var runtime_sources := sources.duplicate()
	_write("res://bridge-base.tscn", '[gd_scene format=3]\n[node name="Base" type="GDCubismUserModel"]\n')
	for nested: bool in [false, true]:
		var path := "res://bridge-nested.tscn" if nested else "res://bridge-inherited.tscn"
		var text := '[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://bridge-base.tscn" id="1"]\n'
		text += '[node name="Root" type="Node"]\n[node name="Legacy" parent="." instance=ExtResource("1")]\n' if nested else '[node name="Legacy" instance=ExtResource("1")]\n'
		text += "assets = " + JSON.stringify(sources[0]) + "\n"
		_write(path, text)
		var tree := (load(path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var packed := PackedScene.new()
		assert(packed.pack(tree) == OK)
		tree.free()
		assert(ResourceSaver.save(packed, path) == OK)
		assert(CubismExportValidator.validate_file(path).ok)
		paths.append(path)
		runtime_sources.append(sources[0])
		checks.append("saved nested bridge" if nested else "saved inherited bridge")
	_write("res://bridge-expected.json", JSON.stringify({"sources": runtime_sources, "scenes": paths, "checks": checks, "layout_x": [0.0, 0.5, 0.0, 0.0]}, "\t"))
	# Adding/removing the test importer schedules an editor filesystem scan.
	await get_tree().create_timer(0.5).timeout
	while filesystem.is_scanning():
		await get_tree().process_frame
	print("CUBISM_LEGACY_BRIDGE_PREPARED checks=", checks.size())
	get_tree().quit()
