extends RefCounted

static func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("CUBISM_LIFECYCLE_FAIL: " + message)
	return condition

static func _write(path: String, contents: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(contents)

static func _manifest(refs: Dictionary) -> void:
	_write("user://invalid.model3.json", JSON.stringify({"Version": 3, "FileReferences": refs}).to_utf8_buffer())

static func run(host: Node, fixture: Dictionary) -> bool:
	var tree: SceneTree = host.get_tree()
	var model := GDCubismUserModel.new()
	host.add_child(model)
	model.playback_process_mode = GDCubismUserModel.MANUAL
	if not _check(model.get_model_state() == GDCubismUserModel.UNLOADED, "new model state"):
		return false
	var signals: Dictionary = {"ready": 0, "failed": 0}
	model.model_ready.connect(func() -> void: signals.ready += 1)
	model.model_failed.connect(func(_error: Dictionary) -> void: signals.failed += 1)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.model))
	_write("user://valid.moc3", FileAccess.get_file_as_bytes(fixture.model.get_base_dir().path_join(manifest.FileReferences.Moc)))
	_write("user://empty.moc3", PackedByteArray())
	_write("user://bad.exp3.json", "{".to_utf8_buffer())
	_write("user://empty.exp3.json", PackedByteArray())
	_write("user://valid.exp3.json", FileAccess.get_file_as_bytes(fixture.model.get_base_dir().path_join(manifest.FileReferences.Expressions[0].File)))
	# Exported textures are imported resources, so raw FileAccess does not
	# necessarily return their original PNG bytes. Produce the private failure
	# fixture through the same Texture2D API in source and exported runs.
	var fixture_texture: Texture2D = load(fixture.model.get_base_dir().path_join(manifest.FileReferences.Textures[0]))
	if not _check(fixture_texture.get_image().save_png("user://valid.png") == OK, "could not prepare partial texture fixture"):
		return false
	var corrupt: PackedByteArray = []
	corrupt.resize(64)
	_write("user://corrupt.moc3", corrupt)
	var cases: Array[Dictionary] = [
		{"Moc": "missing.moc3"},
		{"Moc": "empty.moc3"},
		{"Moc": "corrupt.moc3"},
		{"Moc": "valid.moc3", "Expressions": [{"Name": "bad", "File": "bad.exp3.json"}]},
		{"Moc": "valid.moc3", "Expressions": [{"Name": "empty", "File": "empty.exp3.json"}]},
		{"Moc": "valid.moc3", "Expressions": [{"Name": "good", "File": "valid.exp3.json"}, {"Name": "bad", "File": "bad.exp3.json"}]},
		{"Moc": "valid.moc3", "Textures": ["valid.png", "missing.png"]},
		{"Moc": "valid.moc3", "Textures": ["script-bearing.tres"]},
	]
	for refs: Dictionary in cases:
		_manifest(refs)
		model.assets = "user://invalid.model3.json"
		if not _check(model.get_model_state() == GDCubismUserModel.LOAD_ERROR and not model.is_initialized(), "partial load remained ready"):
			return false
		var error: Dictionary = model.get_last_error()
		if not _check(error.code != OK and not error.message.is_empty() and not error.path.is_empty(), "missing structured failure"):
			return false
		await tree.process_frame
		await tree.process_frame
		model.unload_model()
		model.unload_model()
		if not _check(model.get_model_state() == GDCubismUserModel.DISPOSED and model.get_child_count() == 0, "partial load did not clean up"):
			return false
	if not _check(signals.failed == cases.size(), "failed signal count"):
		return false
	model.assets = fixture.model
	await tree.process_frame
	await tree.process_frame
	if not _check(signals.ready == 1 and model.get_last_error().is_empty(), "valid load did not recover"):
		return false
	# The queued ready/failure from a superseded load must not reach the new one.
	var ready_before: int = signals.ready
	model.assets = "user://invalid.model3.json"
	model.assets = fixture.model
	model.assets = fixture.model
	await tree.process_frame
	await tree.process_frame
	if not _check(signals.failed == cases.size() and signals.ready == ready_before + 1, "stale load signals escaped"):
		return false
	var retained: GDCubismParameter = model.get_parameters()[0]
	host.remove_child(model)
	if not _check(model.get_model_state() == GDCubismUserModel.READY and retained.is_valid(), "tree exit lost legacy native state"):
		return false
	host.add_child(model)
	if not _check(model.is_initialized() and model.get_parameters()[0] == retained, "tree reentry replaced legacy parameter"):
		return false
	retained.value = 99.0
	model.unload_model()
	if not _check(not retained.is_valid(), "explicit unload retained native parameter"):
		return false
	var cycles: int = 10
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--cycles="):
			cycles = int(argument.trim_prefix("--cycles="))
	for cycle: int in cycles:
		model.assets = fixture.model
		if not _check(model.is_initialized(), "repeated load " + str(cycle)):
			return false
		model.advance(1.0 / 60.0)
		model.unload_model()
		model.unload_model()
		if not _check(model.get_child_count() == 0, "renderer nodes survived unload"):
			return false
		# Let Redot drain deferred signals and rendering commands each cycle.
		await tree.process_frame
	model.free()
	var simultaneous: Array[GDCubismUserModel] = []
	for index: int in 20:
		var instance := GDCubismUserModel.new()
		instance.assets = fixture.model
		instance.playback_process_mode = GDCubismUserModel.MANUAL
		host.add_child(instance)
		simultaneous.append(instance)
		if not _check(instance.is_initialized(), "simultaneous instance " + str(index)):
			return false
	var untouched: float = simultaneous[1].get_parameters()[0].value
	simultaneous[0].get_parameters()[0].value = untouched + 0.1
	simultaneous[0].advance(1.0 / 60.0)
	if not _check(simultaneous[1].get_parameters()[0].value == untouched, "instances share mutable parameter state"):
		return false
	for instance: GDCubismUserModel in simultaneous:
		instance.free()
	simultaneous.clear()
	# Deferred signals are dispatched after SDK iteration and reject stale loads.
	var ready_free := GDCubismUserModel.new()
	host.add_child(ready_free)
	ready_free.model_ready.connect(func() -> void:
		host.remove_child(ready_free)
		ready_free.queue_free()
	)
	ready_free.assets = fixture.model
	await tree.process_frame
	await tree.process_frame
	if not _check(not is_instance_valid(ready_free), "ready callback could not delete model"):
		return false
	var motion_free := GDCubismUserModel.new()
	host.add_child(motion_free)
	motion_free.assets = fixture.model
	motion_free.playback_process_mode = GDCubismUserModel.MANUAL
	motion_free.motion_finished.connect(func() -> void:
		host.remove_child(motion_free)
		motion_free.queue_free()
	)
	motion_free.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
	for frame: int in int(ceil((float(fixture.motion_duration) + 2.0) * 60.0)):
		motion_free.advance(1.0 / 60.0)
	await tree.process_frame
	await tree.process_frame
	if not _check(not is_instance_valid(motion_free), "motion callback could not delete model"):
		return false
	var custom_model := GDCubismUserModel.new()
	var effect := GDCubismEffectCustom.new()
	custom_model.add_child(effect)
	host.add_child(custom_model)
	custom_model.assets = fixture.model
	custom_model.playback_process_mode = GDCubismUserModel.MANUAL
	var reloaded: Dictionary = {"done": false}
	effect.cubism_process.connect(func(owner: GDCubismUserModel, _delta: float) -> void:
		if not reloaded.done:
			reloaded.done = true
			owner.assets = fixture.model
	)
	custom_model.advance(1.0 / 60.0)
	if not _check(reloaded.done and custom_model.is_initialized(), "custom callback reload failed"):
		return false
	effect.cubism_process.connect(func(owner: GDCubismUserModel, _delta: float) -> void: owner.queue_free(), CONNECT_ONE_SHOT)
	custom_model.advance(1.0 / 60.0)
	await tree.process_frame
	await tree.process_frame
	if not _check(not is_instance_valid(custom_model), "custom callback deletion was not deferred safely"):
		return false
	print("CUBISM_LIFECYCLE_PASS cycles=" + str(cycles))
	return true
