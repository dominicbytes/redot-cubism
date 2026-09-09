# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func user_data(value: Dictionary) -> Dictionary:
	return CubismManifestParser.parse_user_data(JSON.stringify(value))

func display_info(value: Dictionary) -> Dictionary:
	return CubismManifestParser.parse_display_info(JSON.stringify(value))

func rejected(result: Dictionary, field: String, path: String) -> void:
	var found := false
	for diagnostic: Dictionary in result.diagnostics:
		found = found or diagnostic.path == path
	expect(not result.ok and result[field].is_empty() and found, "reject " + path)

func _initialize() -> void:
	var data := {"Version": 3, "Meta": {"UserDataCount": 1, "TotalUserDataSize": 6}, "UserData": [{"Target": "ArtMesh", "Id": "髪", "Value": "頭髪"}], "Future": "保持"}
	expect(user_data(data).ok and user_data(data).user_data.UserData == data.UserData, "Unicode user data preserved")
	for count: Variant in [-1, 0.5, 999999999, "1", true]:
		var copy := data.duplicate(true)
		copy.Meta.UserDataCount = count
		rejected(user_data(copy), "user_data", "Meta.UserDataCount")
	for field: String in ["Target", "Id", "Value"]:
		var copy := data.duplicate(true)
		copy.UserData[0][field] = []
		rejected(user_data(copy), "user_data", "UserData[0]." + field)
	for field: String in ["Target", "Id"]:
		var copy := data.duplicate(true)
		copy.UserData[0][field] = ""
		rejected(user_data(copy), "user_data", "UserData[0]." + field)
	for size: Variant in [-1, 0.5, "six"]:
		var copy := data.duplicate(true)
		copy.Meta.TotalUserDataSize = size
		rejected(user_data(copy), "user_data", "Meta.TotalUserDataSize")
	data.UserData[0].Value = ""
	data.UserData[0].Target = "FutureTarget"
	expect(user_data(data).ok, "empty value and future target preserved")
	var info := {"Version": 3, "Parameters": [{"Id": "P", "GroupId": "", "Name": "角度"}], "ParameterGroups": [{"Id": "G", "Name": "顔"}], "Parts": [{"Id": "P", "Name": "体"}], "CombinedParameters": [["P", "Q"]], "Future": "保持"}
	expect(display_info(info).ok and display_info(info).display_info.Parameters == info.Parameters, "display names and cross-collection IDs preserved")
	for field: String in ["Parameters", "ParameterGroups", "Parts"]:
		var copy := info.duplicate(true)
		copy[field].append(copy[field][0].duplicate(true))
		rejected(display_info(copy), "display_info", field + "[1].Id")
		copy[field] = {}
		rejected(display_info(copy), "display_info", field)
	for field: String in ["Id", "Name", "GroupId"]:
		var copy := info.duplicate(true)
		copy.Parameters[0][field] = 1
		rejected(display_info(copy), "display_info", "Parameters[0]." + field)
	info.CombinedParameters = [[1]]
	rejected(display_info(info), "display_info", "CombinedParameters[0][0]")
	info.CombinedParameters = ["P"]
	rejected(display_info(info), "display_info", "CombinedParameters[0]")
	expect(display_info({"Version": 3}).ok, "optional display collections")
	rejected(display_info({"Version": 2}), "display_info", "Version")
	rejected(user_data({"Version": true}), "user_data", "Version")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest := CubismManifestParser.parse_manifest(FileAccess.get_file_as_string(fixture.model), fixture.model)
	for key: String in ["DisplayInfo", "UserData"]:
		var path: String = manifest.manifest.FileReferences.get(key, "")
		if not path.is_empty():
			var source := FileAccess.get_file_as_string(path)
			var result := CubismManifestParser.parse_display_info(source) if key == "DisplayInfo" else CubismManifestParser.parse_user_data(source)
			expect(result.ok, "real fixture " + key)
	for failure: String in failures:
		printerr("METADATA_PARSER_FAIL: ", failure)
	print("CUBISM_METADATA_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_METADATA_PARSER_PASS")
	quit(0 if failures.is_empty() else 1)
