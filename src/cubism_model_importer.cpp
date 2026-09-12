// SPDX-License-Identifier: MIT
#include "cubism_model_importer.hpp"
#include "cubism_model_factory.hpp"
#include "cubism_model_resource.hpp"
#include "cubism_manifest_parser.hpp"
#include <godot_cpp/classes/resource_saver.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void CubismModelImporter::_bind_methods() {
    ClassDB::bind_static_method("CubismModelImporter", D_METHOD("import_model", "source_file", "destination", "strict_optional_files"), &CubismModelImporter::import_model, DEFVAL(false));
}

String CubismModelImporter::_get_importer_name() const { return "redot.cubism.model"; }
String CubismModelImporter::_get_visible_name() const { return "Cubism Model"; }
PackedStringArray CubismModelImporter::_get_recognized_extensions() const {
    PackedStringArray extensions;
    extensions.push_back("model3.json");
    return extensions;
}
String CubismModelImporter::_get_save_extension() const { return "res"; }
String CubismModelImporter::_get_resource_type() const { return "CubismModelResource"; }
int32_t CubismModelImporter::_get_preset_count() const { return 0; }
TypedArray<Dictionary> CubismModelImporter::_get_import_options(const String &, int32_t) const {
    TypedArray<Dictionary> options;
    Dictionary strict;
    strict["name"] = "validation/strict_optional_files";
    strict["default_value"] = false;
    options.push_back(strict);
    return options;
}
bool CubismModelImporter::_get_option_visibility(const String &, const StringName &, const Dictionary &) const { return true; }
float CubismModelImporter::_get_priority() const { return 2.0f; }
// Imported texture/audio resources must exist before factory assembly.
int32_t CubismModelImporter::_get_import_order() const { return 100; }
int32_t CubismModelImporter::_get_format_version() const { return 1; }
bool CubismModelImporter::_can_import_threaded() const { return false; }
Error CubismModelImporter::_import(const String &source_file, const String &save_path,
        const Dictionary &options, const TypedArray<String> &, const TypedArray<String> &) const {
    return import_model(source_file, save_path + String(".res"), options.get("validation/strict_optional_files", false));
}

Error CubismModelImporter::import_model(const String &source_file, const String &destination, bool strict_optional_files) {
    if (!source_file.ends_with(".model3.json")) {
        return ERR_FILE_UNRECOGNIZED;
    }
    if (!destination.ends_with(".res") && !destination.ends_with(".tres")) {
        return ERR_INVALID_PARAMETER;
    }
    const Dictionary target = CubismManifestParser::validate_project_file(destination);
    const String status = target.get("status", "error");
    if (status != "file" && status != "missing") {
        return ERR_FILE_BAD_PATH;
    }
    const Dictionary result = CubismModelFactory::build(source_file, strict_optional_files);
    if (!bool(result.get("ok", false))) {
        UtilityFunctions::push_error("Cubism import failed: ", source_file, " ", result.get("diagnostics", Array()));
        return ERR_PARSE_ERROR;
    }
    const Ref<CubismModelResource> model = result["model"];
    return ResourceSaver::get_singleton()->save(model, destination);
}
