# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	var failures: Array[String] = []
	var checks := 0
	var cases := {"unicode": true, "bom": true, "double-bom": true, "empty": true, "exact-limit": true, "too-large": false, "nul": false, "overlong": false, "overlong-three": false, "overlong-four": false, "surrogate": false, "too-high": false, "bad-leader": false, "stray-continuation": false, "truncated": false, "bad-continuation": false}
	for name: String in cases:
		var result := CubismManifestParser.read_project_json("res://paths/json/" + name + ".json")
		checks += 1
		if result.ok != cases[name] or (not result.ok and (result.text != "" or result.message == "")):
			failures.append(name)
	var unicode := CubismManifestParser.read_project_json("res://paths/json/unicode.json")
	checks += 1
	if unicode.text != '{"text":"内部😀"}':
		failures.append("Unicode preserved")
	checks += 1
	if unicode.sha256 != FileAccess.get_sha256("res://paths/json/unicode.json") or unicode.byte_length != unicode.text.to_utf8_buffer().size():
		failures.append("Raw byte fingerprint and length")
	var bom := CubismManifestParser.read_project_json("res://paths/json/bom.json")
	checks += 1
	if bom.text != "{}":
		failures.append("BOM stripped")
	checks += 1
	if bom.sha256 != FileAccess.get_sha256("res://paths/json/bom.json") or bom.byte_length != 5:
		failures.append("Fingerprint includes original BOM bytes")
	var double_bom := CubismManifestParser.read_project_json("res://paths/json/double-bom.json")
	checks += 1
	if double_bom.text != "\ufeff{}":
		failures.append("Only one initial BOM stripped")
	for path: String in ["res://paths/outside-link.txt", "res://paths/dangling-link.txt", "res://paths/loop.txt", "res://paths", "res://paths/missing.txt", "res://../outside.txt", "user://a.json"]:
		var result := CubismManifestParser.read_project_json(path)
		checks += 1
		if result.ok or result.text != "":
			failures.append("Rejected path " + path)
	var link := CubismManifestParser.read_project_json("res://paths/inside-link.txt")
	checks += 1
	if not link.ok or link.text != "inside":
		failures.append("Contained symlink read")
	for failure: String in failures:
		printerr("JSON_READ_FAIL: ", failure)
	print("CUBISM_JSON_READ_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_JSON_READ_PASS")
	quit(0 if failures.is_empty() else 1)
