# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var entries: Array = []
	for index in 2:
		var filename := "test-cue-" + str(index) + ".motion3.json"
		var events := [{"Time": 0.0, "Value": "start"}, {"Time": 0.5, "Value": "半分_😀"}, {"Time": 1.0, "Value": "end"}]
		var size := 0
		for event: Dictionary in events:
			size += str(event.Value).to_utf8_buffer().size()
		_write(source.get_base_dir().path_join(filename), {
			"Version": 3,
			"Meta": {"Duration": 1.0, "Fps": 20.0, "Loop": index == 1, "AreBeziersRestricted": true,
				"CurveCount": 1, "TotalSegmentCount": 1, "TotalPointCount": 2,
				"UserDataCount": events.size(), "TotalUserDataSize": size},
			"Curves": [{"Target": "Parameter", "Id": "ParamAngleX", "Segments": [0.0, 0.0, 0, 1.0, 20.0 if index == 0 else -20.0]}],
			"UserData": events})
		entries.append({"File": filename, "FadeInTime": 0.0, "FadeOutTime": 0.2})
	manifest.FileReferences.Motions = {"Cue": entries}
	_write(source.get_base_dir().path_join("test-long-cue.motion3.json"), {
		"Version": 3, "Meta": {"Duration": 30.0, "Fps": 60.0, "Loop": false, "AreBeziersRestricted": true,
			"CurveCount": 2, "TotalSegmentCount": 3, "TotalPointCount": 5, "UserDataCount": 0, "TotalUserDataSize": 0},
		"Curves": [{"Target": "Parameter", "Id": "ParamAngleX", "Segments": [0.0, 0.0, 0, 30.0, 20.0]},
			{"Target": "Parameter", "Id": "ParamMouthOpenY", "Segments": [0.0, 0.0, 0, 15.0, 1.0, 0, 30.0, 0.0]}], "UserData": []})
	manifest.FileReferences.Motions["LongCue"] = [{"File": "test-long-cue.motion3.json", "FadeInTime": 0.0, "FadeOutTime": 0.0}]
	_write(source.get_base_dir().path_join("test-eyes.motion3.json"), {
		"Version": 3, "Meta": {"Duration": 1.0, "Fps": 20.0, "Loop": true, "AreBeziersRestricted": true,
			"CurveCount": 2, "TotalSegmentCount": 2, "TotalPointCount": 4, "UserDataCount": 0, "TotalUserDataSize": 0},
		"Curves": [{"Target": "Parameter", "Id": "ParamEyeLOpen", "Segments": [0.0, 0.25, 0, 1.0, 0.25]},
			{"Target": "Parameter", "Id": "ParamEyeROpen", "Segments": [0.0, 0.25, 0, 1.0, 0.25]}], "UserData": []})
	manifest.FileReferences.Motions["Eyes"] = [{"File": "test-eyes.motion3.json", "FadeInTime": 0.0, "FadeOutTime": 0.2}]
	for group: String in ["Lips", "ModelLips"]:
		var filename := "test-" + group + ".motion3.json"
		_write(source.get_base_dir().path_join(filename), {
			"Version": 3, "Meta": {"Duration": 1.0, "Fps": 20.0, "Loop": true, "AreBeziersRestricted": true,
				"CurveCount": 1, "TotalSegmentCount": 1, "TotalPointCount": 2, "UserDataCount": 0, "TotalUserDataSize": 0},
			"Curves": [{"Target": "Parameter" if group == "Lips" else "Model", "Id": "ParamMouthOpenY" if group == "Lips" else "LipSync",
				"Segments": [0.0, 0.25, 0, 1.0, 0.25]}], "UserData": []})
		manifest.FileReferences.Motions[group] = [{"File": filename, "FadeInTime": 0.0, "FadeOutTime": 0.2}]
	var expressions: Array = []
	for blend: String in ["Add", "Multiply", "Overwrite"]:
		var filename := "test-" + blend + ".exp3.json"
		_write(source.get_base_dir().path_join(filename), {
			"Type": "Live2D Expression", "FadeInTime": 0.4, "FadeOutTime": 0.2,
			"Parameters": [{"Id": "ParamAngleX", "Blend": blend, "Value": 10.0 if blend == "Add" else (2.0 if blend == "Multiply" else -10.0)}]})
		expressions.append({"Name": blend, "File": filename})
	_write(source.get_base_dir().path_join("test-mouth.exp3.json"), {
		"Type": "Live2D Expression", "FadeInTime": 0.0, "FadeOutTime": 0.2,
		"Parameters": [{"Id": "ParamMouthOpenY", "Blend": "Overwrite", "Value": 0.3}]})
	expressions.append({"Name": "Mouth", "File": "test-mouth.exp3.json"})
	manifest.FileReferences.Expressions = expressions
	_write(source, manifest)
	var error := CubismModelImporter.import_model(source, "res://imported-model.res")
	if error != OK:
		printerr("Motion fixture import failed: ", error)
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	print("CUBISM_PREFERRED_MOTION_PREPARED")
	get_tree().quit()
