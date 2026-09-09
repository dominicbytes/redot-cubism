# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func minimal() -> Dictionary:
	return {"Version": 3, "FileReferences": {"Moc": "Hero.moc3", "Textures": ["textures/A.png"]}}

func parse(value: Dictionary, source := "res://models/Hero.model3.json") -> Dictionary:
	return CubismManifestParser.parse_manifest(JSON.stringify(value), source)

func rejected(value: Dictionary, path: String, label: String) -> void:
	var result := parse(value)
	var found := false
	for diagnostic: Dictionary in result.diagnostics:
		found = found or diagnostic.path == path
	expect(not result.ok and result.manifest.is_empty() and found, label)

func _initialize() -> void:
	var input := minimal()
	input["Metadata"] = {"Author": "作者", "Future": [1, true]}
	input.FileReferences.Textures = ["textures/Z.png", "../共通/A.png", "textures/Z.png"]
	input.FileReferences.Motions = {"Idle": [{"File": "idle.motion3.json", "Sound": "voice.ogg", "FadeInTime": -1}]}
	input.FileReferences.Expressions = [{"Name": "笑顔", "File": "smile.exp3.json"}]
	input.Layout = {"CenterX": 0.5, "Width": 2.0}
	var result := parse(input)
	expect(result.ok, "valid manifest")
	expect(result.manifest.Metadata == JSON.parse_string(JSON.stringify(input)).Metadata, "unknown metadata preserved")
	expect(result.manifest.FileReferences.Textures == ["res://models/textures/Z.png", "res://共通/A.png", "res://models/textures/Z.png"], "texture order and Unicode preserved")
	expect(result.manifest.FileReferences.Motions.Idle[0].File == "res://models/idle.motion3.json", "motion normalization")
	var sorted: PackedStringArray = result.dependencies.duplicate()
	sorted.sort()
	expect(sorted == result.dependencies and sorted.size() == 6, "dependencies sorted and deduplicated")
	expect(input.FileReferences.Textures[0] == "textures/Z.png", "input remains unchanged")
	expect(parse(minimal(), "res://Hero.model3.json").manifest.FileReferences.Moc == "res://Hero.moc3", "root manifest")
	for unsafe: String in ["../../escape.moc3", "/absolute.moc3", "C:\\escape.moc3", "\\\\server\\file.moc3", "https://host/file.moc3", "res://elsewhere.moc3", "bad\nname.moc3", "", "file.gd"]:
		var value := minimal()
		value.FileReferences.Moc = unsafe
		rejected(value, "FileReferences.Moc", "unsafe path: " + unsafe.c_escape())
	expect(not CubismManifestParser.parse_manifest('{"Version":3,"FileReferences":{"Moc":"bad\\u0000.moc3","Textures":[]}}', "res://Hero.model3.json").ok, "NUL escape rejected before lossy decoding")
	var backslashes := minimal()
	backslashes.FileReferences.Moc = "sub\\..\\Hero.moc3"
	expect(parse(backslashes).manifest.FileReferences.Moc == "res://models/Hero.moc3", "relative backslash normalization")
	for extension: String in ["tres", "res", "tscn", "scn", "gd", "svg"]:
		var value := minimal()
		value.FileReferences.Textures = ["asset." + extension]
		rejected(value, "FileReferences.Textures[0]", "unsafe texture extension " + extension)
	for version: Variant in [null, "3", 2, 4, 3.5, true]:
		var value := minimal()
		value.Version = version
		rejected(value, "Version", "unsupported version " + str(version))
	for field: String in ["Textures", "Expressions", "Motions", "Physics", "Pose", "DisplayInfo", "UserData"]:
		var value := minimal()
		value.FileReferences[field] = 123
		rejected(value, "FileReferences." + field, "wrong type " + field)
	var duplicate := minimal()
	duplicate.FileReferences.Expressions = [{"Name": "Same", "File": "a.exp3.json"}, {"Name": "Same", "File": "b.exp3.json"}]
	rejected(duplicate, "FileReferences.Expressions[1].Name", "duplicate expression")
	var sound := minimal()
	sound.FileReferences.Motions = {"TapBody": [{"File": "tap.motion3.json", "Sound": "script.tres"}]}
	rejected(sound, "FileReferences.Motions.TapBody[0].Sound", "sound rejected before resource loading")
	var fade := minimal()
	fade.FileReferences.Motions = {"Idle": [{"File": "idle.motion3.json", "FadeInTime": "slow"}]}
	rejected(fade, "FileReferences.Motions.Idle[0].FadeInTime", "fade must be numeric")
	for field: String in ["Groups", "HitAreas", "Layout"]:
		var value := minimal()
		value[field] = "wrong"
		rejected(value, field, "metadata type " + field)
	var huge := minimal()
	huge.FileReferences.Textures = []
	for i: int in 65:
		huge.FileReferences.Textures.append(str(i) + ".png")
	rejected(huge, "FileReferences.Textures", "texture count bound")
	expect(not CubismManifestParser.parse_manifest("[]", "res://Hero.model3.json").ok, "non-object JSON")
	expect(not CubismManifestParser.parse_manifest("{broken", "res://Hero.model3.json").ok, "malformed JSON")
	expect(not parse(minimal(), "res://../Hero.model3.json").ok, "source path escape")
	var oversized := minimal()
	oversized.Extra = "x".repeat(4097)
	expect(not parse(oversized).ok, "string length bound")
	var nested := minimal()
	var cursor: Dictionary = nested
	for i: int in 34:
		cursor["child"] = {}
		cursor = cursor.child
	expect(not parse(nested).ok, "nesting bound")
	for failure: String in failures:
		printerr("MANIFEST_CHECK_FAIL: ", failure)
	print("MANIFEST_CHECKS: ", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_MANIFEST_PASS cases=", checks)
	quit(0 if failures.is_empty() else 1)
