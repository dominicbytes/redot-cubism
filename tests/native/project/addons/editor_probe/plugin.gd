# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	if not ClassDB.class_exists("GDCubismPlugin"):
		push_error("CUBISM_NATIVE_FAIL: editor plugin missing")
		return
	print("CUBISM_NATIVE_EDITOR_REGISTERED")
	_probe.call_deferred()

func _probe() -> void:
	# Imported model references resolve audio UIDs after filesystem discovery.
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.model))
	for texture: String in manifest.FileReferences.Textures:
		if not ResourceLoader.exists(fixture.model.get_base_dir().path_join(texture), "Texture2D"):
			# Discovery may still have pending texture imports. The harness
			# requires the creation/save check on the subsequent restart.
			print("CUBISM_NATIVE_EDITOR_WAITING_IMPORT")
			return
	var prepare_export := OS.get_cmdline_user_args().has("--cubism-native-export-prepare")
	if prepare_export:
		# Factory tests create resources without import provenance. Export must
		# use the supported importer and the imported legacy source bridge.
		var source_error := CubismModelImporter.import_source(fixture.model)
		var resource_error := CubismModelImporter.import_model(fixture.model, "res://factory-model.res")
		if source_error != OK or resource_error != OK:
			push_error("CUBISM_NATIVE_FAIL: prepare imported export resources: source=%d resource=%d" % [source_error, resource_error])
			get_tree().quit(1)
			return
		var unicode_manifest := manifest.duplicate(true)
		unicode_manifest.FileReferences.Moc = "模型_😀.moc3"
		unicode_manifest.FileReferences.Motions = {"待機_😀": manifest.FileReferences.Motions[fixture.motion_group]}
		var unicode_source: String = fixture.model.get_base_dir().path_join("模型_😀.model3.json")
		var output := FileAccess.open(unicode_source, FileAccess.WRITE)
		output.store_string(JSON.stringify(unicode_manifest))
		output.close()
		if CubismModelImporter.import_model(unicode_source, "res://unicode-resource.res") != OK:
			push_error("CUBISM_NATIVE_FAIL: import Unicode export resource")
			get_tree().quit(1)
			return
	var scene := Node2D.new()
	scene.name = "CubismEditorProbe"
	var model := GDCubismUserModel.new()
	model.name = "Model"
	scene.add_child(model)
	model.owner = scene
	model.assets = fixture.model
	var packed := PackedScene.new()
	if not model.is_initialized() or packed.pack(scene) != OK or ResourceSaver.save(packed, "res://editor-probe.tscn") != OK:
		push_error("CUBISM_NATIVE_FAIL: editor model creation/save failed: " + str(model.get_last_error()))
		scene.free()
		return
	scene.free()
	if FileAccess.get_file_as_string("res://editor-probe.tscn").count("[node ") != 2:
		push_error("CUBISM_NATIVE_FAIL: generated runtime nodes were serialized")
		return
	print("CUBISM_NATIVE_EDITOR_PASS")
	if prepare_export:
		print("CUBISM_NATIVE_EXPORT_PREPARED")
		get_tree().quit()

func _exit_tree() -> void:
	print("CUBISM_NATIVE_EDITOR_EXIT")
