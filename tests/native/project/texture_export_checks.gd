# SPDX-License-Identifier: MIT
extends SceneTree

func image_hash(image: Image) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return hash.finish().hex_encode()

func _initialize() -> void:
	var model := ResourceLoader.load("res://imported-model.res") as CubismModelResource
	assert(model != null and not model.textures.is_empty())
	if "--prepare" in OS.get_cmdline_user_args():
		var expected := []
		for path: String in model.texture_paths:
			var source := Image.new()
			assert(source.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK)
			assert(source.generate_mipmaps() == OK)
			expected.append({"hash": image_hash(source), "width": source.get_width(), "height": source.get_height(), "mipmaps": source.get_mipmap_count()})
		var file := FileAccess.open("res://texture-expected.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(expected))
		file.close()
		print("CUBISM_TEXTURE_EXPORT_PREPARED")
	else:
		assert(not OS.has_feature("editor"))
		var expected: Array = JSON.parse_string(FileAccess.get_file_as_string("res://texture-expected.json"))
		assert(expected.size() == model.textures.size())
		for i in expected.size():
			assert(not FileAccess.file_exists(model.texture_paths[i]))
			assert(model.textures[i] is PortableCompressedTexture2D)
			var actual: Image = model.textures[i].get_image()
			assert(image_hash(actual) == expected[i].hash)
			assert(actual.get_width() == expected[i].width and actual.get_height() == expected[i].height)
			assert(actual.get_mipmap_count() == expected[i].mipmaps)
		print("CUBISM_TEXTURE_EXPORT_PASS textures=", expected.size())
	quit()
