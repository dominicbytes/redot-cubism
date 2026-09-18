# SPDX-License-Identifier: MIT
extends CharacterBody2D

const Preset = preload("character_preset.gd")
@export var move_speed := 170.0
@onready var model: CubismModel2D = $Model
@onready var controller: CubismCharacterController = $Controller
@onready var interaction: Area2D = $InteractionArea
@onready var name_tag: Label = $NameTag
var preset: Preset
var ids: Dictionary
var configured := false
var player_controlled := false
var walking := false
var model_scale := 1.0

func configure(value: Preset, controlled: bool) -> Dictionary:
	preset = value
	player_controlled = controlled
	if preset == null: return {"ok": false, "message": "Assign a character preset in the scene inspector."}
	var result := preset.configure(model, controller)
	configured = result.ok
	if not configured: return result
	ids = result.ids
	var canvas := model.get_canvas_info()
	model_scale = 230.0 / maxf(canvas.size_in_pixels.x, canvas.size_in_pixels.y)
	model.scale = Vector2.ONE * model_scale
	model.position = Vector2(0, -110)
	name_tag.text = "You" if controlled else preset.display_name
	if not controlled: model.modulate = Color("c6ddd9")
	queue_redraw()
	return result

func _physics_process(_delta: float) -> void:
	# One z value for the complete actor, including its native model drawables.
	z_index = clampi(roundi(position.y), -4096, 4096)
	if not configured: return
	var direction := Vector2.ZERO
	if player_controlled and not controller.is_speaking():
		direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		direction += Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		direction = direction.limit_length()
	velocity = direction * move_speed
	move_and_slide()
	if controller.is_speaking():
		walking = false
		return
	var should_walk := not direction.is_zero_approx()
	if should_walk != walking:
		walking = should_walk
		controller.stop_speaking(0)
		model.stop_motion(0)
		if walking and ids.walk != &"":
			model.play_motion(ids.walk, CubismMotionPriority.NORMAL, true, 1)
		elif ids.idle != &"":
			controller.return_to_idle()
	if walking:
		if direction.x != 0: model.scale.x = model_scale * signf(direction.x)
		controller.look_at_screen_position(get_global_transform_with_canvas() * (model.position + direction * 120))

func talk() -> CubismSpeechHandle:
	if not configured: return null
	walking = false
	if preset.voice:
		return controller.speak(preset.voice, ids.talk, ids.expression, CubismLipSyncProfile.new())
	return controller.perform(ids.talk, ids.expression)

func react() -> CubismSpeechHandle:
	if not configured: return null
	walking = false
	return controller.perform(ids.reaction, ids.expression)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 28, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	# This ring shows the independent foot collider, not the Live2D mesh bounds.
	draw_circle(Vector2.ZERO, 14, Color("80dec580"), false, 1.5, true)
