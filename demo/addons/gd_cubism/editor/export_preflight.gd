# SPDX-License-Identifier: MIT
@tool
extends RefCounted
## Shared checked-export preflight. Call after the editor filesystem scan/import.
## Selection mirrors the pinned Redot 26.2 EditorExportPlatform implementation.

const MAX_FILES: int = 100000
const SHADERS: PackedStringArray = ["mask", "mask_add", "mask_add_inv", "mask_mix", "mask_mix_inv", "mask_mul", "mask_mul_inv", "norm_add", "norm_mix", "norm_mul"]
var _diagnostics: Array[Dictionary] = []
var _indexed: Dictionary = {}
var _selected: Dictionary = {}
var _validated: PackedStringArray = []

func _error(path: String, message: String) -> void:
	if _diagnostics.size() < 32:
		_diagnostics.append({"path": path, "message": message})

func _index(directory: EditorFileSystemDirectory, customized: Dictionary, inherited: int) -> void:
	if directory == null or not _diagnostics.is_empty():
		return
	var mode: int = customized.get(directory.get_path(), inherited)
	for i in directory.get_file_count():
		var path: String = directory.get_file_path(i)
		_indexed[path] = directory.get_file_type(i)
		if _indexed.size() > MAX_FILES:
			_error(path, "Export selection exceeds the file-count limit.")
			return
		if directory.get_file_type(i) != "TextFile" and int(customized.get(path, mode)) != EditorExportPreset.MODE_FILE_REMOVE:
			_selected[path] = true
	for i in directory.get_subdir_count():
		_index(directory.get_subdir(i), customized, mode)

func _dependencies(roots: PackedStringArray) -> void:
	var pending: Array[String] = []
	pending.assign(roots)
	while not pending.is_empty() and _diagnostics.is_empty():
		var path: String = pending.pop_back()
		if _selected.has(path):
			continue
		if not path.begins_with("res://") or not FileAccess.file_exists(path):
			_error(path, "Selected resource or dependency is missing.")
			continue
		_selected[path] = true
		if _selected.size() > MAX_FILES:
			_error(path, "Export dependency closure exceeds the file-count limit.")
			break
		# The engine stops at files absent from its scanned resource index.
		if not _indexed.has(path):
			continue
		for dependency in ResourceLoader.get_dependencies(path):
			var target: String = _dependency_path(path, dependency)
			if not target.is_empty():
				pending.append(target)

func _dependency_path(owner: String, dependency: String) -> String:
	var target: String = dependency.get_slice("::", 0)
	if target.begins_with("uid://"):
		var uid: int = ResourceUID.text_to_id(target)
		if not ResourceUID.has_id(uid):
			_error(owner, "Dependency UID is not registered: " + target)
			return ""
		target = ResourceUID.get_id_path(uid)
	return target

func _matches(path: String, patterns: PackedStringArray) -> bool:
	for pattern in patterns:
		var trimmed: String = pattern.strip_edges()
		if not trimmed.is_empty() and (path.matchn(trimmed) or path.trim_prefix("res://").matchn(trimmed)):
			return true
	return false

func _filters(includes: PackedStringArray, excludes: PackedStringArray) -> void:
	var pending: Array[String] = ["res://"]
	var count: int = 0
	while not pending.is_empty() and _diagnostics.is_empty():
		var path: String = pending.pop_back()
		var directory: DirAccess = DirAccess.open(path)
		if directory == null:
			_error(path, "Cannot enumerate export filters.")
			return
		directory.list_dir_begin()
		var name: String = directory.get_next()
		while not name.is_empty():
			count += 1
			if count > MAX_FILES:
				_error(path, "Export filter scan exceeds the file-count limit.")
				break
			var file: String = path.path_join(name)
			if directory.current_is_dir():
				if not name.begins_with(".") and not FileAccess.file_exists(file.path_join(".gdignore")) and not FileAccess.file_exists(file.path_join("project.godot")):
					if directory.is_link(name):
						_error(file, "Directory symlinks are not supported by checked export.")
					else:
						pending.append(file)
			else:
				if _matches(file, includes):
					_selected[file] = true
				if _matches(file, excludes) or file.matchn("*.import"):
					_selected.erase(file)
			name = directory.get_next()
		directory.list_dir_end()

