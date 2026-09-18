# SPDX-License-Identifier: MIT
extends SceneTree

const MODEL := "res://fixture/Haru.model3.json"

func _initialize() -> void:
	_run.call_deferred()

func _values(model: GDCubismUserModel) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for parameter: GDCubismParameter in model.get_parameters():
		result.append(parameter.value)
	return result

func _moved(before: PackedFloat64Array, after: PackedFloat64Array) -> bool:
	for index: int in before.size():
		if absf(before[index] - after[index]) > 0.0001:
			return true
	return false

func _masks_active(model: GDCubismUserModel) -> bool:
	var found := false
	for child: Node in model.get_children():
		if child is SubViewport:
			found = true
			if child.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
				return false
	return found

func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	var effect := GDCubismEffectCustom.new()
	model.add_child(effect)
	host.add_child(model)
	model.assets = MODEL
	if not model.is_initialized():
		printerr("CUBISM_LEGACY_PARITY_FAIL: Haru fixture did not load")
		quit(2)
		return
	var steps: Array[float] = []
	effect.cubism_process.connect(func(_owner: GDCubismUserModel, delta: float) -> void: steps.append(delta))
	model.advance(0.5)
	var full_delta: bool = steps.size() == 1 and is_equal_approx(steps[0], 0.5)
	var callbacks_before: int = steps.size()
	paused = true
	model.advance(1.0 / 60.0)
	paused = false
	var paused_step: bool = steps.size() == callbacks_before + 1
	var retained: GDCubismParameter = model.get_parameters()[0]
	var handle: GDCubismMotionQueueEntryHandle = model.start_motion("Idle", 0, GDCubismUserModel.PRIORITY_FORCE)
	model.advance(1.0 / 60.0)
	host.remove_child(model)
	var retained_after_detach: bool = retained.is_valid()
	var playback_after_detach: bool = not handle.is_finished()
	host.add_child(model)
	var same_parameter: bool = model.get_parameters()[0] == retained
	var masks_after_reentry: bool = _masks_active(model)
	var restart: Dictionary = {"callbacks": 0, "handle": null}
	model.motion_finished.connect(func() -> void:
		restart.callbacks += 1
		restart.handle = model.start_motion("Idle", 0, GDCubismUserModel.PRIORITY_FORCE)
	)
	model.advance(12.0)
	await process_frame
	var viewer_restart: bool = restart.callbacks == 1 and restart.handle != null and not restart.handle.is_finished()
	model.free()

	var off_tree := GDCubismUserModel.new()
	off_tree.playback_process_mode = GDCubismUserModel.MANUAL
	off_tree.assets = MODEL
	if not off_tree.is_initialized():
		printerr("CUBISM_LEGACY_PARITY_FAIL: off-tree Haru fixture did not load")
		off_tree.free()
		host.free()
		quit(2)
		return
	off_tree.physics_evaluate = false
	off_tree.pose_update = false
	off_tree.start_motion("Idle", 0, GDCubismUserModel.PRIORITY_FORCE)
	var before: PackedFloat64Array = _values(off_tree)
	for step: int in 60:
		off_tree.advance(1.0 / 60.0)
	var off_tree_step: bool = _moved(before, _values(off_tree))
	off_tree.free()
	host.free()
	var result := {"full_delta": full_delta, "paused_step": paused_step,
		"retained_after_detach": retained_after_detach,
		"playback_after_detach": playback_after_detach,
		"same_parameter_after_reentry": same_parameter,
		"masks_after_reentry": masks_after_reentry,
		"viewer_restart": viewer_restart,
		"off_tree_step": off_tree_step}
	print("CUBISM_LEGACY_PARITY:" + JSON.stringify(result))
	for value: bool in result.values():
		if not value:
			quit(1)
			return
	quit(0)
