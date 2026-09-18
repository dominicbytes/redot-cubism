# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	# Fixtures are created by the physical-path runner, outside imported assets.
	var cases := {
		"res://paths/inside.txt": "file",
		"res://paths/内部.txt": "file",
		"res://paths/missing.txt": "missing",
		"res://paths/missing/child.txt": "missing",
		"res://paths": "error",
		"res://paths/inside-link.txt": "file",
		"res://paths/outside-link.txt": "unsafe",
		"res://paths/outside-directory/missing.txt": "unsafe",
		"res://paths/sibling-link.txt": "unsafe",
		"res://paths/dangling-link.txt": "error",
		"res://paths/loop.txt": "error",
		"res://../outside.txt": "unsafe",
		"res://paths/../inside.txt": "unsafe",
		"res://paths//inside.txt": "unsafe",
		"res://paths\\inside.txt": "unsafe",
		"res://paths/inside.txt:stream": "unsafe",
		"user://inside.txt": "unsafe",
		"/etc/passwd": "unsafe",
	}
	var failures := 0
	for path: String in cases:
		var result := CubismManifestParser.validate_project_file(path)
		if result.status != cases[path]:
			failures += 1
			printerr("PATH_CHECK_FAIL ", path, " expected=", cases[path], " actual=", result)
	print("CUBISM_PATH_CHECKS cases=", cases.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)
