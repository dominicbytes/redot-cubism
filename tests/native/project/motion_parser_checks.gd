# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func parse(value: Dictionary) -> Dictionary:
	return CubismManifestParser.parse_motion(JSON.stringify(value), "待機", 2, "res://motions/待機.motion3.json")

func rejected(value: Dictionary, label: String) -> void:
	var result := parse(value)
	expect(not result.ok and result.motion == null and not result.diagnostics.is_empty(), label)

func _initialize() -> void:
	var value := {"Version": 3, "Meta": {"Duration": 4, "Fps": 30, "Loop": true, "CurveCount": 1, "TotalSegmentCount": 4, "TotalPointCount": 7, "UserDataCount": 1}, "Curves": [{"Target": "Parameter", "Id": "Param口", "Segments": [0, 0, 0, 1, 1, 1, 1.25, 0.5, 1.75, 0.25, 2, 0, 2, 3, 1, 3, 4, 0]}], "UserData": [{"Time": 2, "Value": "合図"}], "Future": "保持"}
	var result := parse(value)
	expect(result.ok and result.motion is CubismMotionDescriptor, "four segment forms accepted")
	if result.ok:
		expect(result.motion.id == &"待機/2" and result.motion.group == &"待機" and result.motion.index == 2, "stable Unicode identity")
		expect(result.motion.duration_seconds == 4 and result.motion.loop, "duration and loop")
		expect(result.motion.fade_in_seconds == 1 and result.motion.fade_out_seconds == 1, "SDK default fades")
		expect(result.motion.events.size() == 1 and result.motion.events[0].value == "合図" and result.motion.events[0].time_seconds == 2, "typed Unicode event")
		expect(JSON.stringify(result.motion.metadata.Curves) == JSON.stringify(JSON.parse_string(JSON.stringify(value)).Curves) and result.motion.metadata.Future == "保持", "curves and unknown metadata retained")
		expect(result.motion.animation == null and result.motion.sound == null, "no implicit timeline or sound")
	for target: String in ["Model", "PartOpacity"]:
		var copy := value.duplicate(true)
		copy.Curves[0].Target = target
		expect(parse(copy).ok, target + " curve preserved")
	for field: String in ["CurveCount", "TotalSegmentCount", "TotalPointCount", "UserDataCount"]:
		for wrong: Variant in [-1, 0.5, 999999999, "1", false]:
			var copy := value.duplicate(true)
			copy.Meta[field] = wrong
			rejected(copy, "invalid " + field + " " + str(wrong))
	for field: String in ["Duration", "Fps"]:
		for wrong: Variant in [0, -1, {}, "1", 1e100]:
			var copy := value.duplicate(true)
			copy.Meta[field] = wrong
			rejected(copy, "invalid " + field)
	for segments: Array in [[], [0, 1], [0, 1, 1, 2, 3], [0, 1, 9, 2, 3], [0, 1, 0.5, 2, 3], [0, 1, 0, 0, 3], [0, 1, 0, 1, "bad"], [0, 1, 0, 1, 1e100]]:
		var copy := value.duplicate(true)
		copy.Curves[0].Segments = segments
		rejected(copy, "malformed segment " + str(segments))
	for wrong: Variant in [-1, 5, {}, "2"]:
		var copy := value.duplicate(true)
		copy.UserData[0].Time = wrong
		rejected(copy, "invalid event time")
	var copy := value.duplicate(true)
	copy.Meta.FadeInTime = -1
	copy.Meta.FadeOutTime = 0.25
	result = parse(copy)
	expect(result.ok and result.motion.fade_in_seconds == 1 and result.motion.fade_out_seconds == 0.25, "SDK negative fade fallback")
	copy = value.duplicate(true)
	copy.Curves[0].Target = "Unknown"
	rejected(copy, "unknown target")
	copy = value.duplicate(true)
	copy.Curves.append(copy.Curves[0].duplicate(true))
	copy.Curves[1].Target = "Model"
	copy.Meta.CurveCount = 2
	copy.Meta.TotalSegmentCount = 8
	copy.Meta.TotalPointCount = 14
	rejected(copy, "out-of-order targets rejected before SDK playback")
	copy = value.duplicate(true)
	copy.erase("UserData")
	rejected(copy, "missing declared events")
	copy.Meta.erase("UserDataCount")
	expect(parse(copy).ok, "absent events and event count")
	expect(not CubismManifestParser.parse_motion("{}", "Idle", 0, "res://../a.motion3.json").ok, "traversal rejected")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest := CubismManifestParser.parse_manifest(FileAccess.get_file_as_string(fixture.model), fixture.model)
	for group: String in manifest.manifest.FileReferences.get("Motions", {}):
		var index := 0
		for entry: Dictionary in manifest.manifest.FileReferences.Motions[group]:
			result = CubismManifestParser.parse_motion(FileAccess.get_file_as_string(entry.File), group, index, entry.File)
			expect(result.ok, "fixture motion " + entry.File + " " + str(result.diagnostics))
			index += 1
	for failure: String in failures:
		printerr("MOTION_PARSER_FAIL: ", failure)
	print("CUBISM_MOTION_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_MOTION_PARSER_PASS")
	quit(0 if failures.is_empty() else 1)
