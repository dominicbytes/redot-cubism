# SPDX-License-Identifier: MIT
extends SceneTree
## Executed externally against the staged game/PCK, never shipped as game code.

var _errors: PackedStringArray = []
var _visited: Dictionary = {}
var _remaining: int = 100000
var _models: int = 0
var _motions: int = 0
var _expressions: int = 0
var _moved: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _model(resource: Resource) -> void:
	_models += 1
	var runtime: Node = ClassDB.instantiate("GDCubismUserModel")
	runtime.set("playback_process_mode", ClassDB.class_get_integer_constant("GDCubismUserModel", "MANUAL"))
	root.add_child(runtime)
	runtime.set("model", resource)
	if not runtime.call("is_initialized"):
		_errors.append("Cannot initialize exported model: " + str(runtime.call("get_last_error")))
		runtime.free()
		return
	var groups: Dictionary = resource.get("motion_groups")
	for group: String in groups:
		if groups[group].is_empty():
			continue
		var motion: RefCounted = runtime.call("start_motion", group, 0, ClassDB.class_get_integer_constant("GDCubismUserModel", "PRIORITY_FORCE"))
		if motion == null or motion.call("get_error") != OK:
			_errors.append("Cannot start exported motion: " + group)
			break
		_motions += 1
		_advance(runtime)
	for expression: Resource in resource.get("expressions"):
		runtime.call("start_expression", expression.get("id"))
		_expressions += 1
		_advance(runtime)
	runtime.free()

func _advance(runtime: Node) -> void:
	var before: PackedFloat64Array = []
	for parameter: Object in runtime.call("get_parameters"):
		before.append(parameter.get("value"))
	for frame in 60:
		runtime.call("advance", 1.0 / 60.0)
		var parameters: Array = runtime.call("get_parameters")
		for index in parameters.size():
			var value: float = parameters[index].get("value")
			if not is_finite(value):
				_errors.append("Non-finite exported model parameter")
				return
			_moved = _moved or absf(value - before[index]) > 0.0001

func _visit(value: Variant, owner: String, depth: int) -> void:
	if not _errors.is_empty():
		return
	_remaining -= 1
	if _remaining < 0 or depth > 64:
		_errors.append("Exported resource graph exceeds smoke-test bounds")
		return
	if value is Resource:
		var resource: Resource = value
		var path: String = resource.resource_path.get_slice("::", 0)
		if not path.is_empty() and path != owner:
			return
		if _visited.has(resource.get_instance_id()):
			return
		_visited[resource.get_instance_id()] = true
		if resource.is_class("CubismModelResource"):
			_model(resource)
			return
		for property in resource.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE:
				_visit(resource.get(property.name), owner, depth + 1)
	elif value is Array:
		for child: Variant in value:
			_visit(child, owner, depth + 1)
	elif value is Dictionary:
		for key: Variant in value:
			_visit(key, owner, depth + 1)
			_visit(value[key], owner, depth + 1)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Expected preflight and smoke report paths")
		quit(2)
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if OS.has_feature("editor"):
		_errors.append("Smoke must run the exported template")
	for editor_class: String in ["CubismExportPlugin", "CubismExportValidator", "CubismModelImporter", "CubismDependencyTracker", "CubismModelInspector", "GDCubismPlugin"]:
		if ClassDB.class_exists(editor_class):
			_errors.append("Editor class present in exported template: " + editor_class)
	for path: String in expected.raw_hashes:
		if FileAccess.get_sha256(path) != expected.raw_hashes[path]:
			_errors.append("Exported source/shader hash mismatch: " + path)
	for path: String in expected.validated_files:
		if not _errors.is_empty():
			break
		var resource: Resource = ResourceLoader.load(path)
		if resource == null:
			_errors.append("Cannot load exported resource: " + path)
			break
		_visited.clear()
		_remaining = 100000
		_visit(resource, path, 0)
	if _models != int(expected.models):
		_errors.append("Exported model count differs from preflight")
	var build: Dictionary = ClassDB.class_call_static("CubismBuildInfo", "get_versions") if ClassDB.class_exists("CubismBuildInfo") else {}
	if _models > 0:
		for key: String in ["addon_version", "addon_commit", "redot_version", "redot_api_sha256", "redot_cpp_commit", "framework_commit", "core_version", "precision"]:
			if build.get(key) != expected.build.get(key):
				_errors.append("Runtime native identity differs from preflight: " + key)
	var report: FileAccess = FileAccess.open(args[1], FileAccess.WRITE)
	if report == null:
		printerr("Cannot write exported smoke report")
		quit(2)
		return
	report.store_string(JSON.stringify({"ok": _errors.is_empty(), "diagnostics": _errors, "models": _models, "motions": _motions, "expressions": _expressions, "parameters_changed": _moved, "build": build}, "\t") + "\n")
	report.close()
	print("CUBISM_EXPORTED_SMOKE_PASS" if _errors.is_empty() else "CUBISM_EXPORTED_SMOKE_FAIL")
	quit(0 if _errors.is_empty() else 1)
