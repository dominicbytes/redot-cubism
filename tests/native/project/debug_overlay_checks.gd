# SPDX-License-Identifier: MIT
extends SceneTree

class ReferenceOverlay extends Node2D:
	var show_bounds := false
	var show_hits := false
	var combined: Rect2
	var hits: Array[Rect2] = []
	func _draw() -> void:
		if show_bounds: draw_rect(combined, Color(0, 1, 1, 0.8), false, -1)
		if show_hits:
			for rect: Rect2 in hits: draw_rect(rect, Color(1, 0.2, 0.8, 0.9), false, -1)

var checks := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func capture(viewport: SubViewport) -> Image:
	for frame in 3:
		await process_frame
		RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()

func geometry(reference: ReferenceOverlay, legacy: GDCubismUserModel) -> void:
	# Renderer-updated AABBs are independent of the new Core-based diagnostics.
	var first := true
	var meshes := legacy.get_meshes()
	for mesh: MeshInstance2D in meshes.values():
		var box: AABB = (mesh.mesh as ArrayMesh).custom_aabb
		var rect := Rect2(Vector2(box.position.x, box.position.y), Vector2(box.size.x, box.size.y))
		reference.combined = rect if first else reference.combined.merge(rect)
		first = false
	reference.hits.clear()
	var seen: Array[String] = []
	for area: Dictionary in legacy.get_hit_areas():
		if not meshes.has(area.id) or seen.has(area.id): continue
		seen.append(area.id)
		var box: AABB = (meshes[area.id].mesh as ArrayMesh).custom_aabb
		reference.hits.append(Rect2(Vector2(box.position.x, box.position.y), Vector2(box.size.x, box.size.y)))
	reference.queue_redraw()

