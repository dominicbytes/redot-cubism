# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []

func expect(value: bool, label: String) -> void:
	if not value: failures.append(label)

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("Cannot write fixture " + path)
		return
	file.store_buffer(bytes)
	file.close()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://factory-model.res") as CubismModelResource
	var probe := GDCubismUserModel.new()
	root.add_child(probe)
	probe.model = resource
	var id := ""
	for parameter: GDCubismParameter in probe.get_parameters():
		if parameter.minimum_value <= 0 and parameter.maximum_value >= 1:
			id = parameter.id
			break
	probe.free()
	if id.is_empty():
		push_error("Fixture has no parameter spanning [0,1]")
		quit(1)
		return
	var directory := "user://sdk-json-compatibility"
	expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "create private fixture folder")
	write_bytes(directory.path_join("model.moc3"), FileAccess.get_file_as_bytes(resource.moc_path))
	var textures: Array[String] = []
	for index in resource.textures.size():
		var filename := "texture-%d.png" % index
		expect(resource.textures[index].get_image().save_png(directory.path_join(filename)) == OK, "write private texture")
		textures.append(filename)
	var base := '{"Version":3,"Meta":{"Duration":1,"Fps":60,"Loop":false,"CurveCount":1,"TotalSegmentCount":1,"TotalPointCount":2,"FadeInTime":0,"FadeOutTime":0},"Curves":[{"Target":"Parameter","Id":%s,"Segments":[0,0,0,1,1]}]}' % JSON.stringify(id)
	var escaped_id := '"\\u%04x%s"' % [id.unicode_at(0), id.substr(1)]
	var variants := [base, "\ufeff" + base, base.replace('"Version":3,', '"Version":3 ,'),
		base.replace('"Id":' + JSON.stringify(id), '"Id":' + escaped_id),
		base.replace('[0,0,0,1,1]', '[0e0,0e0,0e0,1e0,1e0]')]
	var baseline := 0.0
	for index in variants.size():
		var motion_file := "motion-%d.motion3.json" % index
		write_bytes(directory.path_join(motion_file), variants[index].to_utf8_buffer())
		var manifest := {"Version":3,"FileReferences":{"Moc":"model.moc3","Textures":textures,
			"Motions":{"待機_😀":[{"File":motion_file,"FadeInTime":0,"FadeOutTime":0}]}}}
		var source := directory.path_join("model-%d.model3.json" % index)
		write_bytes(source, JSON.stringify(manifest).to_utf8_buffer())
		var model := GDCubismUserModel.new()
		model.playback_process_mode = GDCubismUserModel.MANUAL
		model.physics_evaluate = false
		model.pose_update = false
		root.add_child(model)
		model.assets = source
		expect(model.is_initialized(), "JSON variant %d loads: %s" % [index, model.get_last_error()])
		if model.is_initialized():
			expect(model.start_motion("待機_😀", 0, GDCubismUserModel.PRIORITY_FORCE).get_error() == OK, "variant motion starts")
			for step in 30: model.advance(1.0 / 60.0)
			for parameter: GDCubismParameter in model.get_parameters():
				if parameter.id != id: continue
				if index == 0:
					baseline = parameter.value
					expect(baseline > 0.4 and baseline < 0.6, "canonical motion evaluates selected parameter")
				else: expect(absf(parameter.value - baseline) < 1e-5, "equivalent JSON preserves playback")
		model.free()
	for failure in failures: printerr("CUBISM_SDK_JSON_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_SDK_JSON_PASS variants=5")
	quit(0 if failures.is_empty() else 1)
