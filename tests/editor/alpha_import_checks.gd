# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

var checks := 0
var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	var tracker := get_tree().root.find_child("CubismDependencies", true, false)
	tracker.set_process(false)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var straight := load("res://imported-model.res") as CubismModelResource
	var hashes := {source: FileAccess.get_sha256(source)}
	for path: String in straight.texture_paths:
		hashes[path] = FileAccess.get_sha256(path)
		hashes[path + ".import"] = FileAccess.get_sha256(path + ".import")
	expect(CubismModelImporter.import_model_with_options(source, "res://alpha-model.res", {"rendering/premultiplied_alpha": true}) == OK, "import premultiplied model")
	var model := load("res://alpha-model.res") as CubismModelResource
	if model == null:
		expect(false, "premultiplied resource exists")
		finish()
		return
	expect(model.get_premultiplied_alpha(), "alpha option persisted")
	expect(CubismExportValidator.validate_model(model).ok, "premultiplied model qualifies for export")
	var unsaved := CubismModelFactory.build_with_options(source, {"rendering/premultiplied_alpha": true})
	expect(unsaved.ok and not CubismExportValidator.validate_model(unsaved.model).ok, "factory result needs texture provisioning before export")
	for resource: CubismModelResource in [straight, model]:
		var mismatched := resource.duplicate(false) as CubismModelResource
		mismatched.import_options = resource.import_options.duplicate()
		mismatched.import_options["rendering/premultiplied_alpha"] = not resource.get_premultiplied_alpha()
		expect(not CubismExportValidator.validate_model(mismatched).ok, "export rejects texture encoding mismatch")
	expect(model.textures.size() == straight.textures.size() and not model.textures.is_empty(), "all textures provisioned")
	for index in model.textures.size():
		var expected := Image.new()
		expect(expected.load_png_from_buffer(FileAccess.get_file_as_bytes(model.texture_paths[index])) == OK, "decode unchanged source")
		expected.convert(Image.FORMAT_RGBA8)
		expected.premultiply_alpha()
		expect(expected.generate_mipmaps() == OK, "generate mipmaps after premultiplication")
		var texture := model.textures[index] as PortableCompressedTexture2D
		expect(texture != null, "portable alpha texture")
		if texture == null: continue
		expect(texture.get_meta("cubism_premultiplied_alpha", false) == true, "texture encoding marker persisted")
		expect(texture.get_image().get_data() == expected.get_data(), "complete premultiplied pixels and mipmaps")
		expect(texture.get_image().get_mipmap_count() == expected.get_mipmap_count(), "mipmap levels preserved")
		expect(texture.resource_path.get_file().get_basename() == FileAccess.get_sha256(texture.resource_path), "texture identity covers serialized alpha metadata")
		expect(texture.resource_path != straight.textures[index].resource_path, "straight and premultiplied cache entries are distinct")
	expect(CubismModelImporter.import_model_with_options(source, "res://alpha-second.res", {"rendering/premultiplied_alpha": true}) == OK, "repeat premultiplied import")
	var second := load("res://alpha-second.res") as CubismModelResource
	if second:
		for index in model.textures.size():
			expect(second.textures[index] == model.textures[index], "repeat alpha import shares texture resource")
	expect(CubismModelImporter.import_model(source, "res://alpha-second.res") == OK, "return to straight alpha")
	second = ResourceLoader.load("res://alpha-second.res", "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)
	if second:
		expect(not second.get_premultiplied_alpha(), "straight option restored")
		for index in straight.textures.size():
			expect(second.textures[index].resource_path == straight.textures[index].resource_path, "restored straight payload is identical")
	for path: String in hashes:
		expect(FileAccess.get_sha256(path) == hashes[path], "source and engine sidecar preserved: " + path)
	expect(DirAccess.remove_absolute("res://alpha-second.res") == OK, "remove secondary fixture")
	finish()

func finish() -> void:
	for failure: String in failures: printerr("ALPHA_IMPORT_FAIL: ", failure)
	print("CUBISM_ALPHA_IMPORT checks=", checks, " failures=", failures.size())
	if failures.is_empty(): print("CUBISM_ALPHA_IMPORT_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
