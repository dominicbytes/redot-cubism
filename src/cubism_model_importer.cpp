// SPDX-License-Identifier: MIT
#include "cubism_model_importer.hpp"
#include "cubism_model_factory.hpp"
#include "cubism_model_resource.hpp"
#include "cubism_manifest_parser.hpp"
#include "cubism_build_info.hpp"
#include "cubism_texture_import.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
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
int32_t CubismModelImporter::_get_format_version() const { return 3; }
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
    const Error texture_error = provision_cubism_textures(model);
    if (texture_error != OK) return texture_error;
    // The engine owns these sidecars; reading them detects texture/audio import
    // setting changes without modifying their contents or treating them as outputs.
    Dictionary files = model->get_dependency_fingerprints();
    const Array paths = files.keys();
    for (int i = 0; i < paths.size(); ++i) {
        const String path = paths[i];
        if (path.ends_with(".png") || path.ends_with(".wav") || path.ends_with(".ogg")) {
            const String sidecar = path + String(".import");
            const Dictionary state = CubismManifestParser::validate_project_file(sidecar);
            files[sidecar] = state["status"] == String("file") ? FileAccess::get_sha256(sidecar) : String("missing");
        }
    }
    model->set_dependency_fingerprints(files);
    model->set_import_fingerprint(fingerprint(files, model->get_import_options()));
    const Error error = ResourceSaver::get_singleton()->save(model, destination);
    if (error == OK && ResourceLoader::get_singleton()->has_cached(destination)) {
        // Keep resources already open in the Inspector or a scene up to date.
        ResourceLoader::get_singleton()->load(destination, "CubismModelResource", ResourceLoader::CACHE_MODE_REPLACE);
    }
    return error;
}

String CubismModelImporter::fingerprint(const Dictionary &files, const Dictionary &options) {
    const Dictionary versions = CubismBuildInfo::get_versions();
    Dictionary data;
    data["format_version"] = 3;
    data["texture_policy"] = "lossless_source_rgba_mipmaps_v1";
    data["resource_schema"] = 1;
    for (const String key : {String("addon_version"), String("addon_commit"), String("framework_commit"), String("core_version"), String("redot_api_sha256")}) data[key] = versions[key];
    data["files"] = files;
    data["options"] = options;
    return JSON::stringify(data, "", true, true).sha256_text();
}
