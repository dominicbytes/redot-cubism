# SPDX-License-Identifier: MIT
extends SceneTree

var failures: Array[String] = []
var checks := 0

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var model := GDCubismUserModel.new()
	model.playback_process_mode = GDCubismUserModel.MANUAL
	model.physics_evaluate = false
	model.pose_update = false
	var hit := GDCubismEffectHitArea.new()
	var probe := GDCubismEffectCustom.new()
	model.add_child(hit)
	model.add_child(probe)
	root.add_child(model)
	model.model = load("res://factory-model.res") as CubismModelResource
	expect(model.is_initialized(), "fixture loads")
	if model.is_initialized():
		model.advance(0.016)
		expect(hit.get_detail(model, "MissingDrawable").is_empty(), "missing drawable returns empty detail")
		expect(hit.get_detail(null, "MissingDrawable").is_empty(), "missing model returns empty detail")
		var meshes := model.get_meshes()
		var areas := model.get_hit_areas()
		expect(not areas.is_empty(), "fixture supplies a hit area")
		if not areas.is_empty():
			var id: String = areas[0].id
			var mesh_instance: MeshInstance2D = meshes[id]
			var original := mesh_instance.mesh
			expect(not hit.get_detail(model, id).is_empty(), "valid drawable returns bounds")
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
			var nonindexed := ArrayMesh.new()
			nonindexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
			var mesh_3d := ArrayMesh.new()
			mesh_3d.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var entered: Array[String] = []
			hit.hit_area_entered.connect(func(_owner: GDCubismUserModel, value: String): entered.append(value))
			var replacement: Array[Mesh] = [null]
			probe.cubism_prologue.connect(func(_owner: GDCubismUserModel, _delta: float): mesh_instance.mesh = replacement[0])
			probe.cubism_epilogue.connect(func(_owner: GDCubismUserModel, _delta: float): mesh_instance.mesh = original)
			for invalid: Mesh in [null, ArrayMesh.new(), QuadMesh.new(), nonindexed, mesh_3d]:
				replacement[0] = invalid
				mesh_instance.mesh = invalid
				expect(hit.get_detail(model, id).is_empty(), "invalid geometry returns empty detail")
				mesh_instance.mesh = original
				hit.set_target(Vector2.ZERO)
				model.advance(0.016)
				expect(not entered.has(id), "invalid geometry skipped during monitoring")
				entered.clear()
			expect(not hit.get_detail(model, id).is_empty(), "restored geometry still works")
	model.free()
	for failure in failures: printerr("CUBISM_LEGACY_HIT_AREA_FAIL: ", failure)
	if failures.is_empty(): print("CUBISM_LEGACY_HIT_AREA_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
