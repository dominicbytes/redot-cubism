@tool
extends EditorPlugin

func _enter_tree() -> void:
	if not ClassDB.class_exists("GDCubismPlugin"):
		push_error("CUBISM_NATIVE_FAIL: editor plugin missing")
		return
	print("CUBISM_NATIVE_EDITOR_REGISTERED")
	_probe.call_deferred()

func _probe() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture.model))
	for texture: String in manifest.FileReferences.Textures:
		if not ResourceLoader.exists(fixture.model.get_base_dir().path_join(texture), "Texture2D"):
			# Initial discovery runs before texture import. The harness requires
			# the creation/save check on the subsequent editor restart.
			print("CUBISM_NATIVE_EDITOR_WAITING_IMPORT")
			return
	var scene := Node2D.new()
	scene.name = "CubismEditorProbe"
	var model := GDCubismUserModel.new()
	model.name = "Model"
	scene.add_child(model)
	model.owner = scene
	model.assets = fixture.model
	var packed := PackedScene.new()
	if not model.is_initialized() or packed.pack(scene) != OK or ResourceSaver.save(packed, "res://editor-probe.tscn") != OK:
		push_error("CUBISM_NATIVE_FAIL: editor model creation/save failed: " + str(model.get_last_error()))
		scene.free()
		return
	scene.free()
	if FileAccess.get_file_as_string("res://editor-probe.tscn").count("[node ") != 2:
		push_error("CUBISM_NATIVE_FAIL: generated runtime nodes were serialized")
		return
	print("CUBISM_NATIVE_EDITOR_PASS")

func _exit_tree() -> void:
	print("CUBISM_NATIVE_EDITOR_EXIT")
