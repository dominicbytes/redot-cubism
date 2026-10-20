# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var resource := load("res://factory-model.res") as CubismModelResource
	var eyes := resource.eye_blink_parameter_ids
	expect(not eyes.is_empty(), "fixture supplies blink parameters")
	var curves: Array[Dictionary] = []
	for id: String in eyes:
		curves.append({"Target": "Parameter", "Id": id, "Segments": [0.0, 0.25, 0, 1.0, 0.25]})
	var motion_path: String = fixture.model.get_base_dir().path_join("legacy-eyes.motion3.json")
	var file := FileAccess.open(motion_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"Version": 3, "Meta": {"Duration": 1.0, "Fps": 60.0, "Loop": true,
		"AreBeziersRestricted": true, "CurveCount": curves.size(), "TotalSegmentCount": curves.size(),
		"TotalPointCount": curves.size() * 2, "UserDataCount": 0, "TotalUserDataSize": 0}, "Curves": curves, "UserData": []}))
	file.close()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.model))
	manifest.FileReferences.Motions = {"Eyes": [{"File": motion_path.get_file(), "FadeInTime": 0.0, "FadeOutTime": 0.0}]}
	var manifest_path: String = fixture.model.get_base_dir().path_join("legacy-eyes.model3.json")
	file = FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	var built := CubismModelFactory.build(manifest_path)
	expect(built.ok, "synthetic authored-eye fixture assembled")
	if built.ok:
		var model := GDCubismUserModel.new()
		model.playback_process_mode = GDCubismUserModel.MANUAL
		model.physics_evaluate = false
		model.pose_update = false
		var blink := GDCubismEffectEyeBlink.new()
		model.add_child(blink)
		root.add_child(model)
		# Exercise both the resource and retained raw-JSON legacy load paths.
		for raw in [false, true]:
			if raw: model.assets = manifest_path
			else: model.model = built.model
			expect(model.is_initialized(), "legacy fixture loads")
			if not model.is_initialized(): continue
			var handle := model.start_motion_loop("Eyes", 0, GDCubismUserModel.PRIORITY_FORCE, true, false)
			expect(handle.get_error() == OK, "authored-eye motion starts")
			for step in 10:
				model.advance(1.0 / 60.0)
				for id: String in eyes:
					expect(is_equal_approx(model.get(id), 0.25), "motion-authored eye preserved: " + id)
			model.stop_motion()
			model.advance(0.016)
			for id: String in eyes:
				expect(is_equal_approx(model.get(id), 1.0), "automatic blink resumes without primary motion: " + id)
		model.free()
	DirAccess.remove_absolute(manifest_path)
	DirAccess.remove_absolute(motion_path)
	for failure in failures: printerr("CUBISM_LEGACY_EYE_BLINK_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_LEGACY_EYE_BLINK_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
