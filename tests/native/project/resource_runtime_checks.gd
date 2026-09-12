# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)

func values(node: GDCubismUserModel) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for parameter: GDCubismParameter in node.get_parameters():
		result.append(parameter.value)
	return result

func vertices(node: Node) -> PackedVector2Array:
	for child in node.get_children():
		if child is MeshInstance2D and child.mesh.get_surface_count() > 0:
			return child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return PackedVector2Array()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
	var resource := load("res://factory-model.res") as CubismModelResource
	expect(resource != null, "factory resource loads")
	if resource == null:
		quit(1)
		return
	var first := GDCubismUserModel.new()
	first.playback_process_mode = GDCubismUserModel.MANUAL
	first.physics_evaluate = false
	first.pose_update = false
	root.add_child(first)
	first.model = resource
	expect(first.is_initialized(), "resource runtime ready: " + str(first.get_last_error()))
	var second := GDCubismUserModel.new()
	second.playback_process_mode = GDCubismUserModel.MANUAL
	second.physics_evaluate = false
	second.pose_update = false
	root.add_child(second)
	second.model = resource
	expect(second.is_initialized(), "second runtime from shared resource")
	if first.is_initialized() and second.is_initialized():
		var baseline := values(second)
		var motion := first.start_motion(fixture.motion_group, 0, GDCubismUserModel.PRIORITY_FORCE)
		expect(motion.get_error() == OK, "resource motion starts")
		var changed := false
		for frame in 120:
			first.advance(1.0 / 60.0)
			changed = changed or values(first) != baseline
		expect(changed, "resource motion changes parameters")
		expect(values(second) == baseline, "shared resource instances remain independent")
		first.start_expression(fixture.expression)
		for frame in 90:
			first.advance(1.0 / 60.0)
		var parameter: GDCubismParameter = first.get_parameters()[0]
		first.model = resource
		expect(first.is_initialized(), "resource reload")
		expect(not parameter.is_valid(), "reload invalidates old parameter handle")
		root.remove_child(first)
		expect(not first.is_initialized(), "resource unload on tree exit")
		root.add_child(first)
		expect(first.is_initialized(), "resource reload on tree reentry")
		first.assets = fixture.model
		expect(first.is_initialized() and first.model == null, "switch to legacy raw loading")
		first.model = resource
		expect(first.is_initialized() and first.assets.is_empty(), "switch back to resource")
		var invalid := resource.duplicate(true) as CubismModelResource
		invalid.moc_path = "res://../outside.moc3"
		first.model = invalid
		expect(not first.is_initialized() and str(first.get_last_error()).contains("Invalid imported"), "unsafe resource path rejected before file access")
		invalid = resource.duplicate(true) as CubismModelResource
		invalid.dependency_fingerprints[invalid.moc_path] = "stale"
		first.model = invalid
		expect(not first.is_initialized() and str(first.get_last_error()).contains("stale"), "stale raw fingerprint rejected")
		first.model = resource
		expect(first.is_initialized(), "load recovers after rejection")
		var baseline_vertices := vertices(second)
		var laid_out := resource.duplicate(true) as CubismModelResource
		laid_out.layout = {"height": 4.0, "x": 0.25, "y": -0.125}
		first.model = laid_out
		expect(first.is_initialized(), "layout resource loads")
		var actual := vertices(first)
		var expected_offset := Vector2(0.25, 0.125) * resource.canvas_size.y / 2.0
		expect(not actual.is_empty() and actual.size() == baseline_vertices.size(), "layout keeps vertex count")
		var layout_matches := actual.size() == baseline_vertices.size()
		for i in mini(actual.size(), baseline_vertices.size()):
			layout_matches = layout_matches and actual[i].is_equal_approx(baseline_vertices[i] * 2.0 + expected_offset)
		expect(layout_matches, "SDK layout maps to expected pixel-space vertices")
		laid_out.layout = {"height": 0.0}
		first.model = laid_out
		expect(not first.is_initialized(), "singular layout rejected")
		var unicode_resource: CubismModelResource
		if FileAccess.file_exists("res://unicode-resource.res"):
			unicode_resource = load("res://unicode-resource.res")
		elif OS.has_feature("editor"):
			unicode_resource = resource.duplicate(true)
			var unicode_path := "res://fixture/模型_😀.moc3"
			var output := FileAccess.open(unicode_path, FileAccess.WRITE)
			output.store_buffer(FileAccess.get_file_as_bytes(resource.moc_path))
			output.close()
			unicode_resource.moc_path = unicode_path
			unicode_resource.dependency_fingerprints[unicode_path] = resource.dependency_fingerprints[resource.moc_path]
			var motions: Array = unicode_resource.motion_groups[fixture.motion_group]
			for descriptor: CubismMotionDescriptor in motions:
				descriptor.group = &"待機_😀"
			unicode_resource.motion_groups = {"待機_😀": motions}
			# Runtime reads the imported settings, even when the original manifest is absent.
			unicode_resource.source_model_path = "res://missing-source.model3.json"
			expect(ResourceSaver.save(unicode_resource, "res://unicode-resource.res") == OK, "save Unicode runtime fixture")
		expect(unicode_resource != null, "Unicode resource available in source or PCK")
		if unicode_resource != null:
			first.model = unicode_resource
			expect(first.is_initialized(), "Unicode MOC path loads without source manifest")
			if first.is_initialized():
				expect(first.get_motions().has("待機_😀"), "Unicode group name survives adapter")
				var unicode_hint := false
				for property: Dictionary in first.get_property_list():
					unicode_hint = unicode_hint or str(property.hint_string).contains("待機_😀_0")
				expect(unicode_hint, "Unicode motion name in inspector enum")
				var unicode_motion := first.start_motion("待機_😀", 0, GDCubismUserModel.PRIORITY_FORCE)
				expect(unicode_motion.get_error() == OK, "Unicode motion lookup")
				unicode_resource.motion_groups = {}
				expect(first.get_motions().has("待機_😀"), "adapter snapshot survives shared-resource mutation")
		var switched := [false]
		var replacement := resource.duplicate(true) as CubismModelResource
		replacement.motion_groups = {}
		var replace_during_load := func(_child: Node) -> void:
			if not switched[0]:
				switched[0] = true
				first.model = replacement
		first.child_entered_tree.connect(replace_during_load)
		first.model = resource
		first.child_entered_tree.disconnect(replace_during_load)
		expect(switched[0] and first.is_initialized() and first.get_motions().is_empty(), "resource replacement during load is deferred safely")
	first.free()
	second.free()
	for failure in failures:
		printerr("RESOURCE_RUNTIME_FAIL: ", failure)
	print("CUBISM_RESOURCE_RUNTIME cases=", checks, " failures=", failures.size())
	if failures.is_empty():
		print("CUBISM_RESOURCE_RUNTIME_PASS")
	quit(0 if failures.is_empty() else 1)
