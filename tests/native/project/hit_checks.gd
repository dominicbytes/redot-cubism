# SPDX-License-Identifier: MIT
extends SceneTree

var checks := 0
var failures: Array[String] = []
var events: Array[String] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func bounds(legacy: GDCubismUserModel, id: String) -> Rect2:
	var mesh: MeshInstance2D = legacy.get_meshes()[id]
	# Use the renderer's CPU-computed bounds. Its headless compatibility guard
	# skips mesh refresh, so deforming-bound tests require a graphics backend.
	var box: AABB = mesh.mesh.custom_aabb
	expect(box.size.x > 0 and box.size.y > 0, "reference hit mesh has bounds")
	return Rect2(Vector2(box.position.x, box.position.y), Vector2(box.size.x, box.size.y))

func inside(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x and point.y >= rect.position.y and point.y <= rect.end.y

func settle() -> void:
	await process_frame
	await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var deform := OS.get_cmdline_user_args().has("--deformation")
	var head_id := "D_PSD_70" if deform else "HitArea"
	var source := load("res://imported-model.res") as CubismModelResource
	for with_layout: bool in [false, true]:
		var resource := source.duplicate(true) as CubismModelResource
		resource.layout = {"width": 4.0, "x": 0.5, "y": -0.25} if with_layout else {}
		resource.hit_areas = [{"Id": head_id, "Name": "頭_😀"}, {"Id": "HitArea2", "Name": "Body"}, {"Id": "missing", "Name": "Absent"}]
		var node := CubismModel2D.new()
		node.playback_process_mode = CubismModel2D.MANUAL
		node.enable_physics = false
		node.enable_pose = false
		root.add_child(node)
		expect(node.load_model(resource) == OK, "hit fixture loads")
		node.hit_area_entered.connect(func(name: StringName): events.append("+" + String(name)))
		node.hit_area_exited.connect(func(name: StringName): events.append("-" + String(name)))
		var legacy := GDCubismUserModel.new()
		legacy.playback_process_mode = GDCubismUserModel.MANUAL
		legacy.physics_evaluate = false
		legacy.pose_update = false
		legacy.model = resource
		root.add_child(legacy)
		node.advance(0.05)
		legacy.advance(0.05)
		expect(node.get_hit_area_names() == PackedStringArray(["頭_😀", "Body", "Absent"]), "ordered UTF8 hit names")
		expect(not node.hit_test(&"missing name", Vector2.ZERO), "unknown name misses")
		expect(not node.hit_test(&"Absent", Vector2.ZERO), "unknown drawable misses")
		expect(not node.hit_test(&"Body", Vector2(NAN, 0)) and not node.hit_test(&"Body", Vector2(0, INF)), "nonfinite query misses safely")
		node.position = Vector2(280, -60)
		node.rotation = 0.6
		node.scale = Vector2(-0.8, 1.6)
		var head_bounds: Array[Rect2] = []
		for angle: float in [-25.0, 0.0, 25.0]:
			node.set_parameter_value(&"ParamAngleX", angle)
			for parameter: GDCubismParameter in legacy.get_parameters():
				if parameter.get_id() == "ParamAngleX": parameter.value = angle
			node.advance(0.05)
			legacy.advance(0.05)
			head_bounds.append(bounds(legacy, head_id))
			for area: Dictionary in resource.hit_areas:
				if area.Id == "missing": continue
				var rect := bounds(legacy, area.Id)
				for x in range(-1, 12):
					for y in range(-1, 12):
						# Sample within cells, away from float-ambiguous exact boundaries.
						var local := rect.position + rect.size * Vector2((x + 0.37) / 10.0, (y + 0.37) / 10.0)
						var roundtrip := node.to_local(node.to_global(local))
						expect(node.hit_test(StringName(area.Name), roundtrip) == inside(rect, local), "deformed mesh bounds match local hit query with layout and transforms")
		var head := bounds(legacy, head_id).get_center()
		var body := bounds(legacy, "HitArea2").get_center()
		expect(node.hit_test(&"頭_😀", head) and not node.hit_test(&"Body", head), "head target isolates head")
		expect(node.hit_test(&"Body", body) and not node.hit_test(&"頭_😀", body), "body target isolates body")
		await settle()
		events.clear()
		var moving_point := Vector2.ZERO
		var found_moving := false
		for x in 200:
			for y in 20:
				var point := head_bounds[0].position + head_bounds[0].size * Vector2((x + 0.5) / 200.0, (y + 0.5) / 20.0)
				if not inside(head_bounds[2], point): moving_point = point; found_moving = true; break
			if found_moving: break
		if deform: expect(found_moving, "fixture has deforming hit region")
		if found_moving:
			node.set_hit_test_target(moving_point)
			await settle()
			node.set_parameter_value(&"ParamAngleX", -25.0)
			node.advance(0.05)
			await settle()
			expect(events.has("+頭_😀"), "animation enters a stationary target")
			node.set_parameter_value(&"ParamAngleX", 25.0)
			node.advance(0.05)
			await settle()
			expect(events.has("-頭_😀"), "animation exits a stationary target")
		node.clear_hit_test_target()
		await settle()
		events.clear()
		node.set_hit_test_target(head)
		expect(events.is_empty(), "hover signals deferred")
		await settle()
		expect(events == ["+頭_😀"], "first enter once")
		for frame in 10:
			node.set_hit_test_target(head)
			node.set_parameter_value(&"ParamAngleX", 25.0)
			node.advance(0.05)
		await settle()
		expect(events == ["+頭_😀"], "stationary target does not repeat")
		var warnings: Array[int] = []
		node.runtime_warning.connect(func(code: int, _message: String): warnings.append(code))
		node.set_hit_test_target(Vector2(NAN, 0))
		await settle()
		expect(warnings == [ERR_INVALID_PARAMETER] and events == ["+頭_😀"], "invalid tracking target warns and retains hover")
		node.set_hit_test_target(body)
		node.clear_hit_test_target()
		node.set_hit_test_target(head)
		await settle()
		expect(events == ["+頭_😀"], "target changes coalesce before delivery")
		node.paused = true
		node.set_hit_test_target(body)
		await settle()
		expect(events == ["+頭_😀", "-頭_😀", "+Body"], "target follows frozen pose with exits before enters")
		node.hide()
		await settle()
		expect(events.back() == "-Body", "hide exits tracked area")
		expect(node.hit_test(&"Body", body), "pure geometry query is independent of visibility")
		node.show()
		await settle()
		expect(events.back() == "+Body", "show reevaluates retained target")
		node.process_mode = Node.PROCESS_MODE_DISABLED
		await settle()
		expect(events.back() == "-Body", "disabled processing exits")
		node.process_mode = Node.PROCESS_MODE_INHERIT
		await settle()
		expect(events.back() == "+Body", "reenabled processing restores hover")
		node.clear_hit_test_target()
		node.clear_hit_test_target()
		await settle()
		expect(events.back() == "-Body", "clearing pointer exits once")
		var count := events.size()
		node.advance(0.05)
		await settle()
		expect(events.size() == count, "cleared pointer stays inactive")
		node.paused = false
		node.set_hit_test_target(head)
		await settle()
		node.reload_model()
		await settle()
		expect(events.back() == "-頭_😀", "reload exits old model and clears target")
		head = head_bounds[1].get_center()
		node.set_hit_test_target(head)
		await settle()
		root.remove_child(node)
		await settle()
		expect(events.back() == "-頭_😀", "tree exit reports exit")
		count = events.size()
		root.add_child(node)
		await settle()
		expect(events.size() == count, "tree reentry does not restore transient pointer")
		node.set_hit_test_target(head)
		await settle()
		node.unload_model()
		await settle()
		expect(events.back() == "-頭_😀" and node.get_hit_area_names().is_empty() and not node.hit_test(&"頭_😀", head), "unload exits and clears hit catalog")
		node.free()
		legacy.free()
	# Duplicate names aggregate drawables into one logical region. Reload from an
	# entered callback must not emit stale enters from the old snapshot.
	var resource := source.duplicate(true) as CubismModelResource
	resource.hit_areas = [{"Id": "HitArea", "Name": "Both"}, {"Id": "HitArea2", "Name": "Both"}, {"Id": "HitArea", "Name": "Second"}]
	var node := CubismModel2D.new()
	root.add_child(node)
	node.playback_process_mode = CubismModel2D.MANUAL
	node.enable_physics = false
	node.enable_pose = false
	expect(node.load_model(resource) == OK, "overlapping names fixture loads")
	node.advance(0.05)
	expect(node.get_hit_area_names() == PackedStringArray(["Both", "Second"]), "logical names unique in manifest order")
	var head := Vector2.ZERO
	var found := false
	var canvas: Vector2 = node.get_canvas_info().size_in_pixels
	for y in range(-10, 11):
		for x in range(-10, 11):
			var point := Vector2(x, y) * canvas / 20.0
			if node.hit_test(&"Second", point): head = point; found = true; break
		if found: break
	expect(found, "overlap target found")
	events.clear()
	node.hit_area_entered.connect(func(name: StringName):
		events.append("+" + String(name))
		node.unload_model())
	node.hit_area_exited.connect(func(name: StringName): events.append("-" + String(name)))
	node.set_hit_test_target(head)
	await settle()
	expect(events == ["+Both", "-Both"], "callback unload cancels stale enters and exits exactly once")
	node.free()
	await process_frame
	print("CUBISM_HIT checks=", checks, " failures=", failures.size())
	for failure in failures: printerr("HIT_CHECK_FAILED: ", failure)
	if failures.is_empty(): print("CUBISM_HIT_PASS")
	quit(0 if failures.is_empty() else 1)
