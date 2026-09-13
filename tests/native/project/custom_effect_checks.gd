# SPDX-License-Identifier: MIT
extends SceneTree

const ANGLE := &"ParamAngleX"
var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func close(value: float, expected: float, label: String) -> void:
	expect(absf(value - expected) < 0.0001, label + " got " + str(value) + " expected " + str(expected))

func model() -> CubismModel2D:
	var node := CubismModel2D.new()
	node.playback_process_mode = CubismModel2D.MANUAL
	node.enable_physics = false
	node.enable_pose = false
	root.add_child(node)
	expect(node.load_model(resource) == OK, "effect fixture loads")
	return node

func effect(node: CubismModel2D, label: String, priority: int, callback: Callable) -> CubismEffect:
	var item := CubismEffect.new()
	item.name = label
	item.effect_priority = priority
	node.add_child(item)
	item.effect_process.connect(callback.bind(item))
	return item

func write_set(_model: CubismModel2D, _delta: float, item: CubismEffect) -> void:
	expect(item.set_parameter_value(ANGLE, 4) == OK, "effect set accepted in callback")

func write_add(_model: CubismModel2D, _delta: float, item: CubismEffect) -> void:
	expect(item.add_parameter_value(ANGLE, 2) == OK, "effect add accepted in callback")

