# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

var failures: Array[String] = []
var checks := 0
var fixture: Dictionary
const SCENE := "res://editor-workflow.tscn"

func expect(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label)
	return value

func settle() -> void:
	for frame in 4: await get_tree().process_frame

func find_plugin(node: Node) -> Node:
	if node.get_class() == "GDCubismPlugin": return node
	for child: Node in node.get_children(true):
		var found := find_plugin(child)
		if found != null: return found
	return null

func empty_click() -> void:
	var viewport := EditorInterface.get_editor_viewport_2d()
	expect(viewport != null and viewport.size.x > 8 and viewport.size.y > 8, "2D viewport can receive empty-scene click")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(8, 8)
	event.global_position = event.position
	event.pressed = true
	Input.parse_input_event(event)
	await settle()
	event.pressed = false
	Input.parse_input_event(event)
	# Dismiss any editor menu opened by the synthetic top-left click.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	escape = escape.duplicate()
	escape.pressed = false
	Input.parse_input_event(escape)
	await settle()
	expect(EditorInterface.get_edited_scene_root() == null, "click preserves empty editor")

func select(node: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)
	await settle()
	expect(EditorInterface.get_selection().get_selected_nodes().has(node), "node selected in editor")

func _enter_tree() -> void:
	run.call_deferred()

func run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://editor-workflow-fixture.json"))
	EditorInterface.set_main_screen_editor("2D")
	await settle()
	var plugin := find_plugin(get_tree().root)
	if not expect(plugin != null and plugin.is_processing_input(), "native editor plugin receives input"):
		finish()
		return
	if not expect(EditorInterface.get_edited_scene_root() == null, "editor opens without a scene"):
		finish()
		return
	await empty_click()
	var source := Node2D.new()
	source.name = "EditorWorkflow"
	var node := CubismModel2D.new()
	node.name = "Character"
	source.add_child(node)
	node.owner = source
	var packed := PackedScene.new()
	expect(packed.pack(source) == OK, "pack native preferred node")
	expect(ResourceSaver.save(packed, SCENE) == OK, "write scene through engine")
	source.free()
	EditorInterface.open_scene_from_path(SCENE)
	await settle()
	var scene := EditorInterface.get_edited_scene_root()
	if not expect(scene != null and scene.has_node("Character"), "open scene with preferred node"):
		finish()
		return
	node = scene.get_node("Character")
	await select(node)
	var model := load(fixture.resource) as CubismModelResource
	var manager := get_undo_redo()
	manager.create_action("Assign Cubism model", UndoRedo.MERGE_DISABLE, node)
	manager.add_do_property(node, &"model", model)
	manager.add_undo_property(node, &"model", null)
	manager.commit_action()
	await settle()
	expect(node.is_ready(), "assign model through editor undo manager")
	var history := manager.get_history_undo_redo(manager.get_object_history_id(node))
	expect(history.undo(), "undo assignment")
	await settle()
	expect(node.model == null and not node.is_ready(), "undo unloads native model")
	expect(history.redo(), "redo assignment")
	await settle()
	expect(node.is_ready(), "redo reloads native model")
	expect(node.load_model(CubismModelResource.new()) != OK, "invalid resource rejected")
	await settle()
	expect(node.get_model_state() == CubismModel2D.ERROR, "invalid model state visible")
	node.model = null
	expect(not node.is_ready(), "clear invalid model")
	expect(node.load_model(model) == OK, "valid model recovers")
	var canvas := node.get_canvas_info()
	node.scale = Vector2.ONE * 300.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	node.position = Vector2(180, 240)
	node.debug_draw_bounds = true
	node.debug_draw_hit_areas = true
	for cycle in 5:
		EditorInterface.get_selection().clear()
		await settle()
		await select(node)
	EditorInterface.mark_scene_as_unsaved()
	expect(EditorInterface.save_scene() == OK, "save assigned model scene")
	var saved := ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	expect(saved.get_state().get_node_count() == 2, "saved scene excludes generated model drawables")
	var saved_position := node.position
	var handle := node.play_motion(fixture.motion, CubismMotionPriority.FORCE, true)
	expect(handle.get_error() == OK, "preview motion accepted")
	expect(node.set_expression(fixture.expression, 0) == OK, "preview expression accepted")
	await get_tree().create_timer(0.2).timeout
	expect(handle.get_elapsed_seconds() > 0, "editor preview advances motion")
	if fixture.has("capture"):
		await RenderingServer.frame_post_draw
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		expect(image.save_png(fixture.capture) == OK, "save editor capture")
	EditorInterface.close_scene()
	await settle()
	expect(EditorInterface.get_edited_scene_root() == null, "close scene during preview")
	expect(not is_instance_valid(node) and handle.is_finished(), "close destroys model and finishes retained handle")
	await empty_click()
	EditorInterface.open_scene_from_path(SCENE)
	await settle()
	scene = EditorInterface.get_edited_scene_root()
	node = scene.get_node("Character")
	expect(node.is_ready() and node.position == saved_position, "reopen restores model and transform")
	await select(node)
	node.free()
	await settle()
	expect(not is_instance_valid(node), "delete selected model")
	EditorInterface.mark_scene_as_unsaved()
	expect(EditorInterface.save_scene() == OK, "save scene after deletion")
	# Exercise the compatibility node handled by GDCubismPlugin itself.
	var legacy := GDCubismUserModel.new()
	legacy.name = "LegacyCharacter"
	scene.add_child(legacy)
	legacy.owner = scene
	legacy.assets = fixture.legacy_source
	expect(legacy.get_model_state() == GDCubismUserModel.READY, "legacy source loads in editor")
	legacy.scale = Vector2.ONE * 0.1
	await select(legacy)
	legacy.free()
	await settle()
	expect(not is_instance_valid(legacy), "delete selected legacy model")
	legacy = GDCubismUserModel.new()
	legacy.name = "LegacyClose"
	scene.add_child(legacy)
	legacy.owner = scene
	legacy.assets = fixture.legacy_source
	await select(legacy)
	EditorInterface.mark_scene_as_unsaved()
	expect(EditorInterface.save_scene() == OK, "save legacy model scene")
	EditorInterface.close_scene()
	await settle()
	expect(not is_instance_valid(legacy), "close selected legacy model")
	await empty_click()
	var stats := CubismBuildInfo.get_debug_statistics()
	if stats.enabled:
		for key: String in ["loaded_models", "live_drawable_nodes", "live_mesh_resources", "live_material_resources", "live_mask_viewports", "live_compositor_viewports", "live_motion_handles"]:
			expect(stats[key] == 0, "editor workflow releases " + key)
	finish()

func finish() -> void:
	print("CUBISM_EDITOR_WORKFLOW checks=", checks, " failures=", failures.size())
	for failure in failures: printerr(failure)
	if failures.is_empty(): print("CUBISM_EDITOR_WORKFLOW_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
