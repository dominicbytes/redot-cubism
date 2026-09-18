# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

var checks: int = 0
var validator: RefCounted
var config := ConfigFile.new()

func _enter_tree() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _check(files: PackedStringArray, mode: String = "resources", includes: String = "", excludes: String = "") -> Dictionary:
	config.set_value("preset.0", "name", "Models")
	config.set_value("preset.0", "platform", "Linux")
	config.set_value("preset.0", "export_filter", mode)
	config.set_value("preset.0", "export_files", files)
	config.set_value("preset.0", "include_filter", includes)
	config.set_value("preset.0", "exclude_filter", excludes)
	assert(config.save("res://export_presets.cfg") == OK)
	return validator.validate_preset("Models")

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():
		await get_tree().process_frame
	validator = load("res://addons/gd_cubism/editor/export_preflight.gd").new()
	var saved_config: PackedByteArray = FileAccess.get_file_as_bytes("res://export_presets.cfg")
	var model := load("res://imported-model.res") as CubismModelResource
	var stale := model.duplicate() as CubismModelResource
	stale.import_fingerprint = "stale"
	assert(ResourceSaver.save(stale, "res://preflight-stale.res") == OK)
	var wrapper := Resource.new()
	var embedded := stale.duplicate() as CubismModelResource
	wrapper.set_meta("model", embedded)
	assert(ResourceSaver.save(wrapper, "res://preflight-embedded.tres") == OK)
	filesystem.scan()
	await get_tree().process_frame
	while filesystem.is_scanning():
		await get_tree().process_frame
	var result: Dictionary = _check(["res://imported-model.res"])
	_expect(result.ok and result.models == 1, "Unselected invalid models must not block export")
	_expect(result.raw_hashes.has(model.moc_path), "Selected model raw dependency closure")
	_expect(result.files.has("res://addons/gd_cubism/gd_cubism.gdextension"), "Native extension edge in closure")
	var customized: Dictionary = {"res://": "remove"}
	for path: String in result.files:
		customized[path] = "keep"
	config.set_value("preset.0", "customized_files", customized)
	result = _check([], "customized")
	_expect(result.ok and result.models == 1 and not result.files.has("res://preflight-stale.res"), "Customized root removal with per-file keep overrides")
	config.erase_section_key("preset.0", "customized_files")
	result = _check(["res://preflight-stale.res"])
	_expect(not result.ok and result.raw_hashes.is_empty() and result.files.is_empty(), "Reject stale imported model without partial output")
	result = _check(["res://preflight-embedded.tres"])
	_expect(not result.ok, "Reject stale model nested inside a Resource")
	result = _check(["res://imported-model.res"], "resources", "preflight-stale.res")
	_expect(not result.ok, "Include filter adds invalid model to preflight")
	result = _check(["res://imported-model.res"], "resources", "preflight-stale.res", "res://preflight-stale.res")
	_expect(result.ok, "Exclude filter wins over include filter")
	result = _check(["res://imported-model.res"], "resources", "", "addons/gd_cubism/*.gdextension")
	_expect(not result.ok, "Reject exclusion of the required native extension")
	result = _check([], "resources", "imported-model.res")
	_expect(not result.ok, "Include filters do not automatically select resource dependencies")
	result = _check(["res://imported-model.res"], "resources", "", "cubism_generated/*")
	_expect(not result.ok, "Reject exclusion of imported texture resources")
	result = _check([], "all_resources")
	_expect(not result.ok, "All-resources mode must validate unrelated included models")
	result = _check(["res://preflight-stale.res", "res://preflight-embedded.tres"], "exclude")
	_expect(result.ok, "Exclude-selected mode removes invalid models")
	result = _check(["res://missing-model.res"])
	_expect(not result.ok, "Missing explicitly selected model is an error")
	result = _check(["res://preflight-stale.res", "res://matrix-embedded.tscn"], "scenes")
	_expect(result.ok and result.models == 1, "Scene selection ignores non-scenes and validates embedded models")
	ProjectSettings.set_setting("autoload/PreflightModel", "*res://matrix-external.tscn")
	result = _check([], "resources")
	_expect(result.ok and result.files.has("res://imported-model.res"), "Autoload model dependency is selected")
	ProjectSettings.set_setting("autoload/PreflightModel", null)
	var shader: String = "res://addons/gd_cubism/res/shader/2d_cubism_mask.gdshader"
	assert(DirAccess.rename_absolute(shader, shader + ".saved") == OK)
	result = _check(["res://imported-model.res"])
	assert(DirAccess.rename_absolute(shader + ".saved", shader) == OK)
	_expect(not result.ok and result.raw_hashes.is_empty(), "Missing shader fails preflight")
	var shader_bytes: PackedByteArray = FileAccess.get_file_as_bytes(shader)
	var oversized: PackedByteArray = []
	oversized.resize(1024 * 1024 + 1)
	var shader_file := FileAccess.open(shader, FileAccess.WRITE)
	shader_file.store_buffer(oversized)
	shader_file.close()
	result = _check(["res://imported-model.res"])
	shader_file = FileAccess.open(shader, FileAccess.WRITE)
	shader_file.store_buffer(shader_bytes)
	shader_file.close()
	_expect(not result.ok and result.raw_hashes.is_empty(), "Oversized shader fails before export injection")
	config.set_value("preset.1", "name", "Models")
	result = _check(["res://imported-model.res"])
	_expect(not result.ok, "Ambiguous preset name fails preflight")
	config.erase_section("preset.1")
	result = validator.validate_preset("Unknown")
	_expect(not result.ok, "Unknown preset fails preflight")
	for path: String in ["res://preflight-stale.res", "res://preflight-embedded.tres"]:
		assert(DirAccess.remove_absolute(path) == OK)
	var file := FileAccess.open("res://export_presets.cfg", FileAccess.WRITE)
	file.store_buffer(saved_config)
	file.close()
	print("CUBISM_EXPORT_PREFLIGHT_CASES=", checks)
	print("CUBISM_EXPORT_PREFLIGHT_CHECKS_PASS")
	get_tree().quit()
