# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var tracker := get_tree().root.find_child("CubismDependencies", true, false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	tracker.request_scan()
	for frame in 2000:
		await get_tree().process_frame
		if not tracker.get_status().busy:
			break
	var resource := ResourceLoader.load("res://tracked.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	var tracked := false
	for item: Dictionary in tracker.get_status().models:
		if item.resource == "res://tracked.res" and item.status == "current":
			tracked = true
	if resource == null or not tracked or tracker.get_status().busy or resource.dependency_fingerprints.get(fixture.changed_dependency) != fixture.expected_hash:
		printerr("DEPENDENCY_RESTART_FAILED: ", tracker.get_status())
		get_tree().quit(1)
		return
	print("CUBISM_DEPENDENCY_RESTART_PASS")
	get_tree().quit()
