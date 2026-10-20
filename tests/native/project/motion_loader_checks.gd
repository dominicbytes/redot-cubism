# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
var serial := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func motion(segments: Array, restricted := false) -> Dictionary:
	return {"Version": 3, "Meta": {"Duration": 1, "Fps": 30, "Loop": false,
		"AreBeziersRestricted": restricted, "CurveCount": 1, "TotalSegmentCount": 1,
		"TotalPointCount": 4 if segments[2] == 1 else 2},
		"Curves": [{"Target": "Parameter", "Id": "ParamAngleX", "Segments": segments}]}

func load_text(text: String, rejected := false) -> Animation:
	var path := "user://motion-loader-%d.motion3.json" % serial
	serial += 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var previous := Engine.print_error_messages
	if rejected: Engine.print_error_messages = false
	var animation := ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE) as Animation
	Engine.print_error_messages = previous
	DirAccess.remove_absolute(path)
	return animation

func cubic(a: float, b: float, c: float, d: float, t: float) -> float:
	var u := 1.0 - t
	return u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d

func expected_bezier(time: float, restricted: bool) -> float:
	# The pinned Framework uses time inversion for unrestricted curves and
	# normalized endpoint time for restricted curves.
	var parameter := time
	if not restricted:
		var low := 0.0
		var high := 1.0
		for iteration in 50:
			parameter = (low + high) / 2.0
			if cubic(0, 0.1, 0.7, 1, parameter) < time: low = parameter
			else: high = parameter
	return cubic(0, 0.8, 0.2, 1, parameter)

func _initialize() -> void:
	for text: String in ["", "{}", "[]", "null", '{"Version":3}']:
		expect(load_text(text, true) == null, "reject empty/missing motion structure")
	for kind in 4:
		var complete := [kind, 0.1, 0.8, 0.7, 0.2, 1, 1] if kind == 1 else [kind, 1, 1]
		for width in range(1, complete.size()):
			var value := motion([0, 0, 0, 0.25, 0.25] + complete.slice(0, width))
			value.Meta.TotalSegmentCount = 2
			value.Meta.TotalPointCount += 1
			expect(load_text(JSON.stringify(value), true) == null, "reject truncated type %d width %d" % [kind, width])
	var linear := motion([0, 0, 0, 1, 1])
	for bad_fps: Variant in [0, -1, "30", 1e100, 1e-40, 1e-100]:
		var value := linear.duplicate(true)
		value.Meta.Fps = bad_fps
		expect(load_text(JSON.stringify(value), true) == null, "reject invalid Fps")
	var wrong_case := linear.duplicate(true)
	wrong_case.Meta.erase("Fps")
	wrong_case.Meta.FPS = 30
	expect(load_text(JSON.stringify(wrong_case), true) == null, "require standard Fps field")
	expect(load_text(JSON.stringify(linear) + " ".repeat(4 * 1024 * 1024), true) == null, "reject oversized source before parsing")
	var animation := load_text(JSON.stringify(linear))
	expect(animation != null, "linear resource loads")
	if animation != null:
		expect(absf(animation.step - 1.0 / 30.0) < 1e-7, "30-FPS step")
		for time: float in [0.1, 0.25, 0.5, 0.75, 0.9]:
			expect(absf(animation.bezier_track_interpolate(0, time) - time) < 0.002, "linear sample %.2f" % time)
	for restricted: bool in [false, true]:
		animation = load_text(JSON.stringify(motion([0, 0, 1, 0.1, 0.8, 0.7, 0.2, 1, 1], restricted)))
		expect(animation != null, "cubic resource loads")
		if animation == null: continue
		for time: float in [0.1, 0.25, 0.5, 0.75, 0.9]:
			expect(absf(animation.bezier_track_interpolate(0, time) - expected_bezier(time, restricted)) < 0.002,
				"cubic sample %.2f restricted=%s" % [time, restricted])
	# SDK 5-r.5 interior references, also checked against actual playback in
	# sdk_json_checks.gd. The unrestricted curve has discontinuous root selection and
	# cannot be represented by this continuous Animation track.
	var outside := [0, 0, 1, -0.5, 0.8, 1.5, 0.2, 1, 1]
	expect(CubismManifestParser.parse_motion(JSON.stringify(motion(outside)), "Curve", 0, "res://outside.motion3.json").ok,
		"outside-control curve remains valid for native SDK playback")
	expect(load_text(JSON.stringify(motion(outside)), true) == null,
		"reject unrestricted out-of-interval controls instead of clamping")
	animation = load_text(JSON.stringify(motion(outside, true)))
	expect(animation != null, "restricted out-of-interval controls load")
	if animation != null:
		var times := [0.1, 0.25, 0.5, 0.75, 0.9]
		var sdk_values := [0.2008, 0.38125, 0.5, 0.61875, 0.7992]
		for index in times.size():
			expect(absf(animation.bezier_track_interpolate(0, times[index]) - sdk_values[index]) < 0.002,
				"restricted outside-control SDK sample %.2f" % times[index])
	for controls: Array in [[-0.5, 0.7], [0.1, 1.5], [1.5, 0.7], [0.1, -0.5]]:
		expect(load_text(JSON.stringify(motion([0, 0, 1, controls[0], 0.8, controls[1], 0.2, 1, 1])), true) == null,
			"reject either unrestricted control outside either endpoint")
	for failure in failures: printerr("CUBISM_MOTION_LOADER_FAIL: ", failure)
	print("CUBISM_MOTION_LOADER_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty(): print("CUBISM_MOTION_LOADER_PASS")
	quit(0 if failures.is_empty() else 1)
