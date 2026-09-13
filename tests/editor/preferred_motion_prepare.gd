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
			"Meta": {"Duration": 1.0, "Fps": 20.0, "Loop": false, "AreBeziersRestricted": true,
				"CurveCount": 1, "TotalSegmentCount": 1, "TotalPointCount": 2,
				"UserDataCount": events.size(), "TotalUserDataSize": size},
			"Curves": [{"Target": "Parameter", "Id": "ParamAngleX", "Segments": [0.0, 0.0, 0, 1.0, 20.0 if index == 0 else -20.0]}],
			"UserData": events})
		entries.append({"File": filename, "FadeInTime": 0.0, "FadeOutTime": 0.2})
	manifest.FileReferences.Motions = {"Cue": entries}
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
