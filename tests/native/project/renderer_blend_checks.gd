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
						coverage = mask.get_image().get_pixel(0, 0).a
						if masking == "mask_inv":
							coverage = 1.0 - coverage
						material.set_shader_parameter("tex_mask", mask)
						material.set_shader_parameter("channel", Color(0, 0, 0, 1))
						material.set_shader_parameter("mask_scale", 1.0)
						material.set_shader_parameter("mesh_offset", Vector2.ZERO)
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
							push_error("CUBISM_BLEND_FAIL: " + name + " source_alpha=" + str(source_alpha) + " destination_alpha=" + str(destination_alpha) + " actual=" + str(actual) + " expected=" + str(expected))
							passed = false
							break
					checked += 1
	viewport.free()
	if passed:
		print("CUBISM_NATIVE_GRAPHICS:" + JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name()}))
		print("CUBISM_BLEND_PASS cases=" + str(checked))
	return passed
