# SPDX-License-Identifier: MIT
extends SceneTree

func _initialize() -> void:
    var values: Array = [null, true, 12, 0.5, "text", {"key": "value"}, [1, 2]]
    var version: Dictionary = Engine.get_version_info()
    var has_struct: bool = version.major == 26 and version.minor >= 3
    if has_struct:
        # Parse the new constructor only on engines that provide Struct.
        var script := GDScript.new()
        script.source_code = "extends RefCounted\nfunc make_value():\n\treturn Struct()\n"
        assert(script.reload() == OK)
        var value: Variant = script.new().make_value()
        assert(typeof(value) == 39)
        values.append(value)
    var resource := CubismModelResource.new()
    for cycle in 1000:
        for value: Variant in values:
            resource.set_runtime_extension(value)
            assert(typeof(resource.get_runtime_extension()) == typeof(value))
            resource.set_runtime_extension(null)
        if has_struct:
            resource.import_options = {"rendering/mask_quality": values.back()}
            assert(resource.get_mask_quality() == -1)
    resource = null
    print("CUBISM_VARIANT_COMPATIBILITY_PASS cycles=1000 struct=", has_struct)
    quit()
