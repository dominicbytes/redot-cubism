# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
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
		for editor_class: String in ["CubismExportPlugin", "CubismExportValidator", "CubismModelImporter", "CubismDependencyTracker", "CubismModelInspector", "CubismModelSummary", "GDCubismPlugin"]:
			if ClassDB.class_exists(editor_class):
				printerr("EDITOR_CLASS_PRESENT_IN_TEMPLATE: ", editor_class)
				quit(1)
				return
	var runtime := GDCubismUserModel.new()
	runtime.playback_process_mode = GDCubismUserModel.MANUAL
	root.add_child(runtime)
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
	var before := PackedFloat64Array()
	for parameter: GDCubismParameter in runtime.get_parameters():
		before.append(parameter.value)
	var moved := false
	for frame in 120:
		runtime.advance(1.0 / 60.0)
		var parameters := runtime.get_parameters()
		for index in parameters.size():
			moved = moved or absf(parameters[index].value - before[index]) > 0.0001
	runtime.free()
	if not moved:
		printerr("IMPORTED_RESOURCE_MOTION_DID_NOT_MOVE")
		quit(1)
		return
	var high := load("res://mask-quality-model.res") as CubismModelResource
	if high == null or high.get_mask_quality() != 2:
		printerr("IMPORTED_MASK_QUALITY_MISSING")
		quit(1)
		return
	var preferred := CubismModel2D.new()
	preferred.playback_process_mode = CubismModel2D.MANUAL
	root.add_child(preferred)
	var error := preferred.load_model(high)
	var native := preferred.get_child(0, true) as GDCubismUserModel
	var inherited := error == OK and preferred.is_ready() and preferred.mask_quality == CubismModel2D.MASK_MODEL and native.mask_viewport_size == 2048
	preferred.free()
	if not inherited:
		printerr("IMPORTED_MASK_QUALITY_NOT_APPLIED")
		quit(1)
		return
	print("CUBISM_IMPORTED_RESOURCE_PASS")
	quit()
