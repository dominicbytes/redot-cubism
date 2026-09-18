# SPDX-License-Identifier: MIT
@tool
extends EditorPlugin

# Match the pinned editor's focused sleep rate regardless of desktop focus.
# This is process-local: test runs must not change saved editor preferences.
const TEST_PROCESS_SLEEP_USEC := 6900

var tracker: Node
var failures: Array[String] = []
var cases := 0

func _enter_tree() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	if OS.get_low_processor_usage_mode_sleep_usec() != TEST_PROCESS_SLEEP_USEC:
		OS.set_low_processor_usage_mode_sleep_usec(TEST_PROCESS_SLEEP_USEC)
		print("CUBISM_DEPENDENCY_SLEEP_USEC=", OS.get_low_processor_usage_mode_sleep_usec())

func expect(value: bool, label: String) -> void:
	cases += 1
	if not value:
		failures.append(label)

func status(path: String) -> Dictionary:
	for item: Dictionary in tracker.get_status().models:
		if item.resource == path:
			return item
	return {}

func settle() -> void:
	tracker.request_scan()
	for frame in 1600:
		await get_tree().process_frame
		if not tracker.get_status().busy:
			return
	failures.append("dependency scan timed out")

func fresh(path: String) -> CubismModelResource:
	return ResourceLoader.load(path, "CubismModelResource", ResourceLoader.CACHE_MODE_IGNORE)

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	print("CUBISM_DEPENDENCY_GRAPHICS=", RenderingServer.get_current_rendering_method())
	print("CUBISM_DEPENDENCY_SLEEP_USEC=", OS.get_low_processor_usage_mode_sleep_usec())
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	tracker = get_tree().root.find_child("CubismDependencies", true, false)
	expect(tracker != null, "native dependency tracker registered")
	if tracker == null:
		get_tree().quit(1)
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var source: String = fixture.model
	var output := "res://tracked.res"
	expect(CubismModelImporter.import_model(source, output) == OK, "initial explicit import")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	expect(status(output).get("status") == "current", "saved resource indexed")
	var initial := fresh(output)
	var cached := ResourceLoader.load(output, "CubismModelResource") as CubismModelResource
	expect(not initial.import_fingerprint.is_empty(), "import contract fingerprint stored")
	var attempts: int = status(output).get("attempts", -1)
	await settle()
	expect(status(output).get("attempts") == attempts, "unchanged resources do not reimport")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	manifest.Layout = {"x": 0.125}
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	await settle()
	expect(fresh(output).layout.get("x") == 0.125, "source content change reimports")
	expect(cached.layout.get("x") == 0.125, "already loaded model resource updates")
	var physics: String = initial.physics_path
	if not physics.is_empty():
		var original := FileAccess.get_file_as_bytes(physics)
		file = FileAccess.open(physics, FileAccess.WRITE)
		file.store_buffer(original)
		file.store_string("\n ")
		file.close()
		var expected_hash := FileAccess.get_sha256(physics)
		# Deliberately no filesystem scan/event; the bounded poll must find raw JSON changes.
		for frame in 2500:
			await get_tree().process_frame
			if frame % 30 == 0 and fresh(output).dependency_fingerprints[physics] == expected_hash:
				break
		expect(fresh(output).dependency_fingerprints[physics] == expected_hash, "poll detects raw dependency content changes")
		var strict := fresh(output)
		var previous_fingerprint := strict.import_fingerprint
		strict.import_options["validation/strict_optional_files"] = true
		ResourceSaver.save(strict, output)
		await settle()
		expect(fresh(output).import_fingerprint != previous_fingerprint, "import option changes invalidate contract")
		DirAccess.rename_absolute(physics, physics + ".moved")
		print("EXPECTED_DEPENDENCY_FAILURE_BEGIN")
		await settle()
		expect(status(output).get("status") == "failed", "renamed strict dependency fails")
		var failed_attempts: int = status(output).get("attempts", -1)
		await settle()
		expect(status(output).get("attempts") == failed_attempts, "unchanged failure does not loop")
		print("EXPECTED_DEPENDENCY_FAILURE_END")
		DirAccess.rename_absolute(physics + ".moved", physics)
		await settle()
		expect(status(output).get("status") == "current", "restored dependency recovers")
	var texture_path: String = initial.texture_paths[0]
	var image := Image.new()
	expect(image.load_png_from_buffer(FileAccess.get_file_as_bytes(texture_path)) == OK, "decode texture fixture")
	image.set_pixel(0, 0, Color.RED)
	expect(image.save_png(texture_path) == OK, "write changed texture fixture")
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([texture_path]))
	await settle()
	expect(fresh(output).dependency_fingerprints[texture_path] == FileAccess.get_sha256(texture_path), "texture reimport updates fingerprint")
	var pixel: Color = fresh(output).textures[0].get_image().get_pixel(0, 0)
	print("DEPENDENCY_TEXTURE_PIXEL=", pixel)
	expect(pixel.is_equal_approx(Color.RED), "texture reference sees new pixels")
	image.set_pixel(0, 0, Color.GREEN)
	expect(image.save_png(texture_path) == OK, "write texture without filesystem event")
	await settle()
	expect(fresh(output).textures[0].get_image().get_pixel(0, 0).is_equal_approx(Color.GREEN), "raw texture change refreshes engine import")
	expect(fresh("res://imported-model.res").textures[0].get_image().get_pixel(0, 0).is_equal_approx(Color.GREEN), "shared texture updates both models")
	# All raw JSON kinds use the same watcher, including files the engine ignores.
	var changed: Array[String] = []
	for suffix: String in [".motion3.json", ".exp3.json", ".pose3.json", ".userdata3.json", ".cdi3.json"]:
		for path: String in initial.dependency_paths:
			if path.ends_with(suffix):
				write_bytes(path, FileAccess.get_file_as_bytes(path) + "\n ".to_utf8_buffer())
				changed.append(path)
				break
	expect(changed.size() == 5, "fixture covers every remaining JSON dependency kind")
	await settle()
	for path: String in changed:
		expect(fresh(output).dependency_fingerprints.get(path) == FileAccess.get_sha256(path), "raw JSON change: " + path.get_file())
	var voiced: CubismMotionDescriptor
	for group: Array in initial.motion_groups.values():
		for motion: CubismMotionDescriptor in group:
			if motion.sound_path.ends_with(".wav"):
				voiced = motion
				break
		if voiced != null:
			break
	expect(voiced != null, "fixture contains WAV motion audio")
	if voiced != null:
		var sound := AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(voiced.sound_path))
		# Halve the PCM duration so stale imported audio cannot pass on hashes alone.
		var shortened := floori(sound.data.size() * 0.5)
		shortened -= shortened % 4
		sound.data = sound.data.slice(0, shortened)
		expect(sound.save_to_wav(voiced.sound_path) == OK, "write changed audio fixture")
		await settle()
		var updated: CubismMotionDescriptor = fresh(output).motion_groups[voiced.group][voiced.index]
		expect(fresh(output).dependency_fingerprints[voiced.sound_path] == FileAccess.get_sha256(voiced.sound_path), "audio content change reimports")
		expect(absf(updated.sound.get_length() - sound.get_length()) < 0.001, "audio reference sees new duration")
	# A newly declared missing path must survive a failed import in the reverse index.
	var old_physics: String = manifest.FileReferences.Physics
	manifest.FileReferences.Physics = "later.physics3.json"
	write_bytes(source, JSON.stringify(manifest).to_utf8_buffer())
	var saved_hash := FileAccess.get_sha256(output)
	print("EXPECTED_DEPENDENCY_FAILURE_BEGIN")
	await settle()
	expect(status(output).get("status") == "failed", "new missing dependency fails strict import")
	expect(FileAccess.get_sha256(output) == saved_hash, "failed import preserves last saved model")
	print("EXPECTED_DEPENDENCY_FAILURE_END")
	var later := source.get_base_dir().path_join("later.physics3.json")
	write_bytes(later, FileAccess.get_file_as_bytes(physics))
	await settle()
	expect(status(output).get("status") == "current" and fresh(output).physics_path == later, "new missing dependency recovers when created")
	manifest.FileReferences.Physics = old_physics
	write_bytes(source, JSON.stringify(manifest).to_utf8_buffer())
	await settle()
	# Removing the manifest and MOC produces failures without destroying recovery data.
	for path: String in [source, initial.moc_path]:
		expect(DirAccess.rename_absolute(path, path + ".moved") == OK, "move fixture: " + path.get_file())
		print("EXPECTED_DEPENDENCY_FAILURE_BEGIN")
		await settle()
		expect(status(output).get("status") == "failed", "missing source/MOC fails: " + path.get_file())
		print("EXPECTED_DEPENDENCY_FAILURE_END")
		expect(DirAccess.rename_absolute(path + ".moved", path) == OK, "restore fixture: " + path.get_file())
		await settle()
		expect(status(output).get("status") == "current", "source/MOC restore recovers: " + path.get_file())
	var outdated := fresh(output)
	outdated.import_fingerprint = "previous-import-contract"
	ResourceSaver.save(outdated, output)
	await settle()
	expect(fresh(output).import_fingerprint != "previous-import-contract", "outdated import contract rebuilt")
	var settled_attempts: int = status(output).get("attempts", -1)
	await settle()
	expect(status(output).get("attempts") == settled_attempts, "completed dependency reimports settle without looping")
	# Explicitly selecting the native importer is supported even on the stock
	# editor that does not discover compound suffixes during the first scan.
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([source]))
	await settle()
	expect(status(source).get("status") == "current", "engine-managed model import indexed")
	write_bytes(physics, FileAccess.get_file_as_bytes(physics) + "\n  ".to_utf8_buffer())
	await settle()
	expect(fresh(source).dependency_fingerprints.get(physics) == FileAccess.get_sha256(physics), "engine-managed model dependency reimports")
	ResourceSaver.save(Resource.new(), output)
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	expect(status(output).is_empty(), "replacing the output with another resource stops tracking")
	expect(not (ResourceLoader.load(output, "Resource", ResourceLoader.CACHE_MODE_IGNORE) is CubismModelResource), "tracker preserves replacement resource")
	expect(CubismModelImporter.import_model(source, output, true) == OK, "restore tracked model for restart checks")
	EditorInterface.get_resource_filesystem().update_file(output)
	await settle()
	# Leave the source and result for restart/cache-rebuild verification by the runner.
	for failure in failures:
		printerr("DEPENDENCY_TRACKER_FAIL: ", failure)
	print("CUBISM_DEPENDENCY_TRACKER cases=", cases, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_DEPENDENCY_TRACKER_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
