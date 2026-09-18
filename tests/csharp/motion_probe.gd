extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var probe = load("res://MotionProbe.cs").new()
	root.add_child(probe)
