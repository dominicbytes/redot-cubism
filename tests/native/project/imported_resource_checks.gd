# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	var model := ResourceLoader.load("res://imported-model.res", "CubismModelResource")
	if not model is CubismModelResource:
		printerr("IMPORTED_RESOURCE_MISSING")
		quit(1)
		return
	if model.source_hash != FileAccess.get_sha256(model.source_model_path) or model.textures.is_empty() or model.motion_groups.is_empty():
		printerr("IMPORTED_RESOURCE_DATA_MISMATCH")
		quit(1)
		return
	if not OS.has_feature("editor"):
		for editor_class: String in ["CubismModelImporter", "CubismDependencyTracker", "CubismModelInspector", "CubismModelSummary", "GDCubismPlugin"]:
			if ClassDB.class_exists(editor_class):
				printerr("EDITOR_CLASS_PRESENT_IN_TEMPLATE: ", editor_class)
				quit(1)
				return
	var runtime := GDCubismUserModel.new()
	runtime.playback_process_mode = GDCubismUserModel.MANUAL
	runtime.model = model
	if not runtime.is_initialized():
		printerr("IMPORTED_RESOURCE_RUNTIME_FAILED: ", runtime.get_last_error())
		runtime.free()
		quit(1)
		return
	var group: String = model.motion_groups.keys()[0]
	var motion := runtime.start_motion(group, 0, GDCubismUserModel.PRIORITY_FORCE)
	if motion.get_error() != OK:
		printerr("IMPORTED_RESOURCE_MOTION_FAILED")
		runtime.free()
		quit(1)
		return
	for frame in 120:
		runtime.advance(1.0 / 60.0)
	runtime.free()
	print("CUBISM_IMPORTED_RESOURCE_PASS")
	quit()
