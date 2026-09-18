# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _initialize() -> void:
	var motion := CubismMotionDescriptor.new()
	expect(motion.fade_in_seconds == -1 and motion.fade_out_seconds == -1, "absent motion fade defaults")
	expect(motion.sound == null and motion.animation == null and motion.events.is_empty(), "optional motion resources default empty")
	var values := {
		"id": &"TapBody/2", "group": &"TapBody", "index": 2,
		"source_path": "res://motions/挨拶.motion3.json",
		"sound_path": "res://synthetic-audio.wav",
		"fade_in_seconds": 0.25, "fade_out_seconds": 0.5,
		"duration_seconds": 1.25, "loop": true,
		"metadata": {"Alias": "挨拶", "Future": 42},
	}
	for field: String in values:
		motion.set(field, values[field])
	motion.sound = load("res://synthetic-audio.wav") as AudioStream
	expect(motion.sound != null and is_equal_approx(motion.sound.get_length(), 0.01), "imported audio resource")
	motion.animation = Animation.new()
	motion.animation.length = 1.25
	var event := CubismMotionEvent.new()
	event.time_seconds = 0.375
	event.value = "合図"
	var events: Array[CubismMotionEvent] = [event]
	motion.events = events
	var expression := CubismExpressionDescriptor.new()
	expect(expression.fade_in_seconds == -1 and expression.parameters.is_empty(), "expression defaults")
	expression.id = &"笑顔"
	expression.source_path = "res://expressions/笑顔.exp3.json"
	expression.fade_in_seconds = 0.125
	expression.fade_out_seconds = 0.75
	var parameters: Array[CubismExpressionParameter] = []
	for operation: int in [CubismExpressionParameter.ADD, CubismExpressionParameter.MULTIPLY, CubismExpressionParameter.OVERWRITE]:
		var parameter := CubismExpressionParameter.new()
		parameter.id = StringName("Param" + str(operation))
		parameter.operation = operation
		parameter.value = operation * 0.5
		parameters.append(parameter)
	expression.parameters = parameters
	var model := CubismModelResource.new()
	model.motion_groups = {"TapBody": [motion]}
	model.expressions = [expression]
	expect(ResourceSaver.save(model, "user://cubism-descriptors.res") == OK, "save descriptor graph")
	var restored := ResourceLoader.load("user://cubism-descriptors.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	expect(restored != null, "restore model graph")
	if restored:
		var restored_motion: CubismMotionDescriptor = restored.motion_groups.TapBody[0]
		expect(restored_motion != null and restored_motion != motion, "fresh typed motion")
		for field: String in values:
			expect(restored_motion.get(field) == values[field], "motion round trip " + field)
		expect(restored_motion.sound.resource_path == "res://synthetic-audio.wav", "external audio reference preserved")
		expect(is_equal_approx(restored_motion.sound.get_length(), 0.01), "audio duration preserved")
		expect(restored_motion.animation is Animation and restored_motion.animation.length == 1.25, "optional Animation resource preserved")
		expect(restored_motion.events.size() == 1 and restored_motion.events[0] is CubismMotionEvent, "typed motion event")
		expect(restored_motion.events[0].time_seconds == 0.375 and restored_motion.events[0].value == "合図", "event time and Unicode value")
		var restored_expression: CubismExpressionDescriptor = restored.expressions[0]
		expect(restored_expression != null and restored_expression != expression, "fresh typed expression")
		expect(restored_expression.id == &"笑顔" and restored_expression.source_path == expression.source_path, "expression identity and path")
		expect(restored_expression.fade_in_seconds == 0.125 and restored_expression.fade_out_seconds == 0.75, "expression fades")
		expect(restored_expression.parameters.size() == 3, "typed expression parameter count")
		for i: int in restored_expression.parameters.size():
			var parameter := restored_expression.parameters[i]
			expect(parameter is CubismExpressionParameter and parameter.id == parameters[i].id and parameter.operation == parameters[i].operation and parameter.value == parameters[i].value, "parameter and operation " + str(i))
	var dependencies := ResourceLoader.get_dependencies("user://cubism-descriptors.res")
	expect(dependencies.size() == 1 and dependencies[0].contains("res://synthetic-audio.wav"), "engine sees nested audio dependency")
	for failure: String in failures:
		printerr("DESCRIPTOR_CHECK_FAIL: ", failure)
	print("CUBISM_DESCRIPTOR_CHECKS cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_DESCRIPTORS_PASS")
	quit(0 if failures.is_empty() else 1)
