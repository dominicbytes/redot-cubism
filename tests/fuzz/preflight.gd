# SPDX-License-Identifier: MIT
extends SceneTree


func _initialize() -> void:
	for name: String in ["CubismManifestParser", "CubismModelFactory", "CubismMotionDescriptor", "CubismExpressionDescriptor"]:
		if not ClassDB.class_exists(name):
			printerr("FUZZ_PREFLIGHT_MISSING_CLASS:", name)
			quit(1)
			return
	print("FUZZ_PREFLIGHT_PASS")
	quit(0)
