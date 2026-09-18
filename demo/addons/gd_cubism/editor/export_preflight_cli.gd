# SPDX-License-Identifier: MIT
@tool
extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or args[0] != "--cubism-preflight":
		printerr("Usage: --headless --editor --path PROJECT -- --cubism-preflight PRESET REPORT")
		get_tree().quit(2)
		return
	await get_tree().create_timer(1.0).timeout
	var filesystem: EditorFileSystem = EditorInterface.get_resource_filesystem()
	while filesystem != null and filesystem.is_scanning():
		await get_tree().process_frame
	var validator = load("res://addons/gd_cubism/editor/export_preflight.gd").new()
	var result: Dictionary = validator.validate_preset(args[1])
	var report: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
	if report == null:
		printerr("Cannot write Cubism export preflight report: " + args[2])
		get_tree().quit(2)
		return
	report.store_string(JSON.stringify(result, "\t") + "\n")
	report.close()
	print("CUBISM_EXPORT_PREFLIGHT_PASS" if result.ok else "CUBISM_EXPORT_PREFLIGHT_FAIL")
	get_tree().quit(0 if result.ok else 1)
