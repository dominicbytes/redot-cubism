// SPDX-License-Identifier: MIT
#include "cubism_export_validator.hpp"
#include "cubism_model_factory.hpp"
#include "cubism_model_importer.hpp"
#include "cubism_manifest_parser.hpp"
#include "cubism_descriptors.hpp"
#include "private/redot_cubism_model_setting.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/portable_compressed_texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void CubismExportValidator::_bind_methods() {
    ClassDB::bind_static_method("CubismExportValidator", D_METHOD("validate_model", "model"), &CubismExportValidator::validate_model);
}

Dictionary CubismExportValidator::validate_model(const Ref<CubismModelResource> &model) {
    Array diagnostics;
    PackedStringArray raw_files;
    auto error = [&](const String &path, const String &message) {
        if (diagnostics.size() >= 32) return;
        Dictionary item;
        item["path"] = path;
        item["message"] = message;
        diagnostics.push_back(item);
    };
    auto finish = [&]() {
        Dictionary result;
        result["ok"] = diagnostics.is_empty();
        result["diagnostics"] = diagnostics;
        // Never return a partial injection list after a failed validation.
        result["raw_files"] = diagnostics.is_empty() ? raw_files : PackedStringArray();
        return result;
    };
    if (model.is_null()) { error("model", "Expected an imported CubismModelResource."); return finish(); }
    if (!model->get_source_model_path().ends_with(".model3.json")) { error("source_model_path", "Expected a model3.json import source."); return finish(); }
    String settings_error;
    RedotCubismModelSetting settings(model, settings_error);
    if (!settings_error.is_empty()) { error("model", settings_error); return finish(); }
    // Rebuild in memory only: validate current source bytes, paths, MOC and
    // descriptors through the same factory used by import. Never save/reimport.
    const Dictionary rebuilt = CubismModelFactory::build_with_options(model->get_source_model_path(), model->get_import_options());
    if (!bool(rebuilt["ok"])) {
        diagnostics = rebuilt["diagnostics"];
        return finish();
    }
    const Ref<CubismModelResource> current = rebuilt["model"];
    Dictionary files = current->get_dependency_fingerprints();
    const Array source_paths = files.keys();
    for (int i = 0; i < source_paths.size(); ++i) {
        const String path = source_paths[i];
        if (String(files[path]) != "missing" && (path.ends_with(".json") || path.ends_with(".moc3"))) raw_files.push_back(path);
        if (path.ends_with(".png") || path.ends_with(".wav") || path.ends_with(".ogg")) {
            const String sidecar = path + String(".import");
            const String state = CubismManifestParser::validate_project_file(sidecar)["status"];
            if (state == "missing" && String(files[path]) == "missing") { files[sidecar] = "missing"; continue; }
            if (state != "file") {
                error(sidecar, "Missing or unsafe texture/audio import metadata. Import the asset before export.");
                continue;
            }
            const Ref<FileAccess> input = FileAccess::open(sidecar, FileAccess::READ);
            if (input.is_null() || input->get_length() > 1024 * 1024) {
                error(sidecar, "Cannot read import metadata within the 1 MiB limit.");
                continue;
            }
            files[sidecar] = FileAccess::get_sha256(sidecar);
        }
    }
    raw_files.sort();
    if (model->get_source_hash() != current->get_source_hash()
            || JSON::stringify(model->get_dependency_fingerprints(), "", true, true) != JSON::stringify(files, "", true, true)
            || model->get_import_fingerprint() != CubismModelImporter::fingerprint(files, model->get_import_options())) {
        error("import_fingerprint", "Imported model is stale or lacks current import provenance. Reimport before export.");
    }
    if (model->get_moc_path() != current->get_moc_path() || model->get_moc_version() != current->get_moc_version()
            || model->get_physics_path() != current->get_physics_path() || model->get_pose_path() != current->get_pose_path()
            || model->get_user_data_path() != current->get_user_data_path() || model->get_display_info_path() != current->get_display_info_path()
            || model->get_texture_paths() != current->get_texture_paths() || model->get_dependency_paths() != current->get_dependency_paths()) {
        error("model", "Stored source references differ from the current manifest. Reimport before export.");
    }
    const auto textures = model->get_textures();
    for (int i = 0; i < textures.size(); ++i) {
        const Ref<PortableCompressedTexture2D> texture = textures[i];
        const String path = texture.is_valid() ? texture->get_path() : String();
        const String hash = path.get_file().get_basename();
        if (texture.is_null() || !path.begins_with("res://cubism_generated/textures/") || !path.ends_with(".res")
                || hash.length() != 64 || CubismManifestParser::validate_project_file(path)["status"] != String("file")) {
            error("textures[" + String::num_int64(i) + String("]"), "Expected a contained, imported Cubism texture resource.");
            continue;
        }
        const Ref<FileAccess> input = FileAccess::open(path, FileAccess::READ);
        if (input.is_null() || input->get_length() > 512ULL * 1024 * 1024 || FileAccess::get_sha256(path) != hash) {
            error(path, "Imported texture is missing, oversized or changed. Reimport before export.");
        }
    }
    const Array expected_expressions = current->get_expressions();
    const Array expressions = model->get_expressions();
    if (expressions.size() != expected_expressions.size()) error("expressions", "Expression catalog differs from the imported source.");
    for (int i = 0; i < expressions.size() && i < expected_expressions.size(); ++i) {
        const Ref<CubismExpressionDescriptor> actual = expressions[i], expected = expected_expressions[i];
        if (actual.is_null() || actual->get_source_path() != expected->get_source_path() || actual->get_id() != expected->get_id()) {
            error("expressions[" + String::num_int64(i) + String("]"), "Expression source differs from the imported source.");
        }
    }
    const Dictionary groups = model->get_motion_groups(), expected_groups = current->get_motion_groups();
    if (groups.size() != expected_groups.size()) error("motion_groups", "Motion catalog differs from the imported source.");
    const Array names = expected_groups.keys();
    for (int i = 0; i < names.size(); ++i) {
        const String name = names[i];
        const Array actual = groups.get(name, Array()), expected = expected_groups[name];
        if (!groups.has(name) || actual.size() != expected.size()) error("motion_groups." + name, "Motion group differs from the imported source.");
        for (int j = 0; j < actual.size() && j < expected.size(); ++j) {
            const Ref<CubismMotionDescriptor> motion = actual[j], source = expected[j];
            const String property = "motion_groups." + name + String("[") + String::num_int64(j) + String("]");
            if (motion.is_null() || motion->get_source_path() != source->get_source_path() || motion->get_sound_path() != source->get_sound_path()) {
                error(property, "Motion source differs from the imported source.");
                continue;
            }
            const Ref<AudioStream> sound = motion->get_sound();
            if ((!source->get_sound_path().is_empty() && (sound.is_null() || sound->get_path() != source->get_sound_path()))
                    || (source->get_sound_path().is_empty() && sound.is_valid())) {
                error(property + String(".sound"), "Expected the imported audio resource declared by the motion.");
            }
        }
    }
    return finish();
}
