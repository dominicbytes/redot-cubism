# SPDX-License-Identifier: MIT
extends Node2D

const Preset = preload("character_preset.gd")
const SAVE_PATH := "user://cubism_vn_checkpoint.json"
const LINES := ["The last train hasn't left yet. We still have time.",
	"Take a breath. I'll wait here while you decide.", "All right. Let's see where this journey takes us."]
@export var character: Preset
@onready var model: CubismModel2D = $Model
@onready var controller: CubismCharacterController = $Controller
@onready var interface: CanvasLayer = $Interface
var ui: Dictionary
var ids: Dictionary
var configured := false
var line_index := -1
var active: CubismSpeechHandle
var next_button: Button
var pause_button: Button
var hide_button: Button

func _ready() -> void:
	ui = interface.build("The last train", "A small visual-novel scene • Move the pointer to look around")
	next_button = interface.add_button(ui, "Next line", next_line)
	pause_button = interface.add_button(ui, "Pause", toggle_pause)
	hide_button = interface.add_button(ui, "Hide", toggle_visibility)
	interface.add_button(ui, "Save", save_checkpoint)
	interface.add_button(ui, "Restore", restore_checkpoint)
	var result := character.configure(model, controller) if character else {"ok": false, "message": "Assign a character preset in the scene inspector."}
	configured = result.ok
	ui.line.text = result.message
	if configured:
		ids = result.ids
		ui.speaker.text = character.display_name
		ui.line.text = "When you're ready, begin the conversation."
		fit_character()
	get_viewport().size_changed.connect(fit_character)
	model.visibility_changed.connect(_update_buttons)
	_update_buttons()
	queue_redraw()

func fit_character() -> void:
	if not configured: return
	var canvas := model.get_canvas_info()
	var size := get_viewport_rect().size
	model.position = Vector2(size.x * 0.5, size.y * 0.45)
	model.scale = Vector2.ONE * size.y * 0.72 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1929"))
	draw_rect(Rect2(Vector2(0, size.y * 0.66), Vector2(size.x, size.y * 0.34)), Color("20344a"))
	for x in range(60, int(size.x), 140):
		draw_line(Vector2(x, 145), Vector2(x, size.y * 0.66), Color("253e55"), 2)
		draw_circle(Vector2(x, 150), 4, Color("eacb87"))

func _unhandled_input(event: InputEvent) -> void:
	if configured and event is InputEventMouseMotion:
		controller.look_at_screen_position(event.position)
	if event.is_action_pressed("ui_accept"):
		next_line()
		get_viewport().set_input_as_handled()

func next_line() -> void:
	if not configured or (active != null and not active.is_finished()): return
	controller.show_character()
	line_index = (line_index + 1) % LINES.size()
	ui.line.text = LINES[line_index]
	if character.voice:
		active = controller.speak(character.voice, ids.talk, ids.expression, CubismLipSyncProfile.new())
	else:
		active = controller.perform(ids.talk, ids.expression)
	ui.status.text = "Speaking" if character.voice else "Playing motion"
	_update_buttons()
	# Failures can already be terminal; do not connect an await that will never fire.
	if active.is_finished(): _cue_finished(active.get_reason(), active)
	else: active.finished.connect(_cue_finished.bind(active), CONNECT_ONE_SHOT)

func _cue_finished(reason: int, handle: CubismSpeechHandle) -> void:
	if handle != active: return
	ui.status.text = "Ready" if reason == CubismSpeechHandle.COMPLETED else "Conversation interrupted"
	_update_buttons()

func _update_buttons() -> void:
	next_button.disabled = not configured or (active != null and not active.is_finished())
	pause_button.disabled = not configured
	hide_button.disabled = not configured
	pause_button.text = "Resume" if controller.paused else "Pause"
	hide_button.text = "Hide" if model.visible else "Show"

func toggle_pause() -> void:
	if not configured: return
	controller.paused = not controller.paused
	_update_buttons()

func toggle_visibility() -> void:
	if not configured: return
	if model.visible: controller.hide_character(&"fade")
	else: controller.show_character(&"fade")
	ui.status.text = "Character visibility changed"

func save_checkpoint() -> void:
	if not configured: return
	var captured := controller.capture_state()
	if not captured.ok:
		ui.status.text = "Wait for the current cue or fade to finish"
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		ui.status.text = "The checkpoint could not be saved"
		return
	file.store_string(JSON.stringify({"line": line_index, "character": captured.state}))
	file.close()
	ui.status.text = "Checkpoint saved"

func restore_checkpoint() -> void:
	if not configured or not FileAccess.file_exists(SAVE_PATH):
		ui.status.text = "Save a checkpoint first"
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not saved is Dictionary or not saved.get("character") is Dictionary or not (saved.get("line") is float or saved.get("line") is int):
		ui.status.text = "The checkpoint is invalid"
		return
	var index: float = saved.line
	if not is_finite(index) or index != floor(index) or index < -1 or index >= LINES.size():
		ui.status.text = "The checkpoint is invalid"
		return
	var error := controller.restore_state(saved.character)
	if error != OK:
		ui.status.text = "The checkpoint could not be restored: " + error_string(error)
		return
	active = null
	line_index = int(index)
	ui.line.text = LINES[line_index] if line_index >= 0 else "When you're ready, begin the conversation."
	ui.status.text = "Checkpoint restored"
	_update_buttons()
