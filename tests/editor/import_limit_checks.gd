# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

const SETTING := "cubism/import/maximum_file_count"
var tracker: Node
var failures: Array[String] = []
var cases := 0

func _enter_tree() -> void:
	_run.call_deferred()

func expect(value: bool, label: String) -> void:
	cases += 1
	if not value:
		failures.append(label)

func status() -> Dictionary:
	for item: Dictionary in tracker.get_status().models:
		if item.resource == "res://limit-model.res":
			return item
	return {}

func settle() -> void:
	tracker.request_scan()
	for frame in 2000:
		await get_tree().process_frame
		if not tracker.get_status().busy:
			return
	failures.append("file-limit dependency scan timed out")

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	tracker = get_tree().root.find_child("CubismDependencies", true, false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var original_limit: Variant = ProjectSettings.get_setting(SETTING)
	expect(original_limit == 1024, "project limit default")
	for invalid: Variant in [0, -1, 4097, 1.5, "12", true]:
		ProjectSettings.set_setting(SETTING, invalid)
		var result := CubismModelFactory.build(source)
		expect(not result.ok and result.model == null and result.diagnostics[0].path.ends_with(SETTING), "reject invalid project file limit")
	ProjectSettings.set_setting(SETTING, 4096)
	var full := CubismModelFactory.build(source)
	expect(full.ok, "hard maximum accepted")
	var count: int = full.model.dependency_paths.size() + 1
	ProjectSettings.set_setting(SETTING, count)
	expect(CubismModelFactory.build(source).ok, "exact unique file count includes manifest")
	ProjectSettings.set_setting(SETTING, count - 1)
	var rejected := CubismModelFactory.build(source)
	expect(not rejected.ok and rejected.model == null and str(rejected.diagnostics).contains(str(count)), "one below count rejected with required count")
	ProjectSettings.set_setting(SETTING, 4096)
	var options := {"motions/import_manifest_motions": false, "expressions/import": false}
	var reduced := CubismModelFactory.build_with_options(source, options)
	var reduced_count: int = reduced.model.dependency_paths.size() + 1
	expect(reduced_count < count, "disabled catalogs reduce file count")
	ProjectSettings.set_setting(SETTING, reduced_count)
	expect(CubismModelFactory.build_with_options(source, options).ok, "disabled catalog references excluded from budget")
	expect(not CubismModelFactory.build(source).ok, "enabled catalog references consume budget")
	# Repeated references consume one file slot, while retaining ordered descriptors.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var group: String = manifest.FileReferences.Motions.keys()[0]
	manifest.FileReferences.Motions[group].append(manifest.FileReferences.Motions[group][0].duplicate(true))
	var variant := source.get_base_dir().path_join("limit.model3.json")
	var file := FileAccess.open(variant, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	ProjectSettings.set_setting(SETTING, count)
	var repeated := CubismModelFactory.build(variant)
	expect(repeated.ok and repeated.model.dependency_paths.size() + 1 == count, "duplicate motion file uses one slot")
	DirAccess.remove_absolute(variant)
	ProjectSettings.set_setting(SETTING, original_limit)
	expect(CubismModelImporter.import_model(source, "res://limit-model.res") == OK, "save bounded model")
	EditorInterface.get_resource_filesystem().update_file("res://limit-model.res")
	await settle()
	var saved_hash := FileAccess.get_sha256("res://limit-model.res")
	var saved_model := ResourceLoader.load("res://limit-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	var saved_fingerprint: String = saved_model.import_fingerprint
	print("EXPECTED_IMPORT_LIMIT_FAILURE_BEGIN")
	ProjectSettings.set_setting(SETTING, count - 1)
	await settle()
	expect(status().get("status") == "failed", "lower project limit invalidates existing import")
	expect(FileAccess.get_sha256("res://limit-model.res") == saved_hash, "failed budget check preserves saved model")
	var attempts: int = status().get("attempts", -1)
	await settle()
	expect(status().get("attempts") == attempts, "unchanged rejected budget is not retried")
	ProjectSettings.set_setting(SETTING, count)
	await settle()
	print("EXPECTED_IMPORT_LIMIT_FAILURE_END")
	expect(status().get("status") == "current", "raising limit recovers without source changes")
	var updated := ResourceLoader.load("res://limit-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	expect(updated.import_fingerprint != saved_fingerprint and updated.source_hash == saved_model.source_hash, "project limit participates in fingerprint without source change")
	ProjectSettings.set_setting(SETTING, original_limit)
	await settle()
	DirAccess.remove_absolute("res://limit-model.res")
	EditorInterface.get_resource_filesystem().update_file("res://limit-model.res")
	for failure: String in failures:
		printerr("IMPORT_LIMIT_FAIL: ", failure)
	print("CUBISM_IMPORT_LIMIT cases=", cases, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_IMPORT_LIMIT_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
