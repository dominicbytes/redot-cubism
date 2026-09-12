# SPDX-License-Identifier: MIT
extends SceneTree
## Read packaged native identity with the matching editor before template launch.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var build: Dictionary = ClassDB.class_call_static("CubismBuildInfo", "get_versions") if ClassDB.class_exists("CubismBuildInfo") else {}
	var report := FileAccess.open(args[0], FileAccess.WRITE)
	if report == null:
		quit(2)
		return
	report.store_string(JSON.stringify(build, "\t") + "\n")
	report.close()
	print("CUBISM_EXPORT_IDENTITY_PASS")
	quit()
