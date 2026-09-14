# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
## Draws optional drawable, mask and draw-order diagnostics for a legacy Cubism model.
## Place directly under GDCubismUserModel. Use CubismModel2D debug properties for new scenes.
@tool
class_name GDCubismDebugOverlay
extends Node2D

## Optional direct child of GDCubismUserModel. Generated renderer nodes stay private.
@export_flags("Drawable bounds", "Mask bounds", "Draw order") var overlays: int = 3:
	set(value):
		overlays = value
		queue_redraw()

## Leave empty for all drawables; use an exact Core ID to inspect one drawable.
@export var drawable_id: String = "":
	set(value):
		drawable_id = value
		queue_redraw()

func _get_configuration_warnings() -> PackedStringArray:
	if not get_parent() is GDCubismUserModel:
		return ["Attach this overlay directly beneath a GDCubismUserModel."]
	return []

func _process(_delta: float) -> void:
	if overlays != 0 and is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var model := get_parent() as GDCubismUserModel
	if model == null or overlays == 0 or transform.determinant() == 0.0:
		return
	var to_overlay: Transform2D = transform.affine_inverse()
	var screen_scale: float = get_global_transform_with_canvas().get_scale().length() / sqrt(2.0)
	if screen_scale == 0.0:
		return
	var width: float = 1.0 / screen_scale
	var font_size: int = clampi(roundi(12.0 / screen_scale), 8, 512)
	var order: int = 0
	for child: Node in model.get_children():
		if child is MeshInstance2D:
			var draw_order: int = order
			order += 1
			if not drawable_id.is_empty() and str(child.name) != drawable_id:
				continue
			var mesh := child.mesh as ArrayMesh
			if mesh == null:
				continue
			var bounds: AABB = mesh.custom_aabb
			var rect := Rect2(Vector2(bounds.position.x, bounds.position.y), Vector2(bounds.size.x, bounds.size.y))
			draw_set_transform_matrix(to_overlay * child.transform)
			if overlays & 1:
				draw_rect(rect, Color(0, 1, 1, 0.8), false, width)
			if overlays & 4:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, font_size), str(draw_order) + ": " + str(child.name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.YELLOW)
		elif child is SubViewport and overlays & 2:
			if child.canvas_transform.determinant() == 0.0:
				continue
			var rect: Rect2 = child.canvas_transform.affine_inverse() * Rect2(Vector2.ZERO, Vector2(child.size))
			draw_set_transform_matrix(to_overlay)
			draw_rect(rect, Color(1, 0.2, 0.8, 0.9), false, width * 2)
	draw_set_transform_matrix(Transform2D.IDENTITY)
