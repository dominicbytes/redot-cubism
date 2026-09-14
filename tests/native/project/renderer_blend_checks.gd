extends RefCounted

static func _texture(color: Color) -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

static func run(host: Node) -> bool:
	await host.get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("CUBISM_BLEND_FAIL: requires graphics")
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(32, 32)
	var background_shader := Shader.new()
	background_shader.code = "shader_type canvas_item; render_mode blend_disabled, unshaded; uniform vec4 value; void fragment() { COLOR = value; }"
	var background_material := ShaderMaterial.new()
	background_material.shader = background_shader
	background.material = background_material
	viewport.add_child(background)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2(4, 4)
	viewport.add_child(sprite)
	var checked: int = 0
	var passed: bool = true
	for destination_alpha: float in [0.5, 1.0]:
		var destination := Color(0.2, 0.4, 0.6, destination_alpha)
		background_material.set_shader_parameter("value", destination)
		for source_alpha: float in [0.0, 0.5, 1.0]:
			var texture: ImageTexture = _texture(Color(0.75, 0.5, 0.25, source_alpha))
			var source: Color = texture.get_image().get_pixel(0, 0)
			sprite.texture = texture
			for mode: String in ["mix", "add", "mul"]:
				for masking: String in ["norm", "mask", "mask_inv"]:
					# Beyond any mask edge, regular coverage is zero and inverted coverage is one.
					var offsets: Array[Vector2] = [Vector2.ZERO]
					if masking != "norm": offsets.append_array([Vector2(-16, 0), Vector2(16, 0), Vector2(0, -16), Vector2(0, 16)])
					for offset: Vector2 in offsets:
						var name: String = "2d_cubism_" + ("norm_" if masking == "norm" else "mask_") + mode
						if masking == "mask_inv":
							name += "_inv"
						var material := ShaderMaterial.new()
						material.shader = load("res://addons/gd_cubism/res/shader/" + name + ".gdshader")
						material.set_shader_parameter("tex_main", texture)
						material.set_shader_parameter("color_base", Color.WHITE)
						material.set_shader_parameter("color_multiply", Color.WHITE)
						material.set_shader_parameter("color_screen", Color(0, 0, 0, 0))
						var coverage: float = 1.0
						if masking != "norm":
							var mask: ImageTexture = _texture(Color(0, 0, 0, 0.25))
							coverage = mask.get_image().get_pixel(0, 0).a if offset == Vector2.ZERO else 0.0
							if masking == "mask_inv":
								coverage = 1.0 - coverage
							material.set_shader_parameter("tex_mask", mask)
							material.set_shader_parameter("channel", Color(0, 0, 0, 1))
							material.set_shader_parameter("mask_scale", 1.0)
							material.set_shader_parameter("mesh_offset", offset)
						sprite.material = material
						for frame: int in 3:
							await RenderingServer.frame_post_draw
						var actual: Color = viewport.get_texture().get_image().get_pixel(16, 16)
						# SDK compatible blend factors operate on premultiplied source RGB.
						var alpha: float = source.a * coverage
						var expected := Color(0, 0, 0, destination.a)
						for channel: int in 3:
							var premultiplied: float = source[channel] * alpha
							if mode == "mix":
								expected[channel] = premultiplied + destination[channel] * (1.0 - alpha)
							elif mode == "add":
								expected[channel] = minf(1.0, premultiplied + destination[channel])
							else:
								expected[channel] = destination[channel] * (premultiplied + 1.0 - alpha)
						if mode == "mix":
							expected.a = alpha + destination.a * (1.0 - alpha)
						for channel: int in 4:
							if absf(actual[channel] - expected[channel]) > 3.0 / 255.0:
								push_error("CUBISM_BLEND_FAIL: " + name + " mask_offset=" + str(offset) + " source_alpha=" + str(source_alpha) + " destination_alpha=" + str(destination_alpha) + " actual=" + str(actual) + " expected=" + str(expected))
								passed = false
								break
						checked += 1
	sprite.hide()
	var wrapping: Dictionary = await _wrap_checks(viewport, background_material)
	checked += wrapping.checked
	passed = passed and wrapping.passed
	viewport.free()
	if passed:
		print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
		print("CUBISM_BLEND_PASS cases=" + str(checked))
	return passed

