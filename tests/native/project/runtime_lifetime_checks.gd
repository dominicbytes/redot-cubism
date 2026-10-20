# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func wave() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(16000)
	stream.data = data
	return stream

func pair() -> Dictionary:
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	root.add_child(model)
	expect(model.load_model(resource) == OK, "safety fixture loads")
	var controller := CubismCharacterController.new()
	controller.manual_process = true
	controller.manual_audio_clock = true
	root.add_child(controller)
	expect(controller.set_target_model(model) == OK, "safety target attaches")
	return {"model": model, "controller": controller}

func dispose(value: Dictionary) -> void:
	if is_instance_valid(value.controller): value.controller.free()
	if is_instance_valid(value.model): value.model.free()

func churn() -> void:
	# Lifetime assertions resolve objects by ID; none dereference deleted nodes.
	for index in 20:
		var node := Node.new()
		node.free()

func effect(model: CubismModel2D, name: String, priority: int, callback: Callable, flags := 0) -> void:
	var item := CubismEffect.new()
	item.name = name
	item.effect_priority = priority
	model.add_child(item)
	item.effect_process.connect(callback, flags)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res")
	for child: String in ["Voice", "LipSync"]:
		for during: bool in [false, true]:
			var current := pair()
			var cue: CubismSpeechHandle
			if during: cue = current.controller.speak(wave(), &"Cue/0", &"", CubismLipSyncProfile.new())
			current.controller.get_node(child).free()
			churn()
			if during:
				current.controller.paused = true
				current.controller.advance(0.05)
				expect(cue.is_finished() and cue.get_error() == ERR_UNCONFIGURED, "deleted child fails cue: " + child)
			else:
				cue = current.controller.speak(wave(), &"Cue/0", &"", CubismLipSyncProfile.new())
				expect(cue.is_finished() and cue.get_error() == ERR_UNCONFIGURED, "deleted child rejects speak: " + child)
			current.controller.stop_speaking(0)
			dispose(current)
		# Deletion from a synchronous effect exercises the in-flight tick too.
		var current := pair()
		var cue: CubismSpeechHandle = current.controller.speak(wave(), &"Cue/0")
		effect(current.model, "DeleteChild", 0, func(_model: CubismModel2D, _delta: float):
			current.controller.get_node(child).free(), CONNECT_ONE_SHOT)
		current.controller.submit_audio_clock(0.1)
		current.controller.advance(0.05)
		current.controller.advance(0.05)
		expect(cue.is_finished() and cue.get_error() == ERR_UNCONFIGURED, "callback child deletion fails safely: " + child)
		dispose(current)
	for during: bool in [false, true]:
		var current := pair()
		current.model.debug_draw_bounds = true
		var old_id: int = current.model.get_node("CubismDebugOverlay").get_instance_id()
		var cue: CubismSpeechHandle
		if during: cue = current.controller.speak(wave(), &"Cue/0")
		current.model.get_node("CubismDebugOverlay").free()
		churn()
		current.model.debug_draw_hit_areas = true
		expect(current.model.get_node("CubismDebugOverlay").get_instance_id() != old_id, "overlay recreated by flags")
		current.controller.advance(0.05)
		if during: expect(not cue.is_finished(), "overlay deletion preserves cue")
		current.model.get_node("CubismRuntime").free()
		churn()
		expect(not current.model.is_ready() and current.model.get_model_state() == CubismModel2D.DISPOSED, "missing runtime has defined state")
		expect(current.model.reload_model() == ERR_UNCONFIGURED, "missing runtime rejects reload")
		expect(current.model.play_motion(&"Cue/0").get_error() == ERR_UNCONFIGURED, "missing runtime rejects motion")
		current.model.advance(0.05)
		current.model.enable_physics = true
		current.model.enable_pose = true
		current.model.speed_scale = 2
		current.model.stop_motion(0)
		current.controller.advance(0.05)
		if during: expect(cue.is_finished(), "runtime removal terminates cue")
		dispose(current)
	# free() and queued disposal must both abort the remaining effect stages.
	for action: String in ["free_model", "queue_model", "free_runtime", "queue_runtime", "remove_runtime", "free_overlay"]:
		var current := pair()
		current.model.debug_draw_bounds = true
		var model_id: int = current.model.get_instance_id()
		var runtime_id: int = current.model.get_node("CubismRuntime").get_instance_id()
		var calls := [0]
		var cue: CubismSpeechHandle = current.controller.perform(&"Cue/0")
		var handle: CubismMotionHandle = current.controller.get_motion_handle()
		effect(current.model, "Delete", 0, func(target: CubismModel2D, _delta: float):
			print("CUBISM_SAFETY_DISPOSE ", action)
			if action == "free_model": target.free()
			elif action == "queue_model": target.queue_free()
			elif action == "free_runtime": target.get_node("CubismRuntime").free()
			elif action == "queue_runtime": target.get_node("CubismRuntime").queue_free()
			elif action == "remove_runtime": target.remove_child(target.get_node("CubismRuntime"))
			else: target.get_node("CubismDebugOverlay").free(), CONNECT_ONE_SHOT)
		effect(current.model, "Later", 1, func(_model: CubismModel2D, _delta: float): calls[0] += 1)
		current.controller.advance(0.05)
		expect(calls[0] == (1 if action == "free_overlay" else 0), "callback disposal controls remaining stages: " + action)
		if action == "remove_runtime":
			expect(not current.model.is_ready(), "removed runtime unloads after callback")
			instance_from_id(runtime_id).queue_free()
		await process_frame
		await process_frame
		current.controller.advance(0.05)
		if action != "free_overlay":
			expect(not is_instance_id_valid(runtime_id), "disposed runtime is released: " + action)
			expect(cue.is_finished() and handle.is_finished(), "disposal terminates both handles: " + action)
		if action.ends_with("model"): expect(not is_instance_id_valid(model_id), "disposed model is released: " + action)
		dispose(current)
	# Every legacy phase must stop its batch and all subsequent phases.
	var phases := ["cubism_prologue", "cubism_process", "cubism_epilogue"]
	for phase: String in phases:
		var current := pair()
		var runtime: Node = current.model.get_node("CubismRuntime")
		var runtime_id := runtime.get_instance_id()
		var first := GDCubismEffectCustom.new()
		var later := GDCubismEffectCustom.new()
		runtime.add_child(first)
		runtime.add_child(later)
		current.model.advance(0.01)
		var calls := [0, 0, 0]
		first.connect(phase, func(target: GDCubismUserModel, _delta: float):
			print("CUBISM_SAFETY_LEGACY_DISPOSE ", phase)
			target.queue_free(), CONNECT_ONE_SHOT)
		for index in phases.size():
			later.connect(phases[index], func(_target: GDCubismUserModel, _delta: float): calls[index] += 1)
		var cue: CubismSpeechHandle = current.controller.perform(&"Cue/0")
		var handle: CubismMotionHandle = current.controller.get_motion_handle()
		current.controller.advance(0.05)
		for index in phases.size():
			expect(calls[index] == (1 if index < phases.find(phase) else 0), "legacy disposal skips callbacks: " + phase + "/" + phases[index])
		await process_frame
		await process_frame
		current.controller.advance(0.05)
		expect(not is_instance_id_valid(runtime_id), "legacy callback runtime is released: " + phase)
		expect(cue.is_finished() and handle.is_finished(), "legacy disposal terminates both handles: " + phase)
		dispose(current)
	await process_frame
	print("CUBISM_RUNTIME_LIFETIME checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("RUNTIME_LIFETIME_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_RUNTIME_LIFETIME_PASS")
	quit(0 if failures.is_empty() else 1)
