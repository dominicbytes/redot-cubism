# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func parse(value: Dictionary) -> Dictionary:
	return CubismManifestParser.parse_pose(JSON.stringify(value))

func rejected(value: Dictionary, path: String) -> void:
	var result := parse(value)
	var found := false
	for diagnostic: Dictionary in result.diagnostics:
		found = found or diagnostic.path == path
	expect(not result.ok and result.pose.is_empty() and found, "reject " + path)

func _initialize() -> void:
	var value := {"Type": "Live2D Pose", "Groups": [[{"Id": "腕", "Link": ["袖", "手"]}]], "Future": "保持"}
	var result := parse(value)
	expect(result.ok and result.pose == value, "preserve IDs, links, metadata and order")
	expect(result.fade_in_seconds == 0.5, "default fade")
	for fade: Variant in [null, -1, 0, 0.25]:
		value.FadeInTime = fade
		result = parse(value)
		expect(result.ok and result.fade_in_seconds == (0.5 if fade == null or fade == -1 else fade), "SDK fade semantics")
	for wrong: Variant in ["fast", {}, true, 1e100]:
		value.FadeInTime = wrong
		rejected(value, "FadeInTime")
	value.erase("FadeInTime")
	for wrong: Variant in ["", null, 2, []]:
		var copy := value.duplicate(true)
		copy.Groups[0][0].Id = wrong
		rejected(copy, "Groups[0][0].Id")
	for wrong: Variant in ["", 2, {}]:
		var copy := value.duplicate(true)
		copy.Groups[0][0].Link = [wrong]
		rejected(copy, "Groups[0][0].Link[0]")
	rejected({"Groups": {}}, "Groups")
	rejected({"Groups": [2]}, "Groups[0]")
	rejected({"Groups": [[2]]}, "Groups[0][0]")
	rejected({"Groups": [[{"Id": "A", "Link": "B"}]]}, "Groups[0][0].Link")
	rejected({"Type": "Wrong", "Groups": []}, "Type")
	expect(parse({"Groups": []}).ok, "empty pose and absent Type")
	expect(parse({"Groups": [[]]}).ok, "empty group")
	expect(parse({"Groups": [[{"Id": "A"}, {"Id": "A", "Link": null}]]}).ok, "preserve repeated IDs and optional links")
	expect(not CubismManifestParser.parse_pose('{"Groups":[[{"Id":"A\\u0000"}]]}').ok, "NUL rejected")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest := CubismManifestParser.parse_manifest(FileAccess.get_file_as_string(fixture.model), fixture.model)
	var pose: String = manifest.manifest.FileReferences.get("Pose", "")
	if not pose.is_empty():
		expect(CubismManifestParser.parse_pose(FileAccess.get_file_as_string(pose)).ok, "real fixture pose")
	for failure: String in failures:
		printerr("POSE_PARSER_FAIL: ", failure)
	print("CUBISM_POSE_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_POSE_PARSER_PASS")
	quit(0 if failures.is_empty() else 1)
