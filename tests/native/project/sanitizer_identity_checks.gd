# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
	var versions := CubismBuildInfo.get_versions()
	var mode: String = versions.get("sanitizer", "none")
	print("CUBISM_SANITIZER_MODE:", mode)
	if mode not in ["address", "address,undefined"]:
		printerr("Expected ASan or combined ASan/UBSan addon, got ", mode)
		quit(1)
		return
	print("CUBISM_SANITIZER_IDENTITY_PASS")
	quit()
