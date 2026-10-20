# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

const LIMIT := 4096
var cases := 0
var failures: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func expect(value: bool, label: String) -> void:
	cases += 1
	if not value:
		failures.append(label)

func write_manifest(path: String, manifest: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	manifest.HitAreas = []
	manifest.Layout = {}
	manifest.Groups = [{"Target": "Parameter", "Name": "EyeBlink", "Ids": []}, {"Target": "Parameter", "Name": "LipSync", "Ids": []}]
	for index in LIMIT:
		manifest.HitAreas.append({"Id": "Hit" + str(index), "Name": "Area" + str(index)})
		manifest.Layout["Entry" + str(index)] = 0.0
		manifest.Groups[0].Ids.append("Blink" + str(index))
		manifest.Groups[1].Ids.append("Lip" + str(index))
	var variant := source.get_base_dir().path_join("metadata-limit.model3.json")
	var output := "res://metadata-limit.res"
	write_manifest(variant, manifest)
	expect(CubismModelImporter.import_model(variant, output) == OK, "import exact metadata boundaries")
	var model := ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	expect(model != null, "reload boundary resource from disk")
	if model != null:
		expect(model.hit_areas.size() == LIMIT and model.layout.size() == LIMIT, "hit areas and layout preserved")
		expect(model.eye_blink_parameter_ids.size() == LIMIT and model.lip_sync_parameter_ids.size() == LIMIT, "parameter groups preserved")
		var validation := CubismExportValidator.validate_model(model)
		expect(validation.ok, "export adapter accepts exact boundaries: " + str(validation.diagnostics))
		var node := GDCubismUserModel.new()
		node.playback_process_mode = GDCubismUserModel.MANUAL
		add_child(node)
		node.model = model
		expect(node.is_initialized(), "runtime initializes imported boundary resource")
		node.free()
	var saved_hash := FileAccess.get_sha256(output)
	for field: String in ["HitAreas", "Layout", "EyeBlink", "LipSync"]:
		var oversized := manifest.duplicate(true)
		var diagnostic := field
		if field == "HitAreas":
			oversized.HitAreas.append({"Id": "Overflow", "Name": "Overflow"})
		elif field == "Layout":
			oversized.Layout.Overflow = 0.0
		else:
			var index := 0 if field == "EyeBlink" else 1
			oversized.Groups[index].Ids.append("Overflow")
			diagnostic = "Groups[" + str(index) + "].Ids"
		write_manifest(variant, oversized)
		var parsed := CubismManifestParser.parse_manifest(JSON.stringify(oversized), variant)
		expect(not parsed.ok and parsed.manifest.is_empty(), "parser rejects oversized " + field)
		var result := CubismModelFactory.build(variant)
		expect(not result.ok and result.model == null, "factory rejects oversized " + field)
		var field_found := false
		for item: Dictionary in result.diagnostics:
			if item.path.ends_with(diagnostic) and item.message.contains(str(LIMIT)):
				field_found = true
		expect(field_found, "field diagnostic for oversized " + field)
		print("EXPECTED_METADATA_LIMIT_FAILURE_BEGIN")
		expect(CubismModelImporter.import_model(variant, output) == ERR_PARSE_ERROR, "import rejects oversized " + field)
		print("EXPECTED_METADATA_LIMIT_FAILURE_END")
		expect(FileAccess.get_sha256(output) == saved_hash, "failed import preserves saved " + field)
	DirAccess.remove_absolute(variant)
	DirAccess.remove_absolute(output)
	for failure: String in failures:
		printerr("METADATA_LIMIT_FAIL: ", failure)
	print("CUBISM_METADATA_LIMIT cases=", cases, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_METADATA_LIMIT_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