static func _wrap_checks(viewport: SubViewport, background: ShaderMaterial) -> Dictionary:
	# Sample outside each atlas edge. The SDK repeats the source texture even
	# when the surrounding Redot canvas uses clamping.
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var colors: Array[Color] = [Color(1, 0, 0, 0.25), Color(0, 1, 0, 0.5), Color(0, 0, 1, 0.75), Color.WHITE]
	for y in 8:
		for x in 8: image.set_pixel(x, y, colors[int(x >= 4) + 2 * int(y >= 4)])
	var texture := ImageTexture.create_from_image(image)
	var node := MeshInstance2D.new()
	node.scale = Vector2(4, 4)
	viewport.add_child(node)
	var destination := Color(0.2, 0.4, 0.6, 0.5)
	background.set_shader_parameter("value", destination)
	var result := {"checked": 0, "passed": true}
	for repeat_mode in [CanvasItem.TEXTURE_REPEAT_DISABLED, CanvasItem.TEXTURE_REPEAT_ENABLED]:
		node.texture_repeat = repeat_mode
		for uv: Vector2 in [Vector2(-0.25, 0.25), Vector2(1.25, 0.25), Vector2(0.25, -0.25), Vector2(0.25, 1.25)]:
			var source := image.get_pixel(int(fposmod(uv.x, 1.0) * 8), int(fposmod(uv.y, 1.0) * 8))
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(8, 8, 0), Vector3(0, 8, 0)])
			arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([uv, uv, uv, uv])
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			node.mesh = mesh
			for shader_name: String in ["mask", "norm_mix", "norm_add", "norm_mul", "mask_mix", "mask_add", "mask_mul", "mask_mix_inv", "mask_add_inv", "mask_mul_inv"]:
				var material := ShaderMaterial.new()
				material.shader = load("res://addons/gd_cubism/res/shader/2d_cubism_" + shader_name + ".gdshader")
				material.set_shader_parameter("tex_main", texture)
				var coverage := 1.0
				var mode := "mix"
				var sampled := source
				if shader_name == "mask":
					material.set_shader_parameter("channel", Color(0, 0, 0, 1))
					sampled = Color(0, 0, 0, source.a)
				else:
					mode = shader_name.split("_")[1]
					material.set_shader_parameter("color_base", Color.WHITE)
					material.set_shader_parameter("color_multiply", Color.WHITE)
					material.set_shader_parameter("color_screen", Color(0, 0, 0, 0))
					if shader_name.begins_with("mask_"):
						var mask := _texture(Color(0, 0, 0, 0.25))
						coverage = mask.get_image().get_pixel(0, 0).a
						if shader_name.ends_with("_inv"): coverage = 1.0 - coverage
						material.set_shader_parameter("tex_mask", mask)
						material.set_shader_parameter("channel", Color(0, 0, 0, 1))
						material.set_shader_parameter("mask_scale", 1.0)
						material.set_shader_parameter("mesh_offset", Vector2.ZERO)
				node.material = material
				for frame in 3: await RenderingServer.frame_post_draw
				var actual := viewport.get_texture().get_image().get_pixel(16, 16)
				var alpha := sampled.a * coverage
				var expected := Color(0, 0, 0, destination.a)
				for channel in 3:
					var value: float = sampled[channel] * alpha
					if mode == "mix": expected[channel] = value + destination[channel] * (1.0 - alpha)
					elif mode == "add": expected[channel] = minf(1.0, value + destination[channel])
					else: expected[channel] = destination[channel] * (value + 1.0 - alpha)
				if mode == "mix": expected.a = alpha + destination.a * (1.0 - alpha)
				for channel in 4:
					if absf(actual[channel] - expected[channel]) > 3.0 / 255.0:
						push_error("CUBISM_WRAP_FAIL: " + shader_name + " uv=" + str(uv) + " repeat=" + str(repeat_mode) + " actual=" + str(actual) + " expected=" + str(expected))
						result.passed = false
						break
				result.checked += 1
	node.free()
	return result
