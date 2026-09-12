# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

var cases := 0
var failures: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func expect(value: bool, label: String) -> void:
	cases += 1
	if not value:
		failures.append(label)

func reject(model: CubismModelResource, label: String) -> void:
	var result := CubismExportValidator.validate_model(model)
	expect(not result.ok and not result.diagnostics.is_empty() and result.raw_files.is_empty(), label)

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var model := load("res://imported-model.res") as CubismModelResource
	var saved_hash := FileAccess.get_sha256("res://imported-model.res")
	var source_hash := FileAccess.get_sha256(model.source_model_path)
	var result := CubismExportValidator.validate_model(model)
	expect(result.ok, "current imported model: " + str(result.diagnostics))
	expect(result.raw_files.has(model.moc_path) and result.raw_files.has(model.source_model_path), "MOC and manifest included")
	var expected := PackedStringArray([model.source_model_path])
	for path: String in model.dependency_paths:
		if FileAccess.file_exists(path) and (path.ends_with(".moc3") or path.ends_with(".json")):
			expected.append(path)
	expected.sort()
	expect(result.raw_files == expected, "only declared present raw MOC and JSON sources")
	reject(null, "null model")
	reject(CubismModelResource.new(), "empty model")
	for change: Dictionary in [
		{"import_schema_version": 99}, {"import_fingerprint": ""}, {"source_hash": "changed"},
		{"dependency_fingerprints": {}}, {"dependency_paths": PackedStringArray()},
		{"source_model_path": "res://outside.txt"}, {"moc_path": "res://missing.moc3"},
		{"physics_path": "res://other.physics3.json"}, {"textures": []},
		{"expressions": []}, {"motion_groups": {}},
	]:
		var copy := model.duplicate() as CubismModelResource
		var key: String = change.keys()[0]
		copy.set(key, change[key])
		reject(copy, "reject changed " + key)
	var groups := model.motion_groups.duplicate(true)
	var group: String = groups.keys()[0]
	var motion := groups[group][0].duplicate() as CubismMotionDescriptor
	motion.source_path = "res://unrelated.motion3.json"
	groups[group][0] = motion
	var changed := model.duplicate() as CubismModelResource
	changed.motion_groups = groups
	reject(changed, "undeclared motion reference")
	var sound_tested := false
	for name: String in model.motion_groups:
		for index in model.motion_groups[name].size():
			var original: CubismMotionDescriptor = model.motion_groups[name][index]
			if original.sound == null:
				continue
			groups = model.motion_groups.duplicate(true)
			motion = original.duplicate() as CubismMotionDescriptor
			motion.sound = null
			groups[name][index] = motion
			changed = model.duplicate() as CubismModelResource
			changed.motion_groups = groups
			reject(changed, "missing real audio resource edge")
			sound_tested = true
			break
		if sound_tested:
			break
	expect(sound_tested, "audio edge fixture exercised")
	var source := FileAccess.get_file_as_bytes(model.source_model_path)
	var file := FileAccess.open(model.source_model_path, FileAccess.WRITE)
	file.store_buffer(source + PackedByteArray([10]))
	file.close()
	reject(model, "stale manifest with valid JSON")
	file = FileAccess.open(model.source_model_path, FileAccess.WRITE)
	file.store_buffer(source)
	file.close()
	var raw_path: String = model.motion_groups[group][0].source_path
	var raw_bytes := FileAccess.get_file_as_bytes(raw_path)
	file = FileAccess.open(raw_path, FileAccess.WRITE)
	file.store_buffer(raw_bytes + PackedByteArray([10]))
	file.close()
	reject(model, "stale motion source with valid JSON")
	file = FileAccess.open(raw_path, FileAccess.WRITE)
	file.store_buffer(raw_bytes)
	file.close()
	var moc_backup := model.moc_path + ".export-check-backup"
	expect(DirAccess.rename_absolute(model.moc_path, moc_backup) == OK, "temporarily remove MOC")
	reject(model, "missing required MOC with cached imported resource")
	expect(DirAccess.rename_absolute(moc_backup, model.moc_path) == OK, "restore MOC")
	var texture_path: String = model.textures[0].resource_path
	var backup := texture_path + ".export-check-backup"
	expect(DirAccess.rename_absolute(texture_path, backup) == OK, "temporarily remove derived texture")
	reject(model, "missing derived texture even with cached object")
	expect(DirAccess.rename_absolute(backup, texture_path) == OK, "restore derived texture")
	var variant := model.source_model_path.get_base_dir().path_join("export-optional.model3.json")
	var manifest: Dictionary = JSON.parse_string(source.get_string_from_utf8())
	var first_group: String = manifest.FileReferences.Motions.keys()[0]
	manifest.FileReferences.Motions[first_group][0].Sound = "export-absent.wav"
	file = FileAccess.open(variant, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	expect(CubismModelImporter.import_model(variant, "res://export-optional.res") == OK, "import optional missing audio")
	var optional := load("res://export-optional.res") as CubismModelResource
	result = CubismExportValidator.validate_model(optional)
	expect(result.ok, "missing optional audio retains lenient policy: " + str(result.diagnostics))
	DirAccess.remove_absolute("res://export-optional.res")
	DirAccess.remove_absolute(variant)
	expect(CubismExportValidator.validate_model(model).ok, "restored sources valid again")
	expect(FileAccess.get_sha256("res://imported-model.res") == saved_hash and FileAccess.get_sha256(model.source_model_path) == source_hash, "validation never saves or rewrites imported source")
	for failure: String in failures:
		printerr("EXPORT_VALIDATOR_FAIL: ", failure)
	print("CUBISM_EXPORT_VALIDATOR_CHECKS cases=", cases, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_EXPORT_VALIDATOR_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