func viewport() -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	return view

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		expect(false, "debug overlay checks require graphics")
		finish()
		return
	var source := load("res://imported-model.res") as CubismModelResource
	for with_layout: bool in [false, true]:
		var resource := source.duplicate(true) as CubismModelResource
		resource.layout = {"width": 1.5, "x": -4.0, "y": 4.0} if with_layout else {}
		resource.hit_areas = [{"Id": "D_PSD_70", "Name": "Head"}, {"Id": "HitArea", "Name": "Hit"}, {"Id": "D_PSD_70", "Name": "Duplicate"}, {"Id": "missing", "Name": "Missing"}]
		var view := viewport()
		var oracle_view := viewport()
		var node := CubismModel2D.new()
		node.name = "DebugCharacter"
		node.playback_process_mode = CubismModel2D.MANUAL
		node.enable_physics = false
		node.enable_pose = false
		view.add_child(node)
		expect(not node.debug_draw_bounds and not node.debug_draw_hit_areas, "diagnostics default off")
		expect(node.get_child_count(true) == 1, "no diagnostic child allocated by default")
		expect(node.load_model(resource) == OK, "debug fixture loads")
		var legacy := GDCubismUserModel.new()
		legacy.playback_process_mode = GDCubismUserModel.MANUAL
		legacy.physics_evaluate = false
		legacy.pose_update = false
		legacy.mask_viewport_size = 1024
		oracle_view.add_child(legacy)
		legacy.model = resource
		if not node.is_ready() or not legacy.is_initialized():
			view.free()
			oracle_view.free()
			finish()
			return
		node.advance(0.05)
		legacy.advance(0.05)
		var reference := ReferenceOverlay.new()
		legacy.add_child(reference)
		geometry(reference, legacy)
		expect(reference.hits.size() == 2, "fixture has two distinct valid hit drawables")
		if with_layout: expect(reference.combined.end.x < 0 and reference.combined.end.y < 0, "fixture bounds are entirely negative")
		var scale := 220.0 / maxf(reference.combined.size.x, reference.combined.size.y)
		node.scale = Vector2.ONE * scale
		node.position = Vector2(128, 128) - reference.combined.get_center() * scale
		legacy.transform = node.transform
		node.advance(0.05)
		legacy.advance(0.05)
		geometry(reference, legacy)
		var baseline := await capture(view)
		var expected := await capture(oracle_view)
		expect(baseline.get_data() == expected.get_data(), "baseline preferred/legacy pixels match")
		for flags: int in [1, 2, 3, 0, 3]:
			node.paused = true
			var before := node.get_parameter_value(&"ParamAngleX")
			node.debug_draw_bounds = bool(flags & 1)
			node.debug_draw_hit_areas = bool(flags & 2)
			reference.show_bounds = bool(flags & 1)
			reference.show_hits = bool(flags & 2)
			reference.queue_redraw()
			var actual := await capture(view)
			expected = await capture(oracle_view)
			expect(actual.get_data() == expected.get_data(), "overlay pixels match renderer bounds at flags " + str(flags))
			expect((actual.get_data() == baseline.get_data()) == (flags == 0), "flag visibly changes or clears drawing")
			expect(node.get_parameter_value(&"ParamAngleX") == before, "toggling diagnostics does not evaluate simulation")
			expect(node.get_child_count() == 0 and node.get_child_count(true) == 2, "one reusable private drawing child")
		node.paused = false
		for angle: float in [-25, 25]:
			node.set_parameter_value(&"ParamAngleX", angle)
			for parameter: GDCubismParameter in legacy.get_parameters():
				if parameter.get_id() == "ParamAngleX": parameter.value = angle
			node.advance(0.05)
			legacy.advance(0.05)
			geometry(reference, legacy)
			var actual := await capture(view)
			expected = await capture(oracle_view)
			expect(actual.get_data() == expected.get_data(), "overlay follows current deformed vertices")
		# Retained draw commands follow node/canvas transforms without another
		# animation evaluation, including while the model is paused.
		node.paused = true
		var center := reference.combined.get_center()
		node.transform = Transform2D(Vector2(-scale, 0), Vector2(scale * 0.15, scale * 0.8), Vector2.ZERO)
		node.position = Vector2(128, 128) - node.transform.basis_xform(center)
		legacy.transform = node.transform
		node.modulate = Color(0.8, 1, 0.7, 0.7)
		legacy.modulate = node.modulate
		var transformed := await capture(view)
		expected = await capture(oracle_view)
		expect(transformed.get_data() == expected.get_data(), "overlays follow mirrored/sheared transforms and modulation while paused")
		node.hide()
		var hidden := await capture(view)
		expect(hidden.get_used_rect().size == Vector2i.ZERO, "hidden models hide diagnostics")
		node.show()
		expect((await capture(view)).get_data() == transformed.get_data(), "show restores diagnostic pixels")
		var packed := PackedScene.new()
		expect(packed.pack(node) == OK and packed.get_state().get_node_count() == 1, "private drawing child is not serialized")
		expect(ResourceSaver.save(packed, "user://debug-overlay.tscn") == OK, "save diagnostic flags")
		var saved := ResourceLoader.load("user://debug-overlay.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if saved:
			var restored := saved.instantiate() as CubismModel2D
			expect(restored.debug_draw_bounds and restored.debug_draw_hit_areas and restored.get_child_count() == 0, "flags restore without a serialized helper")
			view.remove_child(node)
			view.add_child(restored)
			# Scene persistence restores configuration, not the earlier simulated pose.
			restored.paused = false
			restored.advance(0.05)
			restored.paused = true
			legacy.model = resource
			legacy.move_child(reference, legacy.get_child_count() - 1)
			legacy.transform = restored.transform
			legacy.modulate = restored.modulate
			legacy.advance(0.05)
			geometry(reference, legacy)
			expect((await capture(view)).get_data() == (await capture(oracle_view)).get_data(), "reopened scene renders restored diagnostic flags")
			restored.free()
			view.add_child(node)
		else: expect(false, "saved diagnostic scene loads")
		expect(DirAccess.remove_absolute("user://debug-overlay.tscn") == OK, "remove diagnostic test save")
		for cycle in 10:
			node.debug_draw_bounds = false
			node.debug_draw_hit_areas = false
			node.debug_draw_hit_areas = true
			node.debug_draw_bounds = true
			expect(node.get_child_count(true) == 2, "repeated toggling does not accumulate drawing children")
		node.unload_model()
		var unloaded := await capture(view)
		expect(unloaded.get_used_rect().size == Vector2i.ZERO, "unload clears stale overlays while paused")
		node.model = null
		expect((await capture(view)).get_used_rect().size == Vector2i.ZERO, "cleared model has no diagnostic drawing")
		expect(node.load_model(resource) == OK, "reload diagnostic model")
		node.paused = false
		node.modulate = Color.WHITE
		node.transform = Transform2D(Vector2(scale, 0), Vector2(0, scale), Vector2.ZERO)
		legacy.model = resource
		legacy.move_child(reference, legacy.get_child_count() - 1)
		legacy.modulate = Color.WHITE
		legacy.advance(0.05)
		geometry(reference, legacy)
		node.position = Vector2(128, 128) - reference.combined.get_center() * scale
		legacy.transform = node.transform
		node.advance(0.05)
		legacy.advance(0.05)
		geometry(reference, legacy)
		expect((await capture(view)).get_data() == (await capture(oracle_view)).get_data(), "reload draws current geometry without stale coordinates")
		view.free()
		oracle_view.free()
		await process_frame
	finish()

func finish() -> void:
	print("CUBISM_DEBUG_OVERLAY " + JSON.stringify({"checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method()}))
	if failures.is_empty(): print("CUBISM_DEBUG_OVERLAY_PASS")
	quit(0 if failures.is_empty() else 1)
