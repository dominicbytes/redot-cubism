# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	if not value: failures.append(label)

func finish(marker: String) -> void:
	if failures.is_empty(): print(marker)
	else: printerr("CUBISM_TEXTURE_EXPORT_FAIL ", failures)
	quit(0 if failures.is_empty() else 1)

func image_hash(image: Image) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return hash.finish().hex_encode()

func _initialize() -> void:
	var model := ResourceLoader.load("res://imported-model.res") as CubismModelResource
	expect(model != null and not model.textures.is_empty(), "model contains textures")
	if not failures.is_empty():
		finish("")
		return
	if "--prepare" in OS.get_cmdline_user_args():
		var expected := []
		for path: String in model.texture_paths:
			var source := Image.new()
			expect(source.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, "load source texture")
			expect(source.generate_mipmaps() == OK, "generate source mipmaps")
			expected.append({"hash": image_hash(source), "width": source.get_width(), "height": source.get_height(), "mipmaps": source.get_mipmap_count()})
		var file := FileAccess.open("res://texture-expected.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(expected))
		file.close()
		finish("CUBISM_TEXTURE_EXPORT_PREPARED")
	else:
		expect(not OS.has_feature("editor"), "runs in export template")
		var expected: Array = JSON.parse_string(FileAccess.get_file_as_string("res://texture-expected.json"))
		expect(expected.size() == model.textures.size(), "texture count")
		if not failures.is_empty():
			finish("")
			return
		for i in expected.size():
			expect(not FileAccess.file_exists(model.texture_paths[i]), "source texture excluded")
			expect(model.textures[i] is PortableCompressedTexture2D, "portable exported texture")
			var actual: Image = model.textures[i].get_image()
			expect(image_hash(actual) == expected[i].hash, "exported texture bytes")
			expect(actual.get_width() == expected[i].width and actual.get_height() == expected[i].height, "exported texture dimensions")
			expect(actual.get_mipmap_count() == expected[i].mipmaps, "exported mipmaps")
		finish("CUBISM_TEXTURE_EXPORT_PASS textures=" + str(expected.size()))
