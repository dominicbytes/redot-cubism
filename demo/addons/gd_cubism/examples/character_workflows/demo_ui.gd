# SPDX-License-Identifier: MIT
extends CanvasLayer

const INK := Color("edf3fa")
const MUTED := Color("a9bbce")
const ACCENT := Color("80dec5")

static func label(text: String, size: int, color := INK) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", size)
	value.add_theme_color_override("font_color", color)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value

static func button(text: String, callback: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.custom_minimum_size = Vector2(108, 42)
	value.add_theme_font_size_override("font_size", 16)
	value.focus_mode = Control.FOCUS_NONE
	value.pressed.connect(callback)
	return value

func build(title: String, subtitle: String) -> Dictionary:
	var screen := Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := VBoxContainer.new()
	screen.add_child(header)
	header.position = Vector2(36, 28)
	header.add_theme_constant_override("separation", 5)
	header.add_child(label("REDOT CUBISM / CHARACTER WORKFLOWS", 13, ACCENT))
	header.add_child(label(title, 30))
	header.add_child(label(subtitle, 16, MUTED))
	var panel := PanelContainer.new()
	screen.add_child(panel)
	panel.anchor_left = 0.04
	panel.anchor_right = 0.96
	panel.anchor_top = 0.73
	panel.anchor_bottom = 0.97
	var box := StyleBoxFlat.new()
	box.bg_color = Color("152538")
	box.border_color = Color("36506a")
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	var speaker := label("", 18, ACCENT)
	column.add_child(speaker)
	var line := label("", 21)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(line)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var status := label("", 14, MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(status)
	return {"speaker": speaker, "line": line, "actions": actions, "status": status}

static func add_button(ui: Dictionary, text: String, callback: Callable) -> Button:
	var value := button(text, callback)
	ui.actions.add_child(value)
	ui.actions.move_child(value, ui.actions.get_child_count() - 2)
	return value
