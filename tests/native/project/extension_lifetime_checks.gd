# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	var model := CubismModelResource.new()
	var descriptor := load("res://addons/gd_cubism/gd_cubism.gdextension")
	model.runtime_extension = descriptor
	if model.runtime_extension != descriptor:
		printerr("CUBISM_EXTENSION_LIFETIME_FAIL descriptor identity")
		quit(1)
		return
	model = null
	descriptor = null
	# A passing marker alone is insufficient: the harness must check the exit
	# code, because the old Resource wrapper crashed after library unloading.
	print("CUBISM_EXTENSION_LIFETIME_PASS")
	quit()
