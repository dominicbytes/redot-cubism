extends SceneTree

func _initialize() -> void:
	if not ClassDB.class_exists("GDCubismUserModel"):
		push_error("CUBISM_EMPTY_FAIL: extension class missing")
		quit(1)
		return
	# No model is constructed: extension startup and shutdown must stand alone.
	print("CUBISM_EMPTY_PASS")
	quit()
