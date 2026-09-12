# SPDX-License-Identifier: MIT
@tool
extends Node

var _dialog: ConfirmationDialog
var _directory: EditorFileDialog
var _presets: OptionButton
var _mode: OptionButton
var _python: LineEdit
var _status: Label
var _pid: int = -1
var _report: String = ""
var _timer: Timer

func _ready() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Validate and Export Cubism"
	_dialog.ok_button_text = "Choose output and export"
	_dialog.dialog_hide_on_ok = false
	add_child(_dialog)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(580, 260)
	_dialog.add_child(content)
	for caption: String in ["Existing export preset", "Build mode", "Python 3.10+ executable"]:
		var label := Label.new()
		label.text = caption
		content.add_child(label)
		if caption == "Existing export preset":
			_presets = OptionButton.new()
			content.add_child(_presets)
		elif caption == "Build mode":
			_mode = OptionButton.new()
			_mode.add_item("Release")
			_mode.add_item("Debug")
			content.add_child(_mode)
		else:
			_python = LineEdit.new()
			_python.text = OS.get_environment("CUBISM_PYTHON_BIN")
			if _python.text.is_empty():
				_python.text = "python" if OS.get_name() == "Windows" else "python3"
			content.add_child(_python)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(580, 80)
	_status.size = Vector2(580, 80)
	content.add_child(_status)
	_directory = EditorFileDialog.new()
	_directory.title = "Choose the complete build output directory"
	_directory.access = EditorFileDialog.ACCESS_FILESYSTEM
	_directory.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_dialog.add_child(_directory)
	_dialog.confirmed.connect(_choose_directory)
	_directory.dir_selected.connect(_start)
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_poll)
	add_child(_timer)

func show_export_dialog() -> void:
	if _pid < 0:
		_presets.clear()
		var config := ConfigFile.new()
		if config.load("res://export_presets.cfg") == OK:
			var index: int = 0
			while config.has_section("preset." + str(index)):
				_presets.add_item(config.get_value("preset." + str(index), "name", ""))
				index += 1
		_dialog.get_ok_button().disabled = _presets.item_count == 0
		_status.text = "Save the project and configure an export preset first." if _presets.item_count == 0 else "Save your changes first. Validation and playback checks must pass before the build is replaced. Previous builds and failed-run logs are retained."
	_dialog.popup_centered()

func _choose_directory() -> void:
	if _pid < 0 and _presets.item_count > 0:
		_directory.popup_file_dialog()

func _start(output: String) -> void:
	if _pid >= 0:
		return
	_report = output.get_base_dir().path_join(".cubism-export-status-" + str(Time.get_ticks_usec()) + ".json")
	var args: PackedStringArray = [ProjectSettings.globalize_path("res://addons/gd_cubism/editor/checked_export.py"),
		"--project", ProjectSettings.globalize_path("res://"), "--preset", _presets.get_item_text(_presets.selected),
		"--output", output, "--mode", "debug" if _mode.selected == 1 else "release",
		"--redot-bin", OS.get_executable_path(), "--report", _report]
	_pid = OS.create_process(_python.text.strip_edges(), args)
	if _pid < 0:
		_status.text = "Could not start Python. Set the Python executable and try again."
		return
	_dialog.get_ok_button().disabled = true
	_timer.start()
	_status.text = "Export checks are running. You can close this dialog while they finish."

func _poll() -> void:
	if _pid < 0 or OS.is_process_running(_pid):
		return
	_pid = -1
	_timer.stop()
	_dialog.get_ok_button().disabled = false
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(_report)) if FileAccess.file_exists(_report) else null
	if not result is Dictionary:
		_status.text = "Export process ended without a result. Check the Python executable and the editor Output log."
	elif result.get("status") == "PASS":
		_status.text = "Export passed and the build is ready:\n" + str(result.output) + "\nReports: " + str(result.work)
	else:
		_status.text = "Export failed: " + str(result.get("error", "Unknown failure")) + "\nReports: " + str(result.get("work", ""))
	_dialog.popup_centered()
