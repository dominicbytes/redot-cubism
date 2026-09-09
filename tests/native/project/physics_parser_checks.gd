# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func parse(value: Dictionary) -> Dictionary:
	return CubismManifestParser.parse_physics(JSON.stringify(value))

func rejected(value: Dictionary, path: String) -> void:
	var result := parse(value)
	var found := false
	for diagnostic: Dictionary in result.diagnostics:
		found = found or diagnostic.path == path
	expect(not result.ok and result.physics.is_empty() and found, "reject " + path)

func _initialize() -> void:
	var vertex := {"Mobility": 0.8, "Delay": 0.2, "Acceleration": 1, "Radius": 1, "Position": {"X": 0, "Y": 1}}
	var value := {"Version": 3, "Meta": {"PhysicsSettingCount": 1, "TotalInputCount": 1, "TotalOutputCount": 1, "VertexCount": 2, "EffectiveForces": {"Gravity": {"X": 0, "Y": -1}, "Wind": {"X": 0, "Y": 0}}}, "PhysicsSettings": [{"Input": [{"Source": {"Target": "Parameter", "Id": "入力"}, "Weight": 100, "Type": "X", "Reflect": false}], "Output": [{"Destination": {"Target": "Parameter", "Id": "出力"}, "Weight": 100, "Type": "Angle", "Reflect": true, "Scale": 1, "VertexIndex": 1}], "Vertices": [vertex.duplicate(true), vertex.duplicate(true)], "Normalization": {"Position": {"Minimum": -10, "Maximum": 10, "Default": 0}, "Angle": {"Minimum": -30, "Maximum": 30, "Default": 0}}}], "Future": "保持"}
	var result := parse(value)
	expect(result.ok and JSON.stringify(result.physics) == JSON.stringify(JSON.parse_string(JSON.stringify(value))), "preserve valid physics data and Unicode")
	for field: String in ["PhysicsSettingCount", "TotalInputCount", "TotalOutputCount", "VertexCount"]:
		for wrong: Variant in [-1, 0.5, 999999999, "1", true]:
			var copy := value.duplicate(true)
			copy.Meta[field] = wrong
			rejected(copy, "Meta." + field)
	for fps: Variant in [0, 30, 1000]:
		var copy := value.duplicate(true)
		copy.Meta.Fps = fps
		expect(parse(copy).ok, "supported FPS " + str(fps))
	for fps: Variant in [-1, 1001, 1e100, "30"]:
		var copy := value.duplicate(true)
		copy.Meta.Fps = fps
		rejected(copy, "Meta.Fps")
	for field: String in ["Input", "Output", "Vertices"]:
		var copy := value.duplicate(true)
		copy.PhysicsSettings[0][field] = []
		rejected(copy, "PhysicsSettings[0]." + field)
	for field: String in ["Input", "Output"]:
		var copy := value.duplicate(true)
		copy.PhysicsSettings[0][field][0].Type = "Unknown"
		rejected(copy, "PhysicsSettings[0]." + field + "[0].Type")
		copy.PhysicsSettings[0][field][0].Type = "Y"
		expect(parse(copy).ok, "Y callback " + field)
		copy.PhysicsSettings[0][field][0].Reflect = 1
		rejected(copy, "PhysicsSettings[0]." + field + "[0].Reflect")
	for index: Variant in [-1, 0, 0.5, 2, 999999999, "1"]:
		var copy := value.duplicate(true)
		copy.PhysicsSettings[0].Output[0].VertexIndex = index
		rejected(copy, "PhysicsSettings[0].Output[0].VertexIndex")
	for field: String in ["Mobility", "Delay", "Acceleration", "Radius"]:
		var copy := value.duplicate(true)
		copy.PhysicsSettings[0].Vertices[0][field] = 1e100
		rejected(copy, "PhysicsSettings[0].Vertices[0]." + field)
	var copy := value.duplicate(true)
	copy.Meta.EffectiveForces.Gravity.X = "bad"
	rejected(copy, "Meta.EffectiveForces.Gravity.X")
	copy = value.duplicate(true)
	copy.PhysicsSettings[0].Normalization.Angle.Default = []
	rejected(copy, "PhysicsSettings[0].Normalization.Angle.Default")
	copy = value.duplicate(true)
	copy.PhysicsSettings[0].Output[0].Destination.Target = "PartOpacity"
	rejected(copy, "PhysicsSettings[0].Output[0].Destination.Target")
	copy = value.duplicate(true)
	copy.PhysicsSettings[0].Input[0].Source.Id = ""
	rejected(copy, "PhysicsSettings[0].Input[0].Source.Id")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest := CubismManifestParser.parse_manifest(FileAccess.get_file_as_string(fixture.model), fixture.model)
	var physics: String = manifest.manifest.FileReferences.get("Physics", "")
	if not physics.is_empty():
		expect(CubismManifestParser.parse_physics(FileAccess.get_file_as_string(physics)).ok, "real fixture physics")
	for failure: String in failures:
		printerr("PHYSICS_PARSER_FAIL: ", failure)
	print("CUBISM_PHYSICS_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_PHYSICS_PARSER_PASS")
	quit(0 if failures.is_empty() else 1)
