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
	tracker.request_scan()
	for frame in 2000:
		await get_tree().process_frame
		if not tracker.get_status().busy:
			break
	var model := ResourceLoader.load("res://options-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	assert(model != null and not tracker.get_status().busy)
	assert(model.layout.get("x") == 0.625)
	assert(model.motion_groups.is_empty() and model.expressions.is_empty())
	assert(model.import_options["validation/strict_optional_files"] == true)
	assert(model.import_options["motions/import_manifest_motions"] == false)
	assert(model.import_options["expressions/import"] == false)
	assert(model.get_mask_quality() == 0)
	assert(model.get_premultiplied_alpha())
	for texture: Texture2D in model.textures:
		assert(texture.get_meta("cubism_premultiplied_alpha", false) == true)
	if "--cleanup-options" in OS.get_cmdline_user_args():
		# These extra models share source assets with the independent destructive
		# dependency tests. Finish option/cache coverage, then remove our fixtures.
		var variant := model.source_model_path
		for path: String in ["res://options-model.res", "res://menu-options-model.res", variant]:
			assert(DirAccess.remove_absolute(path) == OK)
			EditorInterface.get_resource_filesystem().update_file(path)
	print("CUBISM_IMPORT_OPTIONS_RESTART_PASS")
	get_tree().quit()
