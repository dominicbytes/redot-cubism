// SPDX-License-Identifier: MIT
#include "cubism_model_importer.hpp"
#include "cubism_model_factory.hpp"
#include "cubism_model_resource.hpp"
#include "cubism_manifest_parser.hpp"
#include "cubism_build_info.hpp"
#include "cubism_texture_import.hpp"
#include "cubism_import_options.hpp"
#include "cubism_export_validator.hpp"
#include <godot_cpp/classes/config_file.hpp>
#include <godot_cpp/classes/editor_file_system.hpp>
#include <godot_cpp/classes/editor_interface.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/resource_saver.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void CubismModelImporter::_bind_methods() {
    ClassDB::bind_static_method("CubismModelImporter", D_METHOD("import_source", "source_file"), &CubismModelImporter::import_source);
    ClassDB::bind_static_method("CubismModelImporter", D_METHOD("import_model", "source_file", "destination", "strict_optional_files"), &CubismModelImporter::import_model, DEFVAL(false));
    ClassDB::bind_static_method("CubismModelImporter", D_METHOD("import_model_with_options", "source_file", "destination", "options"), &CubismModelImporter::import_model_with_options);
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
    const Dictionary defaults = cubism_import_defaults();
    const Array keys = defaults.keys();
    for (int i = 0; i < keys.size(); ++i) {
        if (keys[i] == Variant("motions/convert_to_redot_animation")) continue;
        Dictionary option;
        option["name"] = keys[i];
        option["default_value"] = defaults[keys[i]];
        if (keys[i] == Variant("rendering/mask_quality")) {
            option["property_hint"] = PROPERTY_HINT_ENUM;
            option["hint_string"] = "Low,Medium,High";
        }
        options.push_back(option);
    }
    return options;
}
bool CubismModelImporter::_get_option_visibility(const String &, const StringName &, const Dictionary &) const { return true; }
float CubismModelImporter::_get_priority() const { return 2.0f; }
// Imported texture/audio resources must exist before factory assembly.
int32_t CubismModelImporter::_get_import_order() const { return 100; }
int32_t CubismModelImporter::_get_format_version() const { return 7; }
bool CubismModelImporter::_can_import_threaded() const { return false; }
Error CubismModelImporter::_import(const String &source_file, const String &save_path,
        const Dictionary &options, const TypedArray<String> &, const TypedArray<String> &) const {
    return import_model_with_options(source_file, save_path + String(".res"), options);
}

Error CubismModelImporter::import_model(const String &source_file, const String &destination, bool strict_optional_files) {
    Dictionary options;
    options["validation/strict_optional_files"] = strict_optional_files;
    return import_model_with_options(source_file, destination, options);
}

Error CubismModelImporter::import_source(const String &source_file) {
    if (!source_file.ends_with(".model3.json")) return ERR_FILE_UNRECOGNIZED;
    if (CubismManifestParser::validate_project_file(source_file)["status"] != String("file")) return ERR_FILE_BAD_PATH;
    auto *editor = EditorInterface::get_singleton();
    if (editor == nullptr || editor->get_resource_filesystem()->is_scanning()) return ERR_BUSY;
    const String sidecar = source_file + String(".import");
    const String state = CubismManifestParser::validate_project_file(sidecar)["status"];
    if (state != "missing") {
        if (state != "file") return ERR_FILE_BAD_PATH;
        const Ref<FileAccess> file = FileAccess::open(sidecar, FileAccess::READ);
        if (file.is_null() || file->get_length() > 4 * 1024 * 1024) return ERR_FILE_CANT_READ;
        Ref<ConfigFile> metadata;
        metadata.instantiate();
        if (metadata->parse(file->get_as_text(), false) != OK) return ERR_PARSE_ERROR;
        // Do not take over sources assigned to another importer or overwrite
        // existing Import-dock choices with an arbitrary derived .res's options.
        if (metadata->get_value("remap", "importer", "") != String("redot.cubism.model")) return ERR_ALREADY_IN_USE;
    }
    auto *filesystem = editor->get_resource_filesystem();
    filesystem->update_file(source_file);
    PackedStringArray sources;
    sources.push_back(source_file);
    filesystem->reimport_files(sources);
    const Ref<CubismModelResource> resource = ResourceLoader::get_singleton()->load(source_file, "CubismModelResource", ResourceLoader::CACHE_MODE_REPLACE);
    if (resource.is_null()) return ERR_CANT_CREATE;
    return bool(CubismExportValidator::validate_model(resource)["ok"]) ? OK : ERR_INVALID_DATA;
}

Error CubismModelImporter::import_model_with_options(const String &source_file, const String &destination, const Dictionary &options) {
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
    const Dictionary result = CubismModelFactory::build_with_options(source_file, options);
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
    data["format_version"] = 7;
    data["maximum_file_count"] = cubism_maximum_file_count();
    data["texture_policy"] = "lossless_source_rgba_mipmaps_v1";
    data["resource_schema"] = 1;
    for (const String key : {String("addon_version"), String("addon_commit"), String("framework_commit"), String("core_version"), String("redot_api_sha256")}) data[key] = versions[key];
    data["files"] = files;
    Dictionary normalized = cubism_import_defaults();
    normalized.merge(options, true);
    data["options"] = normalized;
    return JSON::stringify(data, "", true, true).sha256_text();
}
