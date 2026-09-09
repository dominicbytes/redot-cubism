# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func parse(value: Dictionary) -> Dictionary:
	return CubismManifestParser.parse_expression(JSON.stringify(value), "笑顔", "res://expressions/笑顔.exp3.json")

func rejected(value: Dictionary, path: String) -> void:
	var result := parse(value)
	var found := false
	for diagnostic: Dictionary in result.diagnostics:
		found = found or diagnostic.path == path
	expect(not result.ok and result.expression == null and result.source_data.is_empty() and found, "reject " + path)

func _initialize() -> void:
	var value := {"Type": "Live2D Expression", "Parameters": [{"Id": "Param口", "Value": 0.75}], "Future": "保持"}
	var result := parse(value)
	expect(result.ok and result.expression is CubismExpressionDescriptor, "typed expression result")
	expect(result.expression.id == &"笑顔" and result.expression.source_path == "res://expressions/笑顔.exp3.json", "Unicode identity and path")
	expect(result.expression.fade_in_seconds == 1.0 and result.expression.fade_out_seconds == 1.0, "pinned SDK default fades")
	expect(result.expression.parameters[0].operation == CubismExpressionParameter.ADD and result.expression.parameters[0].value == 0.75, "missing Blend defaults to Add")
	expect(result.source_data.Future == "保持", "unknown fields retained")
	for blend: String in ["Add", "Multiply", "Overwrite"]:
		value.Parameters[0].Blend = blend
		result = parse(value)
		expect(result.ok and result.expression.parameters[0].operation == ["Add", "Multiply", "Overwrite"].find(blend), "operation " + blend)
	value.Parameters[0].Blend = null
	expect(parse(value).expression.parameters[0].operation == CubismExpressionParameter.ADD, "null Blend matches SDK default")
	value.FadeInTime = 0.25
	value.FadeOutTime = 0.5
	expect(parse(value).expression.fade_in_seconds == 0.25 and parse(value).expression.fade_out_seconds == 0.5, "explicit fades")
	for field: String in ["FadeInTime", "FadeOutTime"]:
		var invalid := value.duplicate(true)
		invalid[field] = "fast"
		rejected(invalid, field)
	for field: String in ["Id", "Value", "Blend"]:
		var invalid := value.duplicate(true)
		invalid.Parameters[0][field] = []
		rejected(invalid, "Parameters[0]." + field)
	var invalid := value.duplicate(true)
	invalid.Parameters[0].erase("Value")
	rejected(invalid, "Parameters[0].Value")
	invalid = value.duplicate(true)
	invalid.Parameters[0].Id = ""
	rejected(invalid, "Parameters[0].Id")
	invalid = value.duplicate(true)
	invalid.Parameters[0].Blend = "Screen"
	rejected(invalid, "Parameters[0].Blend")
	rejected({"Parameters": "wrong"}, "Parameters")
	rejected({"Type": "Wrong", "Parameters": []}, "Type")
	rejected({"Parameters": [5]}, "Parameters[0]")
	rejected({"Parameters": [{"Id": "P", "Value": 1e100}]}, "Parameters[0].Value")
	expect(parse({"Parameters": []}).ok, "empty expression and absent Type accepted")
	var ordered := {"Parameters": [{"Id": "P", "Value": 1}, {"Id": "P", "Value": 2}]}
	result = parse(ordered)
	expect(result.ok and result.expression.parameters.size() == 2 and result.expression.parameters[1].value == 2, "preserve ordered repeated parameter IDs")
	expect(not CubismManifestParser.parse_expression('{"Parameters":[{"Id":"P\\u0000","Value":1}]}', "Smile", "res://a.exp3.json").ok, "NUL escape rejected")
	expect(not CubismManifestParser.parse_expression("[]", "Smile", "res://a.exp3.json").ok, "non-object rejected")
	expect(not CubismManifestParser.parse_expression('{"Parameters":[]}', "Smile", "res://../a.exp3.json").ok, "source traversal rejected")
	var excessive: Array = []
	excessive.resize(4097)
	excessive.fill({"Id": "P", "Value": 0})
	rejected({"Parameters": excessive}, "Parameters")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest := CubismManifestParser.parse_manifest(FileAccess.get_file_as_string(fixture.model), fixture.model)
	for entry: Dictionary in manifest.manifest.FileReferences.get("Expressions", []):
		result = CubismManifestParser.parse_expression(FileAccess.get_file_as_string(entry.File), entry.Name, entry.File)
		expect(result.ok, "real fixture expression " + entry.Name)
	for failure: String in failures:
		printerr("EXPRESSION_PARSER_FAIL: ", failure)
	print("CUBISM_EXPRESSION_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_EXPRESSION_PARSER_PASS")
	quit(0 if failures.is_empty() else 1)
