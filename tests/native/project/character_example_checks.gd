# SPDX-License-Identifier: MIT
extends SceneTree

const BASE := "res://addons/gd_cubism/examples/character_workflows/"
const Preset = preload("res://addons/gd_cubism/examples/character_workflows/character_preset.gd")
var checks := 0
var failures: Array[String] = []
var playbacks: Array[WeakRef] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value and not failures.has(label): failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func released() -> bool:
	for playback in playbacks:
		if playback.get_ref() != null: return false
	return true

func track(controller: CubismCharacterController) -> void:
	var playback: AudioStreamPlayback = controller.get_node("Voice").get_stream_playback()
	if playback: playbacks.append(weakref(playback))

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func prepare() -> void:
	var preset := Preset.new()
	preset.model = load("res://imported-model.res")
	preset.idle_motion = &"Cue/1"
	preset.talk_motion = &"Cue/0"
	preset.walk_motion = &"Cue/1"
	preset.reaction_motion = &"Cue/0"
	preset.talk_expression = &"Add"
	var voice := AudioStreamWAV.new()
	voice.format = AudioStreamWAV.FORMAT_16_BITS
	voice.mix_rate = 8000
	var samples := PackedByteArray()
	samples.resize(16000 * 2)
	for frame in 16000:
		samples.encode_s16(frame * 2, int(sin(frame * TAU * 220.0 / 8000.0) * 12000))
	voice.data = samples
	preset.voice = voice
	for filename: String in ["visual_novel", "rpg_dialogue"]:
		var scene: Node = load(BASE + filename + ".tscn").instantiate()
		scene.character = preset
		var packed := PackedScene.new()
		expect(packed.pack(scene) == OK, "pack configured " + filename)
		expect(ResourceSaver.save(packed, "res://example-" + filename + ".tscn") == OK, "save configured " + filename)
		scene.free()

