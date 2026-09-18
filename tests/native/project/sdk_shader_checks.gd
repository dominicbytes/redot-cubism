# SPDX-License-Identifier: MIT
extends SceneTree

func rgba(values: Array) -> Color:
	return Color(values[0], values[1], values[2], values[3])

func vector(values: Array) -> Vector4:
	return Vector4(values[0], values[1], values[2], values[3])

func texture(bytes: Array) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_RGBA8, PackedByteArray(bytes)))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or DisplayServer.get_name() == "headless":
		printerr("SDK shader comparison requires a cases file and graphics")
		quit(1)
		return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var cases: Array = reference.cases
	if "--straight-only" in arguments:
		cases = cases.filter(func(entry: Dictionary) -> bool: return not entry.premultiplied)
	var view := SubViewport.new()
	const COLUMNS := 32
	const CELL := 4
	view.size = Vector2i(COLUMNS * CELL, ceili(float(cases.size()) / COLUMNS) * CELL)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var names := ["mix", "add", "mul"]
	for index in cases.size():
		var entry: Dictionary = cases[index]
		var origin := Vector2((index % COLUMNS) * CELL, (index / COLUMNS) * CELL)
		var background := ColorRect.new()
		background.position = origin
		background.size = Vector2(CELL, CELL)
		background.color = rgba(entry.background)
		view.add_child(background)
		var material := ShaderMaterial.new()
		var shader_name: String = "2d_cubism_" + ("norm_" if entry.mask == 0 else "mask_") + names[int(entry.blend)]
		if entry.mask == 2: shader_name += "_inv"
		material.shader = load("res://addons/gd_cubism/res/shader/" + shader_name + ".gdshader")
		var base := vector(entry.base)
		# SDK GetModelColorWithOpacity premultiplies the base RGB in this mode.
		if entry.premultiplied:
			base.x *= base.w
			base.y *= base.w
			base.z *= base.w
		material.set_shader_parameter("color_base", base)
		material.set_shader_parameter("color_screen", vector(entry.screen))
		material.set_shader_parameter("color_multiply", vector(entry.multiply))
		material.set_shader_parameter("tex_main", texture(entry.texel))
		material.set_shader_parameter("channel", Vector4(1, 0, 0, 0))
		material.set_shader_parameter("premultiplied_alpha", entry.premultiplied)
		if entry.mask != 0:
			# Cubism stores the complement in its mask target; this renderer stores
			# coverage. Supply equivalent masks to compare the fragment operations.
			material.set_shader_parameter("tex_mask", texture([int(entry.coverage), 0, 0, 255]))
			material.set_shader_parameter("mask_scale", 1.0)
			material.set_shader_parameter("mesh_offset", Vector2.ZERO)
		var polygon := Polygon2D.new()
		polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(CELL, 0), Vector2(CELL, CELL), Vector2(0, CELL)])
		polygon.uv = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)])
		polygon.position = origin
		polygon.modulate = rgba(entry.modulate)
		polygon.material = material
		view.add_child(polygon)
	for frame in 4: await RenderingServer.frame_post_draw
	var captured := view.get_texture().get_image()
	var failures: Array[Dictionary] = []
	var failed_cases := 0
	var maximum_error := 0
	for index in cases.size():
		var entry: Dictionary = cases[index]
		var pixel := captured.get_pixel((index % COLUMNS) * CELL + 2, (index / COLUMNS) * CELL + 2)
		var actual := [pixel.r8, pixel.g8, pixel.b8, pixel.a8]
		var error := 0
		for channel in 4: error = maxi(error, absi(actual[channel] - int(entry.expected[channel])))
		maximum_error = maxi(maximum_error, error)
		if error > 2:
			failed_cases += 1
			if failures.size() < 12: failures.append({"index": index, "case": entry, "actual": actual, "error": error})
	var output := arguments[0].get_base_dir()
	var image_error := captured.save_png(output.path_join("redot-shader-cases.png"))
	var result := {"cases": cases.size(), "failed_cases": failed_cases, "maximum_channel_error": maximum_error,
		"tolerance_bytes": 2, "failures": failures, "capture_error": image_error,
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(output.path_join("redot-shader-report.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "\t") + "\n")
	var ok := failed_cases == 0 and image_error == OK and file != null and not cases.is_empty()
	print("CUBISM_SDK_SHADER " + JSON.stringify(result))
	if ok: print("CUBISM_SDK_SHADER_PASS")
	view.free()
	quit(0 if ok else 1)
