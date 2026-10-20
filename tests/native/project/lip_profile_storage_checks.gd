# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func range_matches(profile: CubismLipSyncProfile, low: float, high: float) -> bool:
	return profile != null and profile.minimum == low and profile.maximum == high

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for bounds: Array in [[2.0, 3.0], [-3.0, -2.0]]:
		var profile := CubismLipSyncProfile.new()
		if bounds[0] > 0:
			profile.set_maximum(bounds[1])
			profile.set_minimum(bounds[0])
		else:
			profile.set_minimum(bounds[0])
			profile.set_maximum(bounds[1])
		expect(profile.set_minimum(bounds[1] + 1) == ERR_INVALID_PARAMETER and profile.set_maximum(bounds[0] - 1) == ERR_INVALID_PARAMETER, "public range setters retain validation")
		expect(range_matches(profile.duplicate(), bounds[0], bounds[1]), "duplicate preserves complete range")
		for extension: String in ["tres", "res"]:
			var path := "user://safety-profile." + extension
			expect(ResourceSaver.save(profile, path) == OK, "save range " + extension)
			expect(range_matches(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE), bounds[0], bounds[1]), "resource round trip " + extension)
		for reverse: bool in [false, true]:
			var text := '[gd_resource type="CubismLipSyncProfile" format=3]\n[resource]\n'
			text += ("maximum = %s\nminimum = %s\n" % [bounds[1], bounds[0]]) if reverse else ("minimum = %s\nmaximum = %s\n" % [bounds[0], bounds[1]])
			var legacy_file := FileAccess.open("user://safety-legacy.tres", FileAccess.WRITE)
			legacy_file.store_string(text)
			legacy_file.close()
			expect(range_matches(ResourceLoader.load("user://safety-legacy.tres", "", ResourceLoader.CACHE_MODE_IGNORE), bounds[0], bounds[1]), "legacy endpoint order restores a valid pair")
		var component := CubismLipSync.new()
		component.profile = profile
		var scene := PackedScene.new()
		expect(scene.pack(component) == OK and ResourceSaver.save(scene, "user://safety-profile.tscn") == OK, "save profile scene")
		component.free()
		var packed := ResourceLoader.load("user://safety-profile.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var restored := packed.instantiate() as CubismLipSync
		expect(range_matches(restored.profile, bounds[0], bounds[1]), "scene round trip preserves range")
		restored.free()
	await process_frame
	print("CUBISM_LIP_PROFILE_STORAGE checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("LIP_PROFILE_STORAGE_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_LIP_PROFILE_STORAGE_PASS")
	quit(0 if failures.is_empty() else 1)
