# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func vertices(model: GDCubismUserModel) -> PackedVector2Array:
	var result := PackedVector2Array()
	for mesh: MeshInstance2D in model.get_meshes().values():
		if mesh.mesh.get_surface_count() > 0:
			result.append_array(mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	return result

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://factory-model.res") as CubismModelResource
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.parameter_mode = GDCubismUserModel.NONE_PARAMETER
	model.physics_evaluate = false
	model.pose_update = false
	var effect := GDCubismEffectCustom.new()
	var steps: Array[float] = []
	effect.cubism_process.connect(func(_owner: GDCubismUserModel, delta: float): steps.append(delta))
	model.add_child(effect)
	root.add_child(model)
	model.model = resource
	expect(model.is_initialized(), "legacy fixture loads")
	if not model.is_initialized():
		model.free()
		finish()
		return
	var parameters := model.get_parameters()
	var parts := model.get_part_opacities()
	expect(not parameters.is_empty() and not parts.is_empty(), "fixture has parameters and parts")
	if parameters.is_empty() or parts.is_empty():
		model.free()
		finish()
		return
	var parameter_count := parameters.size()
	var parameter: GDCubismParameter = parameters[0]
	var part: GDCubismPartOpacity = parts[0]
	parameters.clear()
	parameters.append(null)
	parts.clear()
	parts.append(null)
	expect(model.get_parameters().size() == parameter_count and model.get_parameters()[0] == parameter, "parameter enumeration is a shallow snapshot")
	expect(model.get_part_opacities()[0] == part, "part enumeration is a shallow snapshot")
	expect(not model.get_property_list().is_empty(), "property enumeration survives container mutation")
	model.advance(0.01)
	steps.clear()
	var before := vertices(model)
	parameter.value = lerpf(parameter.minimum_value, parameter.maximum_value, 0.75)
	part.value = 0.37
	model.advance(0)
	expect(steps == [0.0], "zero delta invokes custom effects")
	if DisplayServer.get_name() != "headless":
		expect(not before.is_empty() and vertices(model) != before, "zero delta updates deformed geometry")
	expect(is_equal_approx(float(model.get(parameter.id)), parameter.value), "zero delta applies parameter write to Core")
	expect(is_equal_approx(float(model.get(part.id)), 0.37), "zero delta applies part write to Core")
	# Keep a pending finite write while rejecting invalid writes. This also
	# checks that rejection preserves the dirty flag until the zero step.
	for value: float in [NAN, INF, -INF, 1e300, -1e300]:
		parameter.value = parameter.default_value
		part.value = 0.61
		Engine.print_error_messages = false
		parameter.value = value
		part.value = value
		model.set(parameter.id, value)
		model.set(part.id, value)
		Engine.print_error_messages = true
		expect(parameter.value == parameter.default_value and is_equal_approx(part.value, 0.61), "invalid wrapper writes preserve cached values")
		expect(is_finite(float(model.get(parameter.id))) and is_equal_approx(float(model.get(part.id)), 0.37), "invalid dynamic writes preserve native values")
		model.advance(0)
		expect(float(model.get(parameter.id)) == parameter.default_value and is_equal_approx(float(model.get(part.id)), 0.61), "pending finite writes survive rejection")
		part.value = 0.37
		model.advance(0)
	var meshes := model.get_meshes()
	var mesh_count := meshes.size()
	meshes.clear()
	meshes["unused"] = null
	model.advance(0)
	expect(model.get_meshes().size() == mesh_count and not model.get_meshes().has("unused"), "mesh enumeration cannot mutate renderer lookup")
	var exposed: Array = model.get_meshes().values()
	if not exposed.is_empty():
		var mesh: MeshInstance2D = exposed[0]
		mesh.mesh = null
		model.advance(0)
		mesh.free()
		model.advance(0)
		for value: Variant in exposed:
			if is_instance_valid(value): value.free()
		model.advance(0)
		expect(true, "missing resources, deleted meshes and no surviving mesh are safe")
	model.unload_model()
	expect(not parameter.is_valid() and not part.is_valid(), "snapshot mutation cannot bypass unload invalidation")
	model.model = resource
	expect(model.is_initialized() and not parameter.is_valid() and not part.is_valid(), "reload keeps retained wrappers invalid")
	model.free()
	var preferred := CubismModel2D.new()
	preferred.playback_process_mode = CubismModel2D.MANUAL
	preferred.enable_physics = false
	preferred.enable_pose = false
	root.add_child(preferred)
	expect(preferred.load_model(resource) == OK, "preferred fixture loads")
	var original := preferred.get_parameter_value(parameter.id)
	var requested := lerpf(parameter.minimum_value, parameter.maximum_value, 0.75)
	expect(preferred.set_parameter_value(parameter.id, requested) == OK, "preferred write queues")
	preferred.advance(0)
	expect(is_equal_approx(preferred.get_parameter_value(parameter.id), original), "preferred zero delta retains pending write")
	preferred.advance(0.01)
	expect(is_equal_approx(preferred.get_parameter_value(parameter.id), requested), "preferred positive delta consumes pending write")
	preferred.free()
	finish()

func finish() -> void:
	for failure: String in failures: printerr("CUBISM_LEGACY_STATE_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_LEGACY_STATE_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
