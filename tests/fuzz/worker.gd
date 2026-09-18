# SPDX-License-Identifier: MIT
# One case per fresh Redot process. The parent creates the ready file only after
# assigning Windows Job limits (or Unix resource limits at process creation).
extends SceneTree

const MAX_DIAGNOSTICS := 32
const MAX_DIAGNOSTIC_BYTES := 1024 * 1024


func _write_result(path: String, value: Dictionary, code: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("FUZZ_WORKER_RESULT_OPEN_FAILED")
		quit(3)
		return
	file.store_string(JSON.stringify(value))
	file.close()
	print("FUZZ_WORKER_DONE")
	quit(code)


func _diagnostics(value: Dictionary, snapshot: Dictionary) -> void:
	var problems: Array[String] = []
	var entries: Variant = value.get("diagnostics")
	if typeof(entries) != TYPE_ARRAY:
		problems.append("diagnostics is not an Array")
		entries = []
	var diagnostics: Array = entries
	if typeof(value.get("ok")) != TYPE_BOOL:
		problems.append("ok is not a boolean")
	if diagnostics.size() > MAX_DIAGNOSTICS:
		problems.append("diagnostic count exceeds 32")
	for item: Variant in diagnostics:
		if typeof(item) != TYPE_DICTIONARY:
			problems.append("diagnostic is not a Dictionary")
			continue
		var path_kind := typeof(item.get("path"))
		if path_kind != TYPE_STRING and path_kind != TYPE_STRING_NAME:
			problems.append("diagnostic path is not text")
		if typeof(item.get("message")) != TYPE_STRING:
			problems.append("diagnostic message is not text")
	var encoded := JSON.stringify(diagnostics)
	var byte_count := encoded.to_utf8_buffer().size()
	if byte_count > MAX_DIAGNOSTIC_BYTES:
		problems.append("encoded diagnostics exceed 1 MiB")
	snapshot["diagnostics"] = diagnostics
	snapshot["diagnostic_bytes"] = byte_count
	snapshot["contract_errors"] = problems


func _motion_value(item: CubismMotionDescriptor) -> Dictionary:
	var events: Array[Dictionary] = []
	for event: CubismMotionEvent in item.events:
		events.append({"time_seconds": event.time_seconds, "value": event.value})
	return {"id": String(item.id), "group": String(item.group), "index": item.index,
		"source_path": item.source_path, "sound_path": item.sound_path,
		"fade_in_seconds": item.fade_in_seconds, "fade_out_seconds": item.fade_out_seconds,
		"duration_seconds": item.duration_seconds, "loop": item.loop,
		"events": events, "metadata": item.metadata}


func _expression_value(item: CubismExpressionDescriptor) -> Dictionary:
	var parameters: Array[Dictionary] = []
	for parameter: CubismExpressionParameter in item.parameters:
		parameters.append({"id": String(parameter.id), "value": parameter.value,
			"operation": parameter.operation})
	return {"id": String(item.id), "source_path": item.source_path,
		"fade_in_seconds": item.fade_in_seconds, "fade_out_seconds": item.fade_out_seconds,
		"parameters": parameters}


func _options(envelope: Dictionary) -> Dictionary:
	var options := {}
	for entry: Array in envelope.entries:
		var key: Variant = entry[1]
		match entry[0]:
			"string_name": key = StringName(key)
			"int": key = int(key)
			"bool": key = bool(key)
		var value: Variant = entry[2]
		if entry.size() == 4 and entry[3] == "int":
			value = int(value)
		options[key] = value
	return options


func _run_case(envelope: Dictionary) -> Dictionary:
	var target: String = envelope.target
	var result: Dictionary
	var snapshot := {"target": target}
	match target:
		"manifest", "path", "dedup":
			result = CubismManifestParser.parse_manifest(envelope.payload, "res://models/Hero.model3.json")
			snapshot["ok"] = result.get("ok")
			snapshot["manifest"] = result.get("manifest")
			var dependencies: Array[String] = []
			for dependency: String in result.get("dependencies", PackedStringArray()):
				dependencies.append(dependency)
			snapshot["dependencies"] = dependencies
			if target == "path" and result.get("ok"):
				var containment: Array[Dictionary] = []
				for dependency: String in result.dependencies:
					var checked := CubismManifestParser.validate_project_file(dependency)
					containment.append({"path": dependency, "status": checked.get("status")})
				snapshot["containment"] = containment
		"motion":
			result = CubismManifestParser.parse_motion(envelope.payload, "待機", 2, "res://motions/待機.motion3.json")
			snapshot["ok"] = result.get("ok")
			var item := result.get("motion") as CubismMotionDescriptor
			snapshot["motion"] = _motion_value(item) if item != null else null
		"expression":
			result = CubismManifestParser.parse_expression(envelope.payload, "笑顔", "res://expressions/笑顔.exp3.json")
			snapshot["ok"] = result.get("ok")
			var item := result.get("expression") as CubismExpressionDescriptor
			snapshot["expression"] = _expression_value(item) if item != null else null
			snapshot["source_data"] = result.get("source_data")
		"options":
			# Validation precedes file lookup. No file exists at this source path, so
			# even valid options cannot advance to a MOC or proprietary Core call.
			result = CubismModelFactory.build_with_options("res://__fuzz_missing__.model3.json", _options(envelope))
			snapshot["ok"] = result.get("ok")
			snapshot["model_present"] = result.get("model") != null
			var paths: Array = []
			var raw_diagnostics: Variant = result.get("diagnostics", [])
			if typeof(raw_diagnostics) == TYPE_ARRAY:
				for diagnostic: Variant in raw_diagnostics:
					if typeof(diagnostic) == TYPE_DICTIONARY:
						paths.append(diagnostic.get("path"))
			snapshot["rejection_stage"] = "source_missing" if paths == ["source_path"] else "options"
		"read_utf8":
			result = CubismManifestParser.read_project_json("res://fuzz_bytes.txt")
			snapshot["ok"] = result.get("ok")
			snapshot["status"] = result.get("status")
			snapshot["message"] = result.get("message")
			snapshot["text"] = result.get("text")
			snapshot["byte_length"] = result.get("byte_length", 0)
			snapshot["sha256"] = result.get("sha256", "")
		_:
			return {"harness_error": "unknown target"}
	if target == "read_utf8":
		result["diagnostics"] = []
	_diagnostics(result, snapshot)
	return snapshot


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("FUZZ_WORKER_ARGS_FAILED")
		quit(2)
		return
	var ready: String = args[0]
	var input: String = args[1]
	var output: String = args[2]
	var deadline := Time.get_ticks_msec() + 5000
	while not FileAccess.file_exists(ready):
		if Time.get_ticks_msec() >= deadline:
			_write_result(output, {"harness_error": "Job readiness gate timed out"}, 2)
			return
		OS.delay_msec(10)
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if typeof(envelope) != TYPE_DICTIONARY:
		_write_result(output, {"harness_error": "case envelope is not a Dictionary"}, 2)
		return
	_write_result(output, _run_case(envelope), 0)
