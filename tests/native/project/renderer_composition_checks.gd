# SPDX-License-Identifier: MIT
# GPU feasibility regression; this is not the public CubismModel2D fallback.
extends SceneTree

var target_size := 64

func rect(parent: Node, color: Color, offset := Vector2.ZERO) -> void:
	var node := ColorRect.new()
	node.color = color
	node.position = offset
	node.size = Vector2(target_size, target_size)
	parent.add_child(node)

func view(size: Vector2i) -> SubViewport:
	var node := SubViewport.new()
	node.size = size
	node.transparent_bg = true
	node.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return node

func drawable(parent: Node, entry: Dictionary, offset := Vector2.ZERO) -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(entry.color)
	var patterned: bool = entry.get("patterned", false)
	var premultiplied: bool = entry.get("premultiplied", false)
	if patterned:
		for y in 4:
			for x in 4:
				image.set_pixel(x, y, Color((x + 1) / 4.0, (y + 1) / 4.0, 0.7, ((x + y) % 4) / 3.0))
	if premultiplied: image.premultiply_alpha()
	var material := ShaderMaterial.new()
	var mask_mode: int = entry.get("mask", 0)
	var suffix: String = ["mix", "add", "mul"][entry.blend] + ("_inv" if mask_mode == 2 else "")
	material.shader = load("res://addons/gd_cubism/res/shader/2d_cubism_" + ("mask_" if mask_mode else "norm_") + suffix + ".gdshader")
	material.set_shader_parameter("tex_main", ImageTexture.create_from_image(image))
	material.set_shader_parameter("premultiplied_alpha", premultiplied)
	var base := Vector4(0.8, 0.9, 0.7, 0.6) if patterned else Vector4.ONE
	if premultiplied:
		base.x *= base.w
		base.y *= base.w
		base.z *= base.w
	material.set_shader_parameter("color_base", base)
	material.set_shader_parameter("color_multiply", Vector4(0.7, 0.8, 0.9, 1) if patterned else Vector4.ONE)
	material.set_shader_parameter("color_screen", Vector4(0.2, 0.1, 0.3, 0) if patterned else Vector4.ZERO)
	if mask_mode:
		var mask := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		for y in 4:
			for x in 4: mask.set_pixel(x, y, Color(0, 0, 0, (x + y) / 6.0))
		material.set_shader_parameter("tex_mask", ImageTexture.create_from_image(mask))
		material.set_shader_parameter("channel", Vector4(0, 0, 0, 1))
		material.set_shader_parameter("mask_scale", 4.0 / target_size)
		material.set_shader_parameter("mesh_offset", Vector2.ZERO)
	var polygon := MeshInstance2D.new()
	var points: PackedVector2Array
	var uvs: PackedVector2Array
	if patterned:
		points = PackedVector2Array([Vector2(target_size * 0.13, target_size * 0.17), Vector2(target_size * 0.93, target_size * 0.23), Vector2(target_size * 0.43, target_size * 0.87)])
		uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0.5, 1)])
		polygon.modulate = Color(0.85, 0.7, 0.95, 0.65)
	else:
		points = PackedVector2Array([Vector2.ZERO, Vector2(target_size, 0), Vector2(target_size, target_size), Vector2(0, target_size)])
		uvs = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2] if patterned else [0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	polygon.mesh = mesh
	polygon.material = material
	polygon.position = offset
	parent.add_child(polygon)

func render(entries: Array, background: Color, mode: String) -> Image:
	var output := view(Vector2i(target_size, target_size))
	root.add_child(output)
	rect(output, background)
	if mode == "direct":
		for entry: Dictionary in entries: drawable(output, entry)
	else:
		var columns := ceili(sqrt(entries.size())) if mode == "ordered" else 1
		var rows := ceili(float(entries.size()) / columns) if mode == "ordered" else 1
		var atlas := view(Vector2i(target_size * columns, target_size * rows))
		output.add_child(atlas)
		for index in entries.size():
			var offset := Vector2(target_size * (index % columns), target_size * (index / columns)) if mode == "ordered" else Vector2.ZERO
			if mode == "ordered" and entries[index].blend == 2: rect(atlas, Color.WHITE, offset)
			drawable(atlas, entries[index], offset)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = atlas.get_texture()
		if mode == "ordered":
			var copy := BackBufferCopy.new()
			copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			output.add_child(copy)
			var shader := load("res://addons/gd_cubism/res/shader/2d_cubism_compositor.gdshader") as Shader
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("layers", atlas.get_texture())
			var modes := PackedInt32Array()
			modes.resize(512)
			for index in entries.size(): modes[index] = entries[index].blend
			material.set_shader_parameter("modes", modes)
			material.set_shader_parameter("count", entries.size())
			material.set_shader_parameter("grid", Vector2(columns, rows))
			sprite.material = material
			sprite.scale = Vector2(1.0 / columns, 1.0 / rows)
		else:
			var material := CanvasItemMaterial.new()
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
			sprite.material = material
		output.add_child(sprite)
	for frame in 4: await RenderingServer.frame_post_draw
	var image := output.get_texture().get_image()
	output.free()
	return image

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or DisplayServer.get_name() == "headless":
		printerr("Pass output JSON and target size; real graphics required")
		quit(1)
		return
	target_size = int(arguments[1])
	if target_size < 2 or target_size > 256:
		quit(1)
		return
	run.call_deferred()

func run() -> void:
	var cases := [
		[{"blend": 0, "color": Color(0.7, 0.2, 0.4, 0.5)}],
		[{"blend": 1, "color": Color(0.7, 0.2, 0.4, 0.5)}],
		[{"blend": 2, "color": Color(0.7, 0.2, 0.4, 0.5)}],
		[{"blend": 1, "color": Color(1, 0.9, 0.8, 1)}, {"blend": 2, "color": Color(0.2, 0.4, 0.6, 1)}],
		[{"blend": 2, "color": Color(0.3, 0.5, 0.7, 0.8)}, {"blend": 0, "color": Color(0.9, 0.3, 0.2, 0.5)}, {"blend": 1, "color": Color(0.4, 0.2, 0.8, 0.4)}]
	]
	var comparisons := []
	for blend in 3:
		for mask in 3:
			for premultiplied in [false, true]:
				cases.append([{"blend": blend, "color": Color.WHITE, "patterned": true, "mask": mask, "premultiplied": premultiplied}])
	for patterned in [false, true]:
		var sequence := []
		var random := RandomNumberGenerator.new()
		random.seed = 3917
		for index in 84:
			sequence.append({"blend": index % 3, "color": Color(random.randf(), random.randf(), random.randf(), random.randf()), "patterned": patterned, "mask": index % 3, "premultiplied": index % 2 == 0})
		cases.append(sequence)
	var failed := 0
	var empty_failures := 0
	var flat_failures := 0
	for background: Color in [Color(0.2, 0.4, 0.8, 0), Color(0.2, 0.4, 0.8, 0.5), Color(0.2, 0.4, 0.8, 1)]:
		var backdrop := await render([], background, "direct")
		for entries: Array in cases:
			var direct := await render(entries, background, "direct")
			var flat := await render(entries, background, "flat")
			var ordered := await render(entries, background, "ordered")
			var flat_error := 0.0
			var ordered_error := 0.0
			var changed_pixels := 0
			for y in target_size:
				for x in target_size:
					var reference := direct.get_pixel(x, y)
					var flattened := flat.get_pixel(x, y)
					var actual := ordered.get_pixel(x, y)
					changed_pixels += int(reference != backdrop.get_pixel(x, y))
					for channel in 4:
						flat_error = maxf(flat_error, absf(flattened[channel] - reference[channel]))
						ordered_error = maxf(ordered_error, absf(actual[channel] - reference[channel]))
			failed += int(ordered_error > 3.0 / 255)
			flat_failures += int(flat_error > 3.0 / 255)
			var should_draw := background.a > 0 or entries.any(func(entry: Dictionary) -> bool: return entry.blend != 2)
			empty_failures += int(should_draw and changed_pixels == 0)
			if ordered_error > 3.0 / 255 or (entries[0].get("patterned", false) and comparisons.size() == 55):
				var prefix := OS.get_cmdline_user_args()[0].get_base_dir().path_join("case-%02d" % comparisons.size())
				direct.save_png(prefix + "-direct.png")
				ordered.save_png(prefix + "-ordered.png")
			comparisons.append({"background": str(background), "entries": str(entries), "direct_changed_pixels": changed_pixels, "direct": str(direct.get_pixel(target_size / 2, target_size / 2)), "flat": str(flat.get_pixel(target_size / 2, target_size / 2)), "ordered": str(ordered.get_pixel(target_size / 2, target_size / 2)), "flat_error": flat_error, "ordered_error": ordered_error})
	var report := {"target_size": target_size, "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "cases": comparisons, "ordered_failures": failed, "empty_failures": empty_failures, "flat_failures": flat_failures}
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("FALLBACK_COMPOSITION cases=", comparisons.size(), " ordered_failures=", failed, " flat_failures=", flat_failures, " empty_failures=", empty_failures)
	quit(0 if failed == 0 and empty_failures == 0 and flat_failures > 0 and file != null else 1)
