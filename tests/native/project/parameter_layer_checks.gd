# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var resource: CubismModelResource
const ANGLE := &"ParamAngleX"

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
	expect(node.load_model(resource) == OK, "layer fixture loads")
	return node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	resource = load("res://imported-model.res")
	for layer in range(CubismModel2D.LAYER_BASE, CubismModel2D.LAYER_POST_EFFECT + 1):
		var node := model()
		var before := node.get_parameter_value(ANGLE)
		expect(node.set_parameter_value(ANGLE, 1, 1, layer) == OK, "accept set at layer " + str(layer))
		expect(node.add_parameter_value(ANGLE, 2, 1, layer) == OK, "accept add at layer " + str(layer))
		expect(node.multiply_parameter_value(ANGLE, 2, 1, layer) == OK, "accept multiply at layer " + str(layer))
		close(node.get_parameter_value(ANGLE), before, "queue does not change evaluated getter")
		node.paused = true
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), before, "paused layer is retained")
		node.paused = false
		node.advance(0)
		close(node.get_parameter_value(ANGLE), before, "zero delta retains layer")
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), 6, "set add multiply retain call order")
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), 6 if layer <= CubismModel2D.LAYER_MOTION else before, "write consumed once; only primary stages enter saved base")
		node.set_parameter_value(ANGLE, 29, 1, layer)
		expect(node.reload_model() == OK, "reload with pending layer")
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), before, "reload discards layer")
		node.set_parameter_value(ANGLE, 29, 1, layer)
		root.remove_child(node)
		root.add_child(node)
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), before, "tree exit discards layer")
		node.free()
	var ordered := model()
	# Deliberately enqueue in reverse pipeline order. Noncommuting operations
	# distinguish layer precedence from submission order: 2,4,8,9,18,19,10.
	ordered.set_parameter_value(ANGLE, 1, 0.5, CubismModel2D.LAYER_POST_EFFECT)
	ordered.add_parameter_value(ANGLE, 1, 1, CubismModel2D.LAYER_POSE)
	ordered.multiply_parameter_value(ANGLE, 2, 1, CubismModel2D.LAYER_PHYSICS)
	ordered.add_parameter_value(ANGLE, 1, 1, CubismModel2D.LAYER_EFFECT)
	ordered.multiply_parameter_value(ANGLE, 2, 1, CubismModel2D.LAYER_EXPRESSION)
	ordered.add_parameter_value(ANGLE, 2, 1, CubismModel2D.LAYER_MOTION)
	ordered.set_parameter_value(ANGLE, 2, 1, CubismModel2D.LAYER_BASE)
	ordered.advance(0.05)
	close(ordered.get_parameter_value(ANGLE), 10, "all seven stages obey pipeline order")
	ordered.advance(0.05)
	close(ordered.get_parameter_value(ANGLE), 4, "primary save excludes later-layer writes")
	for invalid in [-1, 7, 99]:
		expect(ordered.set_parameter_value(ANGLE, 29, 1, invalid) == ERR_INVALID_PARAMETER, "reject unknown layer")
	expect(ordered.set_parameter_value(ANGLE, NAN, 1, CubismModel2D.LAYER_BASE) == ERR_INVALID_PARAMETER, "reject nonfinite early write")
	expect(ordered.add_parameter_value(ANGLE, 1, INF, CubismModel2D.LAYER_MOTION) == ERR_INVALID_PARAMETER, "reject nonfinite early weight")
	expect(ordered.set_parameter_value(&"missing", 1, 1, CubismModel2D.LAYER_POSE) == ERR_DOES_NOT_EXIST, "reject unknown parameter")
	ordered.advance(0.05)
	close(ordered.get_parameter_value(ANGLE), 4, "invalid writes leave queue unchanged")
	ordered.free()
	# Native legacy effect signals run synchronously inside evaluation. Preferred
	# writes from those callbacks must wait for the next complete step too.
	for layer in range(7):
		var node := model()
		var legacy: GDCubismUserModel = node.get_children(true)[0]
		var effect := GDCubismEffectCustom.new()
		legacy.add_child(effect)
		var submitted := [false]
		effect.cubism_process.connect(func(_model: GDCubismUserModel, _delta: float):
			if not submitted[0]:
				submitted[0] = true
				node.set_parameter_value(ANGLE, 8, 1, layer))
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), 0, "callback write waits at every layer")
		node.advance(0.05)
		close(node.get_parameter_value(ANGLE), 8, "callback write applies on following step")
		node.free()
	# Compare native motion and expression evaluation with and without an early
	# write. The reference has no parameter writes and uses the same SDK motion.
	var reference := model()
	reference.play_motion(&"Cue/0")
	reference.set_expression(&"Add", 0)
	reference.advance(0.05)
	for layer in [CubismModel2D.LAYER_BASE, CubismModel2D.LAYER_MOTION, CubismModel2D.LAYER_EXPRESSION]:
		var node := model()
		node.play_motion(&"Cue/0")
		node.set_expression(&"Add", 0)
		node.set_parameter_value(ANGLE, 7, 1, layer)
		node.advance(0.05)
		var expected := reference.get_parameter_value(ANGLE) if layer == CubismModel2D.LAYER_BASE else (17.0 if layer == CubismModel2D.LAYER_MOTION else 7.0)
		close(node.get_parameter_value(ANGLE), expected, "native motion and expression delimit layer " + str(layer))
		node.free()
	reference.free()
	# The private fixture's physics output ParamHairFront has 100% physics weight.
	for layer in [CubismModel2D.LAYER_EFFECT, CubismModel2D.LAYER_PHYSICS, CubismModel2D.LAYER_POSE]:
		var node := model()
		node.enable_physics = true
		for frame in 10: node.advance(0.05)
		node.set_parameter_value(&"ParamHairFront", 0.75, 1, layer)
		node.advance(0.05)
		var value := node.get_parameter_value(&"ParamHairFront")
		if layer == CubismModel2D.LAYER_EFFECT: expect(absf(value - 0.75) > 0.1, "physics replaces EFFECT output")
		else: close(value, 0.75, "write after physics overrides its output")
		node.free()
	# Procedural lip sync is between EXPRESSION and EFFECT.
	for layer in [CubismModel2D.LAYER_EXPRESSION, CubismModel2D.LAYER_EFFECT]:
		var node := model()
		var lip := CubismLipSync.new()
		root.add_child(lip)
		lip.profile = CubismLipSyncProfile.new()
		lip.profile.attack = 0
		lip.set_target_model(node)
		lip.submit_sample(0.5)
		node.set_parameter_value(&"ParamMouthOpenY", 0.1, 1, layer)
		node.advance(0.05)
		var value := node.get_parameter_value(&"ParamMouthOpenY")
		if layer == CubismModel2D.LAYER_EXPRESSION: expect(value > 0.1, "lip effect follows EXPRESSION write")
		else: close(value, 0.1, "EFFECT write follows lip effect")
		lip.free()
		node.free()
	# Queue limits apply to all layers together, and processing frees capacity.
	var bounded := model()
	for index in 100000:
		if bounded.set_parameter_value(ANGLE, 0, 1, index % 7) != OK:
			expect(false, "shared queue accepts documented budget")
			break
	expect(bounded.set_parameter_value(ANGLE, 1) == ERR_OUT_OF_MEMORY, "layers share one bounded queue budget")
	bounded.advance(0.05)
	expect(bounded.set_parameter_value(ANGLE, 8) == OK, "evaluation releases queue capacity")
	bounded.advance(0.05)
	close(bounded.get_parameter_value(ANGLE), 8, "old call shape still defaults to POST_EFFECT")
	bounded.free()
	print("CUBISM_PARAMETER_LAYERS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty(): print("CUBISM_PARAMETER_LAYERS_PASS")
	quit(0 if failures.is_empty() else 1)
