# SPDX-License-Identifier: MIT
extends Resource

@export var display_name := "Mara"
@export var model: CubismModelResource
@export var voice: AudioStream
@export var idle_motion: StringName
@export var talk_motion: StringName
@export var walk_motion: StringName
@export var reaction_motion: StringName
@export var talk_expression: StringName

func configure(target: CubismModel2D, controller: CubismCharacterController) -> Dictionary:
	if model == null:
		return {"ok": false, "message": "Assign an imported model to Character → Model in the scene inspector."}
	var error := target.load_model(model)
	if error != OK:
		return {"ok": false, "message": "Model could not be loaded: " + error_string(error)}
	var motions := target.get_motion_ids()
	var fallback := StringName(motions[0]) if not motions.is_empty() else &""
	var ids := {"idle": idle_motion if idle_motion != &"" else fallback,
		"talk": talk_motion if talk_motion != &"" else fallback,
		"walk": walk_motion if walk_motion != &"" else fallback,
		"reaction": reaction_motion if reaction_motion != &"" else fallback,
		"expression": talk_expression}
	for key: String in ["idle", "talk", "walk", "reaction"]:
		if ids[key] != &"" and not motions.has(String(ids[key])):
			return {"ok": false, "message": "Choose an existing " + key + " motion ID in the character preset."}
	if talk_expression != &"" and not target.get_expression_ids().has(String(talk_expression)):
		return {"ok": false, "message": "Choose an existing expression ID in the character preset."}
	target.enable_eye_blink = true
	target.enable_breath = true
	target.enable_physics = true
	target.enable_pose = true
	controller.target_model = target
	controller.idle_motion = ids.idle
	controller.auto_return_to_idle = ids.idle != &""
	if ids.idle != &"":
		error = controller.return_to_idle()
		if error != OK: return {"ok": false, "message": "Idle could not start: " + error_string(error)}
	return {"ok": true, "ids": ids, "message": "Ready"}