func write_multiply(_model: CubismModel2D, _delta: float, item: CubismEffect) -> void:
	expect(item.multiply_parameter_value(ANGLE, 2) == OK, "effect multiply accepted in callback")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res")
	for tied in [false, true]:
		for reversed in [false, true]:
			var node := model()
			var entries := [["A_Set", -20, write_set], ["B_Add", -10, write_add], ["C_Multiply", 10, write_multiply]]
			if reversed: entries.reverse()
			for entry in entries: effect(node, entry[0], 0 if tied else entry[1], entry[2])
			node.advance(0.05)
			close(node.get_parameter_value(ANGLE), 12, "priority/name order independent of construction")
			node.move_child(node.get_node("A_Set"), node.get_child_count() - 1)
			node.advance(0.05)
			close(node.get_parameter_value(ANGLE), 12, "sibling move does not reorder effects")
			node.set_parameter_value(ANGLE, 7, 1, CubismModel2D.LAYER_EFFECT)
			node.advance(0.05)
			close(node.get_parameter_value(ANGLE), 7, "queued EFFECT layer follows custom effects")
			node.free()
	# Reference native animation has no custom effect. The observer must see the
	# already evaluated motion/expression and then affect the same frame.
	var reference := model()
	reference.play_motion(&"Cue/0")
	reference.set_expression(&"Add", 0)
	reference.advance(0.05)
	var animated := model()
	animated.play_motion(&"Cue/0")
	animated.set_expression(&"Add", 0)
	var observed := [0.0]
	effect(animated, "AfterExpression", 0, func(target: CubismModel2D, _delta: float, item: CubismEffect):
		observed[0] = target.get_parameter_value(ANGLE)
		item.add_parameter_value(ANGLE, 3))
	animated.advance(0.05)
	close(observed[0], reference.get_parameter_value(ANGLE), "custom stage follows native motion and expression")
	close(animated.get_parameter_value(ANGLE), observed[0] + 3, "custom stage changes current frame")
	animated.free()
	reference.free()
	var physical := model()
	physical.enable_physics = true
	for frame in 10: physical.advance(0.05)
	effect(physical, "BeforePhysics", 0, func(_model: CubismModel2D, _delta: float, item: CubismEffect): item.set_parameter_value(&"ParamHairFront", 0.75))
	physical.advance(0.05)
	expect(absf(physical.get_parameter_value(&"ParamHairFront") - 0.75) > 0.1, "physics evaluates after custom effect")
	physical.free()
	var speaking := model()
	var lip := CubismLipSync.new()
	root.add_child(lip)
	lip.profile = CubismLipSyncProfile.new()
	lip.profile.attack = 0
	lip.set_target_model(speaking)
	lip.submit_sample(0.5)
	effect(speaking, "AfterLip", 0, func(target: CubismModel2D, _delta: float, item: CubismEffect):
		expect(target.get_parameter_value(&"ParamMouthOpenY") > 0.1, "lip sync evaluates before custom effect")
		item.set_parameter_value(&"ParamMouthOpenY", 0.1))
	speaking.advance(0.05)
	close(speaking.get_parameter_value(&"ParamMouthOpenY"), 0.1, "custom effect can override lip result")
	lip.free()
	speaking.free()
	var node := model()
	var trace: Array[String] = []
	var later: CubismEffect
	var first := effect(node, "First", 0, func(_model: CubismModel2D, _delta: float, _item: CubismEffect):
		trace.append("first")
		node.get_node("Later").effect_priority = -1
		node.get_node("Later").enabled = false)
	later = effect(node, "Later", 1, func(_model: CubismModel2D, _delta: float, _item: CubismEffect): trace.append("later"))
	node.advance(0.05)
	expect(trace == ["first", "later"], "priority and enabled changes use next-step snapshot")
	trace.clear()
	node.advance(0.05)
	expect(trace == ["first"], "disabled effect absent next step")
	later.enabled = true
	trace.clear()
	node.advance(0.05)
	expect(trace == ["later", "first"], "changed priority applies next step")
	expect(first.set_parameter_value(ANGLE, 1) == ERR_UNAVAILABLE, "effect cannot write outside callback")
	node.free()
	# Detach/readd during another callback must not sneak a new membership into
	# the existing snapshot, even when parent and object ID end up unchanged.
	node = model()
	var moved := [false]
	effect(node, "First", 0, func(_model: CubismModel2D, _delta: float, _item: CubismEffect):
		if not moved[0]:
			moved[0] = true
			var other := node.get_node("Later")
			node.remove_child(other)
			node.add_child(other))
	var calls := [0]
	effect(node, "Later", 1, func(_model: CubismModel2D, _delta: float, _item: CubismEffect): calls[0] += 1)
	node.advance(0.05)
	expect(calls[0] == 0, "reentered effect waits for new snapshot")
	node.advance(0.05)
	expect(calls[0] == 1, "reentered effect runs next step")
	node.free()
	node = model()
	effect(node, "ReparentSelf", 0, func(target: CubismModel2D, _delta: float, item: CubismEffect):
		target.remove_child(item)
		target.add_child(item)
		expect(item.set_parameter_value(ANGLE, 29) == ERR_UNAVAILABLE, "reparenting self revokes active write scope"))
	node.advance(0.05)
	close(node.get_parameter_value(ANGLE), 0, "reparented callback cannot retain old write access")
	node.free()
	node = model()
	var removed_calls := [0]
	effect(node, "Delete", 0, func(target: CubismModel2D, _delta: float, item: CubismEffect):
		target.get_node("Later").queue_free()
		item.queue_free()
		expect(item.set_parameter_value(ANGLE, 29) == ERR_UNAVAILABLE, "queued effect deletion revokes write scope"))
	effect(node, "Later", 1, func(_model: CubismModel2D, _delta: float, _item: CubismEffect): removed_calls[0] += 1)
	node.advance(0.05)
	expect(removed_calls[0] == 0, "queued deletion skips later snapshot entries")
	await process_frame
	node.free()
	node = model()
	var outsider := effect(node, "Other", 1, func(_model: CubismModel2D, _delta: float, _item: CubismEffect): pass)
	effect(node, "Validation", 0, func(target: CubismModel2D, _delta: float, item: CubismEffect):
		expect(outsider.set_parameter_value(ANGLE, 29) == ERR_UNAVAILABLE, "cannot write on another effect's behalf")
		expect(item.set_parameter_value(ANGLE, NAN) == ERR_INVALID_PARAMETER, "reject effect NaN")
		expect(item.add_parameter_value(ANGLE, 1, INF) == ERR_INVALID_PARAMETER, "reject effect infinite weight")
		expect(item.multiply_parameter_value(&"missing", 2) == ERR_DOES_NOT_EXIST, "reject unknown effect parameter")
		item.set_parameter_value(ANGLE, 1000)
		close(target.get_parameter_value(ANGLE), 30, "effect result clamped to native range")
		target.set_parameter_value(ANGLE, -4)
		close(target.get_parameter_value(ANGLE), 30, "model write remains queued inside effect callback"))
	node.advance(0.05)
	close(node.get_parameter_value(ANGLE), 30, "custom write is immediate")
	node.advance(0.05)
	close(node.get_parameter_value(ANGLE), -4, "queued model override applies following step")
	node.free()
	node = model()
	var deltas: Array[float] = []
	var clocked := effect(node, "Clocked", 0, func(_model: CubismModel2D, delta: float, _item: CubismEffect): deltas.append(delta))
	node.paused = true
	node.advance(0.05)
	expect(deltas.is_empty(), "model pause suspends effect")
	node.paused = false
	node.speed_scale = 2
	node.advance(0.025)
	expect(deltas.size() == 1, "one callback per model step")
	close(deltas[0], 0.05, "effect follows scaled model clock")
	clocked.process_mode = Node.PROCESS_MODE_DISABLED
	node.advance(0.05)
	expect(deltas.size() == 1, "effect respects Node process mode")
	clocked.process_mode = Node.PROCESS_MODE_INHERIT
	paused = true
	node.advance(0.05)
	paused = false
	expect(deltas.size() == 1, "effect respects scene-tree pause")
	node.free()
	# A reload requested by an effect invalidates this callback and later effects.
	node = model()
	var reload_calls := [0]
	effect(node, "Reload", 0, func(target: CubismModel2D, _delta: float, item: CubismEffect):
		target.reload_model()
		expect(item.set_parameter_value(ANGLE, 29) == ERR_UNAVAILABLE, "reload revokes current effect write scope"))
	effect(node, "Later", 1, func(_model: CubismModel2D, _delta: float, _item: CubismEffect): reload_calls[0] += 1)
	node.advance(0.05)
	expect(reload_calls[0] == 0, "reload cancels remaining old-generation effects")
	await process_frame
	node.free()
	# Legacy init/prologue/process/epilogue/term still use their original order.
	var legacy := GDCubismUserModel.new()
	legacy.playback_process_mode = GDCubismUserModel.MANUAL
	legacy.physics_evaluate = false
	legacy.pose_update = false
	root.add_child(legacy)
	legacy.model = resource
	var legacy_trace: Array[String] = []
	for label: String in ["B", "A"]:
		var old := GDCubismEffectCustom.new()
		old.name = label
		legacy.add_child(old)
		old.cubism_init.connect(func(_model: GDCubismUserModel): legacy_trace.append(label + " init"))
		old.cubism_term.connect(func(_model: GDCubismUserModel): legacy_trace.append(label + " term"))
		old.cubism_prologue.connect(func(_model: GDCubismUserModel, _delta: float): legacy_trace.append(label + " prologue"))
		old.cubism_process.connect(func(_model: GDCubismUserModel, _delta: float): legacy_trace.append(label + " process"))
		old.cubism_epilogue.connect(func(_model: GDCubismUserModel, _delta: float): legacy_trace.append(label + " epilogue"))
	legacy.advance(0.05)
	expect(legacy_trace == ["B init", "A init", "B process", "A process", "B epilogue", "A epilogue"], "legacy initialization order preserved")
	legacy_trace.clear()
	legacy.advance(0.05)
	expect(legacy_trace == ["B prologue", "A prologue", "B process", "A process", "B epilogue", "A epilogue"], "legacy update callbacks preserved")
	legacy_trace.clear()
	legacy.unload_model()
	expect(legacy_trace == ["B term", "A term"], "legacy termination preserved")
	legacy.free()
	if OS.get_cmdline_user_args().has("--prepare-scene"):
		node = model()
		var saved := CubismEffect.new()
		saved.name = "SavedEffect"
		saved.enabled = false
		saved.effect_priority = -12
		node.add_child(saved)
		saved.owner = node
		var scene := PackedScene.new()
		expect(scene.pack(node) == OK and ResourceSaver.save(scene, "res://custom-effects.tscn") == OK, "save scene containing effect")
		node.free()
	var restored: CubismModel2D = load("res://custom-effects.tscn").instantiate()
	root.add_child(restored)
	var saved_effect: CubismEffect = restored.get_node("SavedEffect")
	expect(not saved_effect.enabled and saved_effect.effect_priority == -12 and restored.is_ready(), "native/exported scene preserves effect configuration")
	restored.free()
	print("CUBISM_CUSTOM_EFFECTS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty(): print("CUBISM_CUSTOM_EFFECTS_PASS")
	quit(0 if failures.is_empty() else 1)
