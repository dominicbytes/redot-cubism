# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(bytes)
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	# Deliberate corruption below is synchronous. Keep the polling service from
	# inspecting that test-only intermediate state through nested editor frames.
	var tracker := get_tree().root.find_child("CubismDependencies", true, false)
	tracker.set_process(false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var model := ResourceLoader.load("res://imported-model.res") as CubismModelResource
	assert(model != null)
	var hashes := {}
	hashes[source] = FileAccess.get_sha256(source)
	var paths: Array[String] = []
	for i in model.textures.size():
		var original: String = model.texture_paths[i]
		hashes[original] = FileAccess.get_sha256(original)
		hashes[original + ".import"] = FileAccess.get_sha256(original + ".import")
		var expected := Image.new()
		assert(expected.load_png_from_buffer(FileAccess.get_file_as_bytes(original)) == OK)
		assert(expected.generate_mipmaps() == OK)
		var texture := model.textures[i] as PortableCompressedTexture2D
		assert(texture != null and texture.get_compression_mode() == PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		assert(texture.get_image().get_data() == expected.get_data())
		assert(texture.get_image().get_mipmap_count() == expected.get_mipmap_count())
		assert(texture.resource_path.get_file().get_basename() == FileAccess.get_sha256(texture.resource_path))
		paths.append(texture.resource_path)
	var edges := ResourceLoader.get_dependencies("res://imported-model.res")
	for path: String in paths:
		assert(Array(edges).any(func(edge: String) -> bool: return edge.ends_with(path)))
	assert(CubismModelImporter.import_model(source, "res://texture-second-model.res") == OK)
	var second := ResourceLoader.load("res://texture-second-model.res") as CubismModelResource
	for i in paths.size():
		assert(second.textures[i].resource_path == paths[i])
		assert(second.textures[i] == model.textures[i])
	assert(CubismModelImporter.import_model(source, "res://imported-model.res") == OK)
	var repeated := ResourceLoader.load("res://imported-model.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE) as CubismModelResource
	for i in paths.size():
		assert(repeated.textures[i].resource_path == paths[i])
	# Existing unexpected bytes must be rejected before ResourceLoader sees them,
	# and neither the existing texture file nor the last model may be overwritten.
	var generated: String = paths[0]
	var original_bytes := FileAccess.get_file_as_bytes(generated)
	var sentinel := "Unrelated file: do not overwrite or deserialize".to_utf8_buffer()
	var saved_model := FileAccess.get_sha256("res://imported-model.res")
	write_bytes(generated, sentinel)
	print("EXPECTED_TEXTURE_FAILURE_BEGIN")
	assert(CubismModelImporter.import_model(source, "res://imported-model.res") == ERR_FILE_CORRUPT)
	print("EXPECTED_TEXTURE_FAILURE_END")
	assert(FileAccess.get_file_as_bytes(generated) == sentinel)
	assert(FileAccess.get_sha256("res://imported-model.res") == saved_model)
	write_bytes(generated, original_bytes)
	# A missing generated texture is recreated from the original source on import.
	assert(DirAccess.remove_absolute(generated) == OK)
	assert(CubismModelImporter.import_model(source, "res://imported-model.res") == OK)
	assert(FileAccess.get_file_as_bytes(generated) == original_bytes)
	for path: String in hashes:
		assert(FileAccess.get_sha256(path) == hashes[path])
	assert(DirAccess.remove_absolute("res://texture-second-model.res") == OK)
	print("CUBISM_TEXTURE_POLICY_PASS textures=", paths.size())
	get_tree().quit()
