# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

var tracker: Node
var cases := 0
var failures: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func expect(value: bool, label: String) -> void:
	cases += 1
	if not value:
		failures.append(label)

func settle() -> void:
	tracker.request_scan()
	for frame in 2000:
		await get_tree().process_frame
		if not tracker.get_status().busy:
			return
	failures.append("option dependency scan timed out")

func status() -> Dictionary:
	for item: Dictionary in tracker.get_status().models:
		if item.resource == "res://options-model.res":
			return item
	return {}

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	tracker = get_tree().root.find_child("CubismDependencies", true, false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var output := "res://options-model.res"
	var variant := source.get_base_dir().path_join("options.model3.json")
	var options := {"motions/import_manifest_motions": false, "expressions/import": false, "validation/strict_optional_files": true}
	options["rendering/mask_quality"] = 2
	for key: Variant in ["rendering/mask_quality", &"rendering/mask_quality"]:
		for quality: int in [0, 1, 2]:
			var result := CubismModelFactory.build_with_options(source, {key: quality})
			expect(result.ok and result.model.get_mask_quality() == quality, "accept String and StringName quality keys")
	for invalid: Variant in [false, true, 1.0, "medium", -1, 3, 9223372036854775807, [], null]:
		var result := CubismModelFactory.build_with_options(source, {"rendering/mask_quality": invalid})
		expect(not result.ok and result.model == null and result.diagnostics[0].path == "rendering/mask_quality", "reject invalid mask quality")
	for key: Variant in ["rendering/premultiplied_alpha", &"rendering/premultiplied_alpha"]:
		for enabled: bool in [false, true]:
			var result := CubismModelFactory.build_with_options(source, {key: enabled})
			expect(result.ok and result.model.get_premultiplied_alpha() == enabled, "accept String and StringName alpha keys")
	for key: String in ["motions/import_manifest_motions", "expressions/import", "validation/strict_optional_files", "rendering/premultiplied_alpha"]:
		for invalid: Variant in [0, 1, "false", [], null]:
			var result := CubismModelFactory.build_with_options(source, {key: invalid})
			expect(not result.ok and result.model == null and result.diagnostics[0].path == key, "reject nonboolean " + key)
	for unsupported: Dictionary in [{"motions/convert_to_redot_animation": true}, {&"motions/convert_to_redot_animation": true}, {"expressions/improt": false}]:
		var result := CubismModelFactory.build_with_options(source, unsupported)
		expect(not result.ok and result.model == null, "reject unavailable option")
	for invalid_key: Variant in [42, true]:
		var invalid_options := {}
		invalid_options[invalid_key] = true
		var result := CubismModelFactory.build_with_options(source, invalid_options)
		expect(not result.ok and result.model == null and result.diagnostics.size() == 1, "reject nontext option key")
		if result.diagnostics.size() == 1:
			expect(typeof(result.diagnostics[0].path) == TYPE_STRING and result.diagnostics[0].path == "$" and result.diagnostics[0].message == "Expected a String or StringName import option key.", "nontext key uses textual diagnostic")
	var long_name := "x".repeat(8192)
	for long_key: Variant in [long_name, StringName(long_name)]:
		var invalid_options := {}
		invalid_options[long_key] = true
		var result := CubismModelFactory.build_with_options(source, invalid_options)
		expect(not result.ok and result.model == null and result.diagnostics.size() == 1, "reject long unknown option key")
		if result.diagnostics.size() == 1:
			expect(typeof(result.diagnostics[0].path) == TYPE_STRING and result.diagnostics[0].path.length() <= 4096, "bound long option diagnostic path")
	var defaults := CubismModelFactory.build_with_options(source, {})
	expect(defaults.ok and defaults.model.get_mask_quality() == 1, "default imported medium mask quality")
	expect(defaults.ok and not defaults.model.get_premultiplied_alpha(), "default straight alpha")
	expect(defaults.ok and not defaults.model.motion_groups.is_empty() and not defaults.model.expressions.is_empty(), "default catalogs preserved")
	var expressions_only := CubismModelFactory.build_with_options(source, {"motions/import_manifest_motions": false})
	expect(expressions_only.ok and expressions_only.model.motion_groups.is_empty() and not expressions_only.model.expressions.is_empty(), "disable only motions")
	var motions_only := CubismModelFactory.build_with_options(source, {"expressions/import": false})
	expect(motions_only.ok and not motions_only.model.motion_groups.is_empty() and motions_only.model.expressions.is_empty(), "disable only expressions")
	var manifest := original.duplicate(true)
	manifest.FileReferences.Motions = {"Missing": [{"File": "missing.motion3.json", "Sound": "missing.wav"}]}
	manifest.FileReferences.Expressions = [{"Name": "Missing", "File": "missing.exp3.json"}]
	write_json(variant, manifest)
	var unsafe := manifest.duplicate(true)
	unsafe.FileReferences.Expressions[0].File = "../../outside.exp3.json"
	write_json(variant, unsafe)
	expect(not CubismModelFactory.build_with_options(variant, options).ok, "disabled category still validates manifest path safety")
	write_json(variant, manifest)
	expect(CubismModelImporter.import_model_with_options(variant, output, options) == OK, "disabled catalogs skip missing content even in strict mode")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	var model := ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	expect(model != null, "options result saved")
	if model != null:
		expect(model.get_mask_quality() == 2, "high mask quality persisted")
		expect(model.motion_groups.is_empty() and model.expressions.is_empty(), "disabled catalogs absent")
		expect(model.import_options.get("motions/import_manifest_motions") == false and model.import_options.get("expressions/import") == false, "options persisted")
		for path: String in model.dependency_paths:
			expect(not path.ends_with(".motion3.json") and not path.ends_with(".exp3.json") and not path.ends_with("missing.wav"), "disabled dependency omitted")
		expect(model.import_warnings.is_empty(), "disabled missing sources do not warn")
		var node := GDCubismUserModel.new()
		node.playback_process_mode = GDCubismUserModel.MANUAL
		add_child(node)
		node.model = model
		expect(node.is_initialized(), "runtime loads model with disabled catalogs")
		if node.is_initialized():
			expect(node.get_motions().is_empty() and node.get_expressions().is_empty(), "runtime respects disabled catalogs")
		node.free()
	var before: Dictionary = status()
	expect(before.get("status") == "current", "option result indexed")
	await settle()
	expect(status().get("attempts") == before.get("attempts"), "filtered dependencies settle without repeated imports")
	manifest.Layout = {"x": 0.375}
	write_json(variant, manifest)
	await settle()
	model = ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	expect(model.layout.get("x") == 0.375 and model.motion_groups.is_empty() and model.expressions.is_empty(), "reimport retains options")
	expect(model.get_mask_quality() == 2, "source reimport retains high mask quality")
	var previous_fingerprint: String = model.import_fingerprint
	model.import_options["rendering/mask_quality"] = 0
	expect(ResourceSaver.save(model, output) == OK, "save low mask quality option")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	model = ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	expect(model.get_mask_quality() == 0 and model.import_fingerprint != previous_fingerprint, "quality-only edit reimports and changes provenance")
	previous_fingerprint = model.import_fingerprint
	var straight_texture: String = model.textures[0].resource_path
	model.import_options["rendering/premultiplied_alpha"] = true
	expect(ResourceSaver.save(model, output) == OK, "save premultiplied alpha option")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	model = ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	expect(model.get_premultiplied_alpha() and model.import_fingerprint != previous_fingerprint, "alpha-only edit reimports and changes provenance")
	expect(model.textures[0].resource_path != straight_texture and model.textures[0].get_meta("cubism_premultiplied_alpha", false) == true, "alpha-only edit regenerates texture encoding")
	# Exercise a disabled source becoming available: it still is not a dependency.
	var excluded := source.get_base_dir().path_join("missing.exp3.json")
	write_json(excluded, {"deliberately": "not an expression"})
	before = status()
	await settle()
	expect(status().get("attempts") == before.get("attempts"), "disabled expression arrival does not trigger import")
	DirAccess.remove_absolute(excluded)
	# Editing stored options must add and then remove the corresponding dependency
	# closure, rather than merely changing the displayed import-options dictionary.
	manifest = original.duplicate(true)
	manifest.Layout = {"x": 0.375}
	write_json(variant, manifest)
	model.import_options["motions/import_manifest_motions"] = true
	model.import_options["expressions/import"] = true
	expect(ResourceSaver.save(model, output) == OK, "save enabled catalog options")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	model = ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	expect(not model.motion_groups.is_empty() and not model.expressions.is_empty(), "option edits restore catalog descriptors")
	var expression_path: String = model.expressions[0].source_path
	expect(expression_path in model.dependency_paths and model.dependency_fingerprints.has(expression_path), "enabled expression dependency restored")
	model.import_options["motions/import_manifest_motions"] = false
	model.import_options["expressions/import"] = false
	expect(ResourceSaver.save(model, output) == OK, "save disabled catalog options")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	model = ResourceLoader.load(output, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	expect(model.motion_groups.is_empty() and model.expressions.is_empty(), "option edits remove catalog descriptors")
	expect(not expression_path in model.dependency_paths and not model.dependency_fingerprints.has(expression_path), "disabled expression dependency removed")
	before = status()
	await settle()
	expect(status().get("attempts") == before.get("attempts"), "removing dependencies settles")
	# Leave a stale saved resource for the next editor process to rebuild.
	manifest.Layout.x = 0.625
	write_json(variant, manifest)
	for failure: String in failures:
		printerr("IMPORT_OPTIONS_FAIL: ", failure)
	print("CUBISM_IMPORT_OPTIONS cases=", cases, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_IMPORT_OPTIONS_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
