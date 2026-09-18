extends SceneTree

func _initialize() -> void:
    var probe_script: Script = load("res://effects_probe.cs")
    if probe_script == null:
        printerr("EFFECTS_PROBE_FAIL: C# script unavailable")
        quit(2)
        return
    var probe: Node = probe_script.new()
    root.add_child(probe)
