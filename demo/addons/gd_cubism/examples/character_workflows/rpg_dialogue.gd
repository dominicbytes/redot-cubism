# SPDX-License-Identifier: MIT
extends Node2D

const Preset = preload("character_preset.gd")
const Actor = preload("rpg_character.gd")
const PLANTER := Rect2(510, 320, 250, 90)
@export var character: Preset
@onready var player: Actor = $Characters/Player
@onready var guide: Actor = $Characters/Guide
@onready var interface: CanvasLayer = $Interface
var ui: Dictionary
var configured := false
var active: CubismSpeechHandle
var talk_button: Button

func _ready() -> void:
	ui = interface.build("A meeting in the courtyard", "WASD / arrows: walk     E / Enter: talk     R: react")
	talk_button = interface.add_button(ui, "Talk", talk)
	interface.add_button(ui, "React", react)
	var first := player.configure(character, true)
	var second := guide.configure(character, false)
	configured = first.ok and second.ok
	ui.speaker.text = character.display_name if character else "Character setup"
	ui.line.text = "Walk over to your companion. The rings mark each character's collision shape." if configured else first.message
	_make_wall(PLANTER, Color("36594f"), true)
	_make_wall(Rect2(16, 156, 1248, 12), Color("294451"))
	_make_wall(Rect2(16, 510, 1248, 12), Color("294451"))
	_make_wall(Rect2(16, 156, 12, 366), Color("294451"))
	_make_wall(Rect2(1252, 156, 12, 366), Color("294451"))
	queue_redraw()

func _make_wall(rect: Rect2, color: Color, raised := false) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position
	body.collision_layer = 1
	body.collision_mask = 2
	body.z_index = int(rect.end.y) if raised else 0
	add_child(body)
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(rect.size.x, 0), rect.size, Vector2(0, rect.size.y)])
	polygon.color = color
	body.add_child(polygon)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.size / 2
	body.add_child(collision)

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1929"))
	draw_rect(Rect2(28, 168, 1224, 342), Color("253d43"))
	for x in range(28, 1253, 64): draw_line(Vector2(x, 168), Vector2(x, 510), Color("304b50"), 1)
	for y in range(168, 511, 64): draw_line(Vector2(28, y), Vector2(1252, y), Color("304b50"), 1)

func _physics_process(_delta: float) -> void:
	var near := configured and guide.interaction.get_overlapping_bodies().has(player)
	talk_button.disabled = not near or (active != null and not active.is_finished())
	if configured and (active == null or active.is_finished()):
		ui.status.text = "E / Enter to talk" if near else "Move closer to your companion"
	if near:
		guide.controller.look_at_screen_position(player.model.get_global_transform_with_canvas().origin)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.is_action_pressed("ui_accept"):
			talk()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			react()
			get_viewport().set_input_as_handled()

func talk() -> void:
	if not configured or not guide.interaction.get_overlapping_bodies().has(player) or (active != null and not active.is_finished()): return
	ui.line.text = "The path around the planter is clear. I'll meet you on the other side."
	active = guide.talk()
	ui.status.text = "Speaking" if character.voice else "Playing motion"
	if active.is_finished(): _talk_finished(active.get_reason(), active)
	else: active.finished.connect(_talk_finished.bind(active), CONNECT_ONE_SHOT)

func _talk_finished(reason: int, handle: CubismSpeechHandle) -> void:
	if handle != active: return
	ui.line.text = "Ready when you are." if reason == CubismSpeechHandle.COMPLETED else "We'll continue in a moment."

func react() -> void:
	if not configured: return
	player.react()
