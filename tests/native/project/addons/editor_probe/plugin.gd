@tool
extends EditorPlugin

func _enter_tree() -> void:
	if not ClassDB.class_exists("GDCubismPlugin"):
		push_error("CUBISM_NATIVE_FAIL: editor plugin missing")
		return
	print("CUBISM_NATIVE_EDITOR_PASS")

func _exit_tree() -> void:
	print("CUBISM_NATIVE_EDITOR_EXIT")