func validate_preset(preset_name: String) -> Dictionary:
	_diagnostics.clear()
	_indexed.clear()
	_selected.clear()
	_validated.clear()
	var hashes: Dictionary = {}
	var models: int = 0
	var config := ConfigFile.new()
	var section: String = ""
	if config.load("res://export_presets.cfg") != OK:
		_error("export_presets.cfg", "Cannot read export presets.")
	else:
		var index: int = 0
		while config.has_section("preset." + str(index)):
			var candidate: String = "preset." + str(index)
			if config.get_value(candidate, "name", "") == preset_name:
				if not section.is_empty():
					_error(preset_name, "Export preset name is ambiguous.")
				section = candidate
			index += 1
	if section.is_empty():
		_error(preset_name, "Export preset was not found.")
	if not _diagnostics.is_empty():
		return _result(models, hashes)
	var platform: String = config.get_value(section, "platform", "")
	if platform not in ["Linux", "Windows Desktop"]:
		_error(platform, "Checked export currently requires a Linux or Windows Desktop preset.")
		return _result(models, hashes)
	var options: String = section + ".options"
	# Match EditorExportPreset.get_project_setting's platform/preset features,
	# which intentionally do not include template_debug/template_release.
	var features: PackedStringArray = ["pc", "linux" if platform == "Linux" else "windows", config.get_value(options, "binary_format/architecture", "x86_64")]
	if config.get_value(options, "texture_format/s3tc_bptc", true):
		features.append_array(["s3tc", "bptc"])
	if config.get_value(options, "texture_format/etc2_astc", false):
		features.append_array(["etc2", "astc"])
	if not config.get_value(section, "dedicated_server", false) and config.get_value(options, "shader_baker/enabled", false):
		features.append("shader_baker")
	for feature in str(config.get_value(section, "custom_features", "")).split(",", false):
		if not feature.strip_edges().is_empty():
			features.append(feature.strip_edges())
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if filesystem == null or filesystem.is_scanning():
		_error(preset_name, "Wait for the editor filesystem scan and imports to finish.")
		return _result(models, hashes)
	var filter: String = config.get_value(section, "export_filter", "")
	var customized: Dictionary = {}
	if filter == "customized":
		var stored: Dictionary = config.get_value(section, "customized_files", {})
		var modes: Dictionary = {"keep": EditorExportPreset.MODE_FILE_KEEP, "strip": EditorExportPreset.MODE_FILE_STRIP, "remove": EditorExportPreset.MODE_FILE_REMOVE}
		for path: String in stored:
			if modes.has(str(stored[path])):
				customized[path] = modes[str(stored[path])]
	_index(filesystem.get_filesystem(), customized, EditorExportPreset.MODE_FILE_NOT_CUSTOMIZED)
	var files: PackedStringArray = config.get_value(section, "export_files", PackedStringArray())
	match filter:
		"resources", "scenes":
			_selected.clear()
			var roots: PackedStringArray = []
			for path in files:
				if not FileAccess.file_exists(path):
					_error(path, "Explicitly selected export file is missing.")
				elif filter != "scenes" or _indexed.get(path, "") == "PackedScene":
					roots.append(path)
			for property in ProjectSettings.get_property_list():
				if str(property.name).begins_with("autoload/"):
					roots.append(str(ProjectSettings.get_setting_with_override_and_custom_features(property.name, features)).trim_prefix("*"))
			_dependencies(roots)
		"exclude":
			for path in files:
				_selected.erase(path)
		"all_resources", "customized":
			pass
		_:
			_error(preset_name, "Unknown export selection mode.")
	var includes: PackedStringArray = str(config.get_value(section, "include_filter", "")).split(",")
	includes.append_array(["*.ico", "*.icns"])
	_filters(includes, str(config.get_value(section, "exclude_filter", "")).split(","))
	# Redot skips these before invoking any export plugin callback.
	for path: String in _selected.keys():
		if FileAccess.file_exists(path + ".import"):
			var sidecar := ConfigFile.new()
			if sidecar.load(path + ".import") != OK:
				_error(path, "Cannot read selected resource import metadata.")
			elif sidecar.get_value("remap", "importer", "") == "skip":
				_selected.erase(path)
	for path: String in _selected:
		if not _diagnostics.is_empty():
			break
		if _indexed.get(path, "") != "CubismModelResource" and path.get_extension() not in ["res", "tres", "tscn", "scn"]:
			continue
		_validated.append(path)
		var checked: Dictionary = CubismExportValidator.validate_file(path)
		if not checked.ok:
			_diagnostics.assign(checked.diagnostics)
			break
		models += int(checked.models)
		for raw: String in checked.raw_hashes:
			if hashes.has(raw) and hashes[raw] != checked.raw_hashes[raw]:
				_error(raw, "Selected models have conflicting source hashes.")
			hashes[raw] = checked.raw_hashes[raw]
	if models > 0:
		for shader in SHADERS:
			var path: String = "res://addons/gd_cubism/res/shader/2d_cubism_" + shader + ".gdshader"
			if CubismManifestParser.validate_project_file(path).status != "file":
				_error(path, "Required Cubism shader is missing or unsafe.")
			else:
				var source: FileAccess = FileAccess.open(path, FileAccess.READ)
				if source == null or source.get_length() > 1024 * 1024:
					_error(path, "Cannot read Cubism shader within the 1 MiB limit.")
				else:
					hashes[path] = FileAccess.get_sha256(path)
	# Include filters add files without adding their resource dependencies. Also
	# reject exclusions that cut real resource edges, before packaging can begin.
	for path in _validated:
		for dependency in ResourceLoader.get_dependencies(path):
			var target: String = _dependency_path(path, dependency)
			if not target.is_empty() and not _selected.has(target) and not hashes.has(target):
				_error(path, "Export selection omits a required resource dependency: " + target)
	return _result(models, hashes)

func _result(models: int, hashes: Dictionary) -> Dictionary:
	var files: Array = _selected.keys()
	files.sort()
	_validated.sort()
	return {"ok": _diagnostics.is_empty(), "diagnostics": _diagnostics.duplicate(true), "models": models, "files": files if _diagnostics.is_empty() else [], "validated_files": _validated if _diagnostics.is_empty() else PackedStringArray(), "raw_hashes": hashes if _diagnostics.is_empty() else {}}
