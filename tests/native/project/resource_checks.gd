# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _initialize() -> void:
	var model := CubismModelResource.new()
	expect(model.import_schema_version == 1, "schema default")
	expect(model.textures.is_empty() and model.motion_groups.is_empty(), "empty resource defaults")
	var values := {
		"source_model_path": "res://Models/模型.model3.json",
		"source_hash": "test-source-hash",
		"moc_path": "res://Models/模型.moc3",
		"moc_version": 6,
		"texture_paths": PackedStringArray(["res://tex/B.png", "res://tex/A.png"]),
		"layout": {"CenterX": 0.25, "Width": 2.0},
		"dependency_fingerprints": {"res://missing.pose3.json": "missing"},
		"motion_groups": {"Idle": [{"id": "Idle/0", "source_path": "res://idle.motion3.json"}]},
		"expressions": [{"id": "笑顔", "source_path": "res://smile.exp3.json"}],
		"physics_path": "res://p.physics3.json",
		"pose_path": "res://p.pose3.json",
		"user_data_path": "res://p.userdata3.json",
		"display_info_path": "res://p.cdi3.json",
		"eye_blink_parameter_ids": PackedStringArray(["ParamEyeLOpen", "ParamEyeROpen"]),
		"lip_sync_parameter_ids": PackedStringArray(["ParamMouthOpenY"]),
		"canvas_size": Vector2(2048, 4096),
		"canvas_origin": Vector2(1024, 2048),
		"pixels_per_unit": 1000.0,
		"dependency_paths": PackedStringArray(["res://a.moc3", "res://b.png"]),
		"import_warnings": PackedStringArray(["Optional pose is missing."]),
		"import_schema_version": 1,
		"sdk_compatibility": {"core": "6.0.1", "moc": 6},
		"import_options": {"validation/strict_optional_files": false},
		"metadata": {"Unknown": {"Author": "作者"}},
	}
	for field: String in values:
		model.set(field, values[field])
	var hits: Array[Dictionary] = [{"Id": "Head", "Name": "頭"}]
	model.hit_areas = hits
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest := CubismManifestParser.parse_manifest(FileAccess.get_file_as_string(fixture.model), fixture.model)
	var texture_path: String = manifest.manifest.FileReferences.Textures[0]
	var texture := load(texture_path) as Texture2D
	expect(texture != null, "load imported project texture")
	var image := texture.get_image()
	var textures: Array[Texture2D] = [texture, texture]
	model.textures = textures
	expect(ResourceSaver.save(model, "user://cubism-test-model.res") == OK, "save model resource")
	var first_bytes := FileAccess.get_file_as_bytes("user://cubism-test-model.res")
	expect(ResourceSaver.save(model, "user://cubism-test-model.res") == OK and FileAccess.get_file_as_bytes("user://cubism-test-model.res") == first_bytes, "repeat save is deterministic")
	var restored := ResourceLoader.load("user://cubism-test-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	expect(restored != null and restored != model, "deserialize fresh native model resource")
	if restored:
		for field: String in values:
			expect(restored.get(field) == values[field], "round trip " + field)
		expect(restored.hit_areas == hits, "typed hit areas round trip")
		expect(restored.textures.size() == 2, "texture index count preserved")
		if restored.textures.size() == 2:
			expect(restored.textures[0] == restored.textures[1], "shared texture identity preserved")
			expect(restored.textures[0].resource_path == texture_path, "real external texture dependency preserved")
			expect(restored.textures[0].get_image().get_data() == image.get_data(), "texture pixel payload preserved")
	var dependencies := ResourceLoader.get_dependencies("user://cubism-test-model.res")
	expect(dependencies.size() == 1 and dependencies[0].contains(texture_path), "engine sees texture dependency")
	for failure: String in failures:
		printerr("RESOURCE_CHECK_FAIL: ", failure)
	print("CUBISM_RESOURCE_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_RESOURCE_PASS")
	quit(0 if failures.is_empty() else 1)
