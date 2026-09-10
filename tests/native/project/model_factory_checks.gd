# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
var temporary_path := ""

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func build_variant(value: Dictionary, strict: bool = false) -> Dictionary:
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	var result := CubismModelFactory.build(temporary_path, strict)
	DirAccess.remove_absolute(temporary_path)
	return result

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var path: String = fixture.model
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	temporary_path = path.get_base_dir().path_join("factory-test.model3.json")
	var result := CubismModelFactory.build(path)
	expect(result.ok and result.model is CubismModelResource, "real model assembled: " + str(result.diagnostics))
	if result.ok:
		var model: CubismModelResource = result.model
		expect(model.source_hash == FileAccess.get_sha256(path), "source fingerprint")
		expect(model.moc_version > 0 and model.canvas_size.x > 0 and model.canvas_size.y > 0 and model.pixels_per_unit > 0, "MOC metadata")
		expect(model.textures.size() == original.FileReferences.Textures.size(), "ordered texture edges")
		expect(model.expressions.size() == original.FileReferences.get("Expressions", []).size(), "expression descriptors")
		expect(model.motion_groups.size() == original.FileReferences.get("Motions", {}).size(), "motion groups")
		expect(model.dependency_fingerprints.has(model.moc_path), "MOC fingerprint")
		expect(ResourceSaver.save(model, "res://factory-model.res") == OK, "save assembled model")
		var restored := ResourceLoader.load("res://factory-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
		expect(restored is CubismModelResource and restored.source_hash == model.source_hash, "roundtrip assembled model")
	var copy := original.duplicate(true)
	copy.FileReferences.Physics = "missing.physics3.json"
	result = build_variant(copy)
	expect(result.ok and result.warnings.size() == 1 and result.model.physics_path == "", "lenient missing optional file")
	result = build_variant(copy, true)
	expect(not result.ok and result.model == null, "strict missing optional file")
	copy = original.duplicate(true)
	copy.FileReferences.Moc = "missing.moc3"
	result = build_variant(copy)
	expect(not result.ok and result.model == null, "missing required MOC")
	copy = original.duplicate(true)
	copy.FileReferences.Textures[0] = "missing.png"
	result = build_variant(copy)
	expect(not result.ok and result.model == null, "missing required texture")
	copy = original.duplicate(true)
	copy.FileReferences.Textures = []
	result = build_variant(copy)
	expect(not result.ok and result.model == null, "MOC texture index mismatch")
	copy = original.duplicate(true)
	copy.FileReferences.Textures[0] = "danger.gd"
	result = build_variant(copy)
	expect(not result.ok and result.model == null, "script-bearing texture suffix rejected")
	var bomb_path := path.get_base_dir().path_join("factory-bomb.png")
	var bomb := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 255, 255, 255, 255, 255, 255, 255, 255, 8, 6, 0, 0, 0, 0, 0, 0, 0])
	var bomb_file := FileAccess.open(bomb_path, FileAccess.WRITE)
	bomb_file.store_buffer(bomb)
	bomb_file.close()
	copy = original.duplicate(true)
	copy.FileReferences.Textures[0] = "factory-bomb.png"
	result = build_variant(copy)
	expect(not result.ok and result.model == null, "oversized PNG rejected before texture decoding")
	DirAccess.remove_absolute(bomb_path)
	if not original.FileReferences.get("Motions", {}).is_empty():
		copy = original.duplicate(true)
		var group: String = copy.FileReferences.Motions.keys()[0]
		copy.FileReferences.Motions[group][0].FadeInTime = 0.125
		copy.FileReferences.Motions[group][0].FadeOutTime = 0.25
		var depth := path.get_base_dir().trim_prefix("res://").split("/", false).size()
		copy.FileReferences.Motions[group][0].Sound = "../".repeat(depth) + "synthetic-audio.wav"
		result = build_variant(copy)
		expect(result.ok, "motion overrides and audio accepted: " + str(result.diagnostics))
		if result.ok:
			var motion: CubismMotionDescriptor = result.model.motion_groups[group][0]
			expect(motion.fade_in_seconds == 0.125 and motion.fade_out_seconds == 0.25, "manifest fades override motion defaults")
			expect(motion.sound is AudioStream and motion.sound_path == "res://synthetic-audio.wav", "audio resource edge")
	for failure: String in failures:
		printerr("MODEL_FACTORY_FAIL: ", failure)
	print("CUBISM_FACTORY_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_MODEL_FACTORY_PASS")
	quit(0 if failures.is_empty() else 1)
