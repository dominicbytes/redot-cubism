extends RefCounted

static func run(host: Node, fixture: Dictionary) -> bool:
	var model := GDCubismUserModel.new()
	var effect := GDCubismEffectCustom.new()
	model.add_child(effect)
	host.add_child(model)
	model.assets = fixture.model
	model.playback_process_mode = GDCubismUserModel.MANUAL
	var steps: Array[float] = []
	effect.cubism_process.connect(func(_owner: GDCubismUserModel, delta: float) -> void: steps.append(delta))
	for delta: float in [NAN, INF, -INF, -1.0, 0.0]:
		model.advance(delta)
	model.speed_scale = NAN
	model.advance(10.0)
	model.speed_scale = 0.0
	model.advance(1.0)
	model.speed_scale = 2.0
	model.advance(1.0 / 60.0)
	if steps.size() != 2 or not is_equal_approx(steps[0], 10.0) or not is_equal_approx(steps[1], 1.0 / 30.0):
		push_error("CUBISM_DELTA_FAIL: invalid or zero delta reached native effects, or finite elapsed time was lost: " + str(steps))
		return false
	for parameter: GDCubismParameter in model.get_parameters():
		if not is_finite(parameter.value):
			push_error("CUBISM_DELTA_FAIL: nonfinite model parameter")
			return false
	model.free()
	print("CUBISM_DELTA_PASS")
	return true
