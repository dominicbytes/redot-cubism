extends RefCounted

static func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("CUBISM_HANDLE_FAIL: " + message)
	return condition

static func run(host: Node, fixture: Dictionary) -> bool:
	var tree: SceneTree = host.get_tree()
	var model := GDCubismUserModel.new()
	host.add_child(model)
	model.playback_process_mode = GDCubismUserModel.MANUAL
	var rejected: GDCubismMotionQueueEntryHandle = model.start_motion("absent", 0, GDCubismUserModel.PRIORITY_NORMAL)
	if not _check(rejected.is_finished() and rejected.get_error() == FAILED, "unloaded rejection is not terminal"):
		return false
	model.assets = fixture.model
	var reasons: Array[int] = [GDCubismMotionQueueEntryHandle.STOPPED, GDCubismMotionQueueEntryHandle.INTERRUPTED,
		GDCubismMotionQueueEntryHandle.UNLOADED, GDCubismMotionQueueEntryHandle.RELOADED, GDCubismMotionQueueEntryHandle.COMPLETED]
	var retained: Array[GDCubismMotionQueueEntryHandle] = []
	for reason: int in reasons:
		if not model.is_initialized():
			model.assets = fixture.model
		var handle: GDCubismMotionQueueEntryHandle = model.start_motion_loop(fixture.motion_group, 0,
			GDCubismUserModel.PRIORITY_FORCE, reason != GDCubismMotionQueueEntryHandle.COMPLETED, true)
		retained.append(handle)
		var observed: Array[int] = []
		handle.finished.connect(func(value: int) -> void: observed.append(value))
		if not _check(handle.get_error() == OK and not handle.is_finished(), "accepted handle not playing"):
			return false
		# Failed reservations must not terminate the accepted motion.
		rejected = model.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_IDLE)
		if not _check(rejected.is_finished() and rejected.get_error() == FAILED and not handle.is_finished(), "rejected reservation changed active handle"):
			return false
		match reason:
			GDCubismMotionQueueEntryHandle.STOPPED:
				model.stop_motion()
				model.stop_motion()
			GDCubismMotionQueueEntryHandle.INTERRUPTED:
				model.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
			GDCubismMotionQueueEntryHandle.UNLOADED:
				model.unload_model()
				model.unload_model()
			GDCubismMotionQueueEntryHandle.RELOADED:
				model.assets = fixture.model
			GDCubismMotionQueueEntryHandle.COMPLETED:
				for frame: int in int(ceil((float(fixture.motion_duration) + 2.0) * 60.0)):
					model.advance(1.0 / 60.0)
		if not _check(handle.is_finished() and handle.get_reason() == reason, "terminal reason " + str(reason)):
			return false
		await tree.process_frame
		await tree.process_frame
		if not _check(observed == [reason], "terminal signal did not fire exactly once"):
			return false
		model.stop_motion()
	var destroyed: GDCubismMotionQueueEntryHandle = model.start_motion_loop(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE, true, true)
	var destroyed_signals: Array[int] = []
	destroyed.finished.connect(func(reason: int) -> void: destroyed_signals.append(reason))
	model.free()
	await tree.process_frame
	await tree.process_frame
	if not _check(destroyed.get_reason() == GDCubismMotionQueueEntryHandle.MODEL_DESTROYED and destroyed_signals == [GDCubismMotionQueueEntryHandle.MODEL_DESTROYED], "destruction lost terminal result"):
		return false
	for index: int in reasons.size():
		if not _check(retained[index].get_reason() == reasons[index], "later playback rewrote a terminal handle"):
			return false
	print("CUBISM_HANDLE_PASS")
	return true
