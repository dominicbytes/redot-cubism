# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	check(ClassDB.class_exists("CubismAbiNode"), "Native Node2D not registered")
	check(ClassDB.class_exists("CubismAbiResource"), "Native Resource not registered")
	if not OS.has_feature("editor"):
		check(not ClassDB.class_exists("CubismAbiEditorPlugin"), "Editor class registered in export template")
	if failures > 0:
		get_tree().quit(1)
		return
	var resource := CubismAbiResource.new()
	resource.source = "日本語/model.model3.json"
	check(ResourceSaver.save(resource, "user://roundtrip.tres") == OK, "Resource save failed")
	var loaded: Resource = load("user://roundtrip.tres")
	check(loaded != null and loaded.get("source") == resource.source, "Native Resource round trip failed")
	var model: CubismAbiNode = load("res://override.gd").new()
	add_child(model)
	for index in range(4):
		await get_tree().process_frame
	check(model.get_ticks() > 0, "Script override disabled native processing")
	check(model.get("ready_calls") == 1, "Expected one ready notification")
	var ticks: int = model.get_ticks()
	get_tree().paused = true
	for index in range(4):
		await get_tree().process_frame
	check(model.get_ticks() == ticks, "Scene pause did not stop native processing")
	get_tree().paused = false
	remove_child(model)
	add_child(model)
	for index in range(4):
		await get_tree().process_frame
	check(model.get_entries() == 2, "Tree reentry did not reach native notification")
	check(model.get_ticks() > ticks, "Tree reentry did not resume native processing")
	check(model.get("ready_calls") == 1, "Test accidentally requested a second ready")
	model.free()
	var ordinary: Resource = load("res://ordinary.json")
	check(ordinary != null and ordinary.has_meta("generic_json") and not ordinary is CubismAbiResource, "Cubism importer claimed ordinary JSON")
	var imported: Resource = load("res://hero.model3.json")
	check(imported is CubismAbiResource, "Multipart suffix failed automatic import")
	if imported != null:
		check(imported.get("source") == "res://hero.model3.json", "Imported metadata lost")
	var uid: int = ResourceLoader.get_resource_uid("res://hero.model3.json")
	check(uid != -1, "Imported resource has no UID")
	print("CUBISM_ABI_UID:", uid)
	check(FileAccess.get_file_as_string("res://probe.raw") == "SDK-free export injection fixture\n", "Raw export dependency missing")
	print("CUBISM_ABI_PASS" if failures == 0 else "CUBISM_ABI_FAIL")
	get_tree().quit(0 if failures == 0 else 1)
