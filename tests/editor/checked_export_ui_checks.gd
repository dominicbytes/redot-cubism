# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	if OS.get_cmdline_user_args().has("--checked-export-ui-test"):
		_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var invoked: bool = false
	for menu: PopupMenu in get_tree().root.find_children("*", "PopupMenu", true, false):
		for index in menu.item_count:
			if menu.get_item_text(index) == "Validate and Export Cubism":
				menu.index_pressed.emit(index)
				invoked = true
				break
		if invoked:
			break
	assert(invoked, "Native checked-export menu action must exist")
	var dialog: ConfirmationDialog
	for candidate: ConfirmationDialog in get_tree().root.find_children("*", "ConfirmationDialog", true, false):
		if candidate.title == "Validate and Export Cubism":
			dialog = candidate
			break
	assert(dialog != null and dialog.visible)
	var controller: Node = dialog.get_parent()
	var presets: OptionButton = controller.get("_presets")
	assert(presets.item_count > 0 and presets.get_item_text(0) == "Textures")
	var python: LineEdit = controller.get("_python")
	python.text = OS.get_environment("CUBISM_PYTHON_BIN")
	var mode: OptionButton = controller.get("_mode")
	mode.select(1 if OS.get_environment("CUBISM_UI_MODE") == "debug" else 0)
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	assert(dialog.size.y < 700, "Export dialog must fit a normal editor window")
	assert(dialog.get_texture().get_image().save_png(OS.get_environment("CUBISM_UI_BEFORE")) == OK)
	dialog.confirmed.emit()
	var directory: EditorFileDialog = controller.get("_directory")
	assert(directory.visible)
	directory.dir_selected.emit(OS.get_environment("CUBISM_UI_OUTPUT"))
	directory.hide()
	assert(int(controller.get("_pid")) >= 0)
	while int(controller.get("_pid")) >= 0:
		await get_tree().create_timer(0.5).timeout
	var report_path: String = str(controller.get("_report"))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path)) if FileAccess.file_exists(report_path) else null
	if not parsed is Dictionary:
		push_error("Checked export did not write a valid status report: " + report_path)
		get_tree().quit(1)
		return
	var status: Dictionary = parsed
	if status.get("status") != "PASS":
		push_error("Checked export failed: " + JSON.stringify(status))
		get_tree().quit(1)
		return
	var label: Label = controller.get("_status")
	if not label.text.contains("Export passed"):
		push_error("Checked export result did not report success: " + label.text)
		get_tree().quit(1)
		return
	RenderingServer.force_draw(false)
	assert(dialog.size.y < 700, "Export result must not create an oversized dialog")
	assert(dialog.get_texture().get_image().save_png(OS.get_environment("CUBISM_UI_AFTER")) == OK)
	print("CUBISM_CHECKED_EXPORT_UI_PASS")
	get_tree().quit()
