# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0
const OWNED := ["loaded_models", "live_drawable_nodes", "live_mesh_resources", "live_material_resources", "live_mask_viewports", "live_compositor_viewports", "live_motion_handles"]

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func counts(node: Node, result: Dictionary) -> void:
	if node is MeshInstance2D:
		result.drawables += 1
		if node.mesh: result.meshes[node.mesh.get_instance_id()] = true
		if node.material: result.materials[node.material.get_instance_id()] = true
	if node is SubViewport: result.viewports += 1
	for child: Node in node.get_children(true): counts(child, result)

func verify_tree(node: CubismModel2D, fallback: bool) -> void:
	var actual := {"drawables": 0, "meshes": {}, "materials": {}, "viewports": 0}
	counts(node, actual)
	var stats := CubismBuildInfo.get_debug_statistics()
	expect(stats.loaded_models == 1, "one loaded model")
	expect(stats.live_drawable_nodes == actual.drawables, "mesh instance count matches tree")
	expect(stats.live_mesh_resources == actual.meshes.size(), "unique mesh count shares fallback geometry")
	expect(stats.live_material_resources == actual.materials.size(), "unique material count")
	expect(stats.live_mask_viewports == actual.viewports - int(fallback), "mask viewport count")
	expect(stats.live_compositor_viewports == int(fallback), "compositor viewport count")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var initial := CubismBuildInfo.get_debug_statistics()
	if not initial.enabled:
		expect(initial.keys() == ["enabled"], "release exposes unavailability instead of zero measurements")
		finish()
		return
	for key: String in OWNED: expect(initial[key] == 0, "empty baseline " + key)
	var view := SubViewport.new()
	view.size = Vector2i(256, 256)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var model := CubismModel2D.new()
	model.playback_process_mode = CubismModel2D.MANUAL
	model.enable_physics = false
	model.enable_pose = false
	view.add_child(model)
	expect(model.load_model(load("res://imported-model.res")) == OK, "load fixture")
	var canvas := model.get_canvas_info()
	model.scale = Vector2.ONE * 220.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	model.position = Vector2(128, 128)
	model.advance(0.01)
	verify_tree(model, false)
	# Start a fresh process frame before checking additive update counters.
	var loaded_frame := Engine.get_process_frames()
	while Engine.get_process_frames() == loaded_frame: await process_frame
	model.advance(0.01)
	var first := CubismBuildInfo.get_debug_statistics()
	expect(first.vertex_bytes_uploaded_last_frame > 0, "real geometry upload recorded")
	expect(first.model_update_usec > 0 and first.renderer_update_usec > 0, "both CPU phases measured")
	expect(first.mask_redraws_last_frame == first.live_mask_viewports, "visible mask requests counted once")
	model.advance(0.01)
	var second := CubismBuildInfo.get_debug_statistics()
	expect(second.frame_id == first.frame_id, "manual updates share process frame")
	expect(second.vertex_bytes_uploaded_last_frame == 2 * first.vertex_bytes_uploaded_last_frame, "all manual uploads counted")
	expect(second.mask_redraws_last_frame == first.mask_redraws_last_frame, "duplicate mask requests deduplicated")
	await process_frame
	var idle := CubismBuildInfo.get_debug_statistics()
	expect(idle.vertex_bytes_uploaded_last_frame == 0 and idle.model_update_usec == 0 and idle.renderer_update_usec == 0, "fresh idle frame has zero update work")
	model.hide()
	model.advance(0.01)
	expect(CubismBuildInfo.get_debug_statistics().mask_redraws_last_frame == 0, "hidden mask updates not requested")
	model.show()
	model.rendering_mode = CubismModel2D.SUBVIEWPORT_FALLBACK
	model.advance(0.01)
	for frame in 3: await RenderingServer.frame_post_draw
	expect(model.rendering_error.is_empty(), "fallback supported")
	verify_tree(model, true)
	var handle := model.play_motion(&"Cue/0", CubismMotionPriority.FORCE, true)
	expect(handle.get_error() == OK and CubismBuildInfo.get_debug_statistics().live_motion_handles == 1, "owned motion handle counted")
	model.unload_model()
	for key: String in OWNED: expect(CubismBuildInfo.get_debug_statistics()[key] == 0, "unload clears ownership " + key)
	expect(handle.is_finished(), "caller-retained finished handle does not count as runtime owned")
	view.free()
	finish()

func finish() -> void:
	print("CUBISM_DEBUG_STATISTICS checks=", checks, " failures=", failures.size())
	for failure in failures: printerr(failure)
	if failures.is_empty(): print("CUBISM_DEBUG_STATISTICS_PASS")
	quit(0 if failures.is_empty() else 1)