func capture(filename: String) -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--captures")
	if index < 0: return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	expect(picture != null and not picture.is_empty(), "render " + filename)
	if picture:
		expect(picture.save_png(args[index + 1].path_join(filename + ".png")) == OK, "save " + filename)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	Engine.max_fps = 60
	if OS.get_cmdline_user_args().has("--prepare-scenes"): prepare()
	# Public scenes must open without proprietary assets or a hanging cue.
	for filename: String in ["visual_novel", "rpg_dialogue"]:
		var empty: Node = load(BASE + filename + ".tscn").instantiate()
		root.add_child(empty)
		await process_frame
		expect(not empty.configured and "Assign an imported model" in empty.ui.line.text, filename + " explains missing model")
		await capture(filename + "-setup")
		empty.free()
	var vn: Node = load("res://example-visual_novel.tscn").instantiate()
	root.add_child(vn)
	await process_frame
	expect(vn.configured and vn.controller.is_idle(), "VN loads exported preset and starts idle")
	expect(vn.model.enable_eye_blink and vn.model.enable_breath and vn.model.enable_physics and vn.model.enable_pose, "VN enables companion effects")
	vn.next_button.pressed.emit()
	track(vn.controller)
	await wait_seconds(0.3)
	expect(vn.line_index == 0 and vn.active.get_error() == OK and not vn.active.is_finished(), "Next line starts voice and motion")
	expect(vn.controller.get_node("Voice").playing and vn.controller.get_node("LipSync").get_envelope() > 0, "recorded audio drives lip envelope")
	expect(vn.controller.get_motion_handle().get_motion_id() == &"Cue/0", "talk motion selected")
	var cue: CubismMotionHandle = vn.controller.get_motion_handle()
	var cue_time: float = cue.get_elapsed_seconds()
	expect(cue_time > 0.05 and cue_time < 1.0 and not cue.is_finished(), "voiced talk motion is advancing")
	var ids: PackedStringArray = vn.model.get_parameter_ids()
	expect(ids.has("ParamHairFront") and ids.has("ParamMouthOpenY"), "Haru fixture exposes physics and mouth outputs")
	var hair_on: float = vn.model.get_parameter_value(&"ParamHairFront")
	var mouth_on: float = vn.model.get_parameter_value(&"ParamMouthOpenY")
	var control := CubismModel2D.new()
	control.playback_process_mode = CubismModel2D.MANUAL
	control.enable_physics = false
	root.add_child(control)
	var control_ready := control.load_model(vn.character.model) == OK
	expect(control_ready, "physics-off control loads the same imported model")
	if control_ready:
		var control_cue: CubismMotionHandle = control.play_motion(&"Cue/0", CubismMotionPriority.FORCE, false, 1)
		var cue_ready := control_cue != null and control_cue.get_error() == OK
		expect(cue_ready, "physics-off control starts the same talk motion")
		if cue_ready:
			control.advance(cue_time)
			var hair_off: float = control.get_parameter_value(&"ParamHairFront")
			var mouth_off: float = control.get_parameter_value(&"ParamMouthOpenY")
			var hair_delta := absf(hair_on - hair_off)
			var mouth_delta := mouth_on - mouth_off
			expect(is_finite(hair_on) and is_finite(hair_off) and is_finite(mouth_on) and is_finite(mouth_off), "voiced effect samples are finite")
			expect(hair_delta > 0.01, "authored Haru physics changes hair during a voiced talk cue")
			expect(mouth_delta > 0.05, "voice envelope changes mouth beyond the motion-only control")
			print("CUBISM_VN_EFFECT_CONTRAST ", JSON.stringify({"cue_seconds": cue_time, "hair_on": hair_on, "hair_off": hair_off, "hair_delta": hair_delta, "mouth_on": mouth_on, "mouth_off": mouth_off, "mouth_delta": mouth_delta}))
	control.free()
	vn.pause_button.pressed.emit()
	var paused_time: float = vn.controller.get_model_time()
	await wait_seconds(0.2)
	expect(vn.controller.get_model_time() == paused_time and vn.controller.get_node("Voice").stream_paused, "pause freezes character and voice")
	vn.pause_button.pressed.emit()
	await capture("visual_novel-speaking")
	await wait_seconds(2.2)
	expect(vn.active.is_finished() and vn.active.get_reason() == CubismSpeechHandle.COMPLETED and vn.controller.is_idle(), "voice completion returns VN to idle")
	vn.save_checkpoint()
	expect(vn.ui.status.text == "Checkpoint saved", "VN saves stable dialogue checkpoint")
	vn.next_button.pressed.emit()
	track(vn.controller)
	var interrupted: CubismSpeechHandle = vn.active
	vn.restore_checkpoint()
	await process_frame
	expect(interrupted.get_reason() == CubismSpeechHandle.INTERRUPTED and vn.line_index == 0 and vn.active == null, "restore cancels new cue and restores line")
	expect(vn.ui.status.text == "Checkpoint restored" and vn.controller.is_idle(), "stale completion cannot overwrite restored UI")
	vn.next_button.pressed.emit()
	track(vn.controller)
	var hidden: CubismSpeechHandle = vn.active
	vn.hide_button.pressed.emit()
	await wait_seconds(0.5)
	expect(hidden.get_reason() == CubismSpeechHandle.HIDDEN and not vn.model.visible and vn.hide_button.text == "Show", "Hide cancels voice and fades character")
	vn.hide_button.pressed.emit()
	await wait_seconds(0.5)
	expect(vn.model.visible and is_equal_approx(vn.model.modulate.a, 1), "Show restores full character opacity")
	# The same scene works with no audio assigned.
	vn.character = vn.character.duplicate()
	vn.character.voice = null
	vn.next_button.pressed.emit()
	await wait_seconds(1.4)
	expect(vn.active.get_reason() == CubismSpeechHandle.COMPLETED and vn.controller.is_idle(), "unvoiced VN cue completes")
	vn.free()
	var rpg: Node = load("res://example-rpg_dialogue.tscn").instantiate()
	root.add_child(rpg)
	await wait_seconds(0.1)
	expect(rpg.configured and rpg.player.controller.is_idle() and rpg.guide.controller.is_idle(), "RPG loads both independent characters")
	expect(rpg.player.model != rpg.guide.model and rpg.player.preset == rpg.guide.preset, "RPG shares configuration with separate native instances")
	expect(rpg.talk_button.disabled, "dialogue unavailable outside interaction area")
	var start: Vector2 = rpg.player.position
	Input.action_press("ui_left")
	await wait_seconds(0.3)
	Input.action_release("ui_left")
	expect(rpg.player.position.x < start.x - 30 and rpg.player.walking and rpg.player.model.scale.x < 0, "movement input selects walk and left facing")
	await wait_seconds(0.1)
	expect(not rpg.player.walking and rpg.player.controller.is_idle(), "released movement returns to idle")
	# Approach the planter from below. Enlarging artwork must not enlarge collision.
	rpg.player.position = Vector2(600, 475)
	rpg.player.model.scale *= 2
	Input.action_press("ui_up")
	await wait_seconds(0.65)
	Input.action_release("ui_up")
	await wait_seconds(0.1)
	expect(absf(rpg.player.position.y - 424.0) < 1, "14px foot collider blocks planter regardless of model scale")
	expect(rpg.player.get_node("CollisionShape2D").shape.radius == 14, "native artwork does not replace gameplay collider")
	rpg.player.model.scale = Vector2.ONE * rpg.player.model_scale
	rpg.player.position = rpg.guide.position + Vector2(-45, 30)
	await wait_seconds(0.1)
	expect(not rpg.talk_button.disabled and rpg.player.z_index > rpg.guide.z_index, "nearby lower character sorts in front and can talk")
	await capture("rpg-front")
	rpg.player.position.y = rpg.guide.position.y - 30
	await wait_seconds(0.1)
	expect(rpg.player.z_index < rpg.guide.z_index, "whole character sorts behind companion")
	await capture("rpg-behind")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	await wait_seconds(0.3)
	track(rpg.guide.controller)
	expect(rpg.active != null and rpg.guide.controller.is_speaking(), "E interacts with nearby companion")
	if rpg.active:
		expect(rpg.guide.controller.get_node("LipSync").get_envelope() > 0, "RPG voice drives lip sync")
	var guide_time: float = rpg.guide.controller.get_model_time()
	rpg.react()
	expect(rpg.player.controller.is_speaking(), "hit reaction starts on player")
	await wait_seconds(0.2)
	expect(rpg.guide.controller.get_model_time() > guide_time and not rpg.active.is_finished(), "player reaction does not interrupt companion voice")
	await wait_seconds(2.0)
	expect(rpg.active.get_reason() == CubismSpeechHandle.COMPLETED and rpg.guide.controller.is_idle() and rpg.player.controller.is_idle(), "RPG dialogue and reaction return to idle")
	rpg.free()
	var deadline := Time.get_ticks_msec() + 1500
	while not released() and Time.get_ticks_msec() < deadline: await process_frame
	expect(released(), "audio mixer releases all stopped playbacks before exit")
	print("CUBISM_CHARACTER_EXAMPLES_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty(): print("CUBISM_CHARACTER_EXAMPLES_PASS")
	quit(0 if failures.is_empty() else 1)
