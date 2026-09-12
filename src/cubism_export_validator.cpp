// SPDX-License-Identifier: MIT
#include "cubism_export_validator.hpp"
#include "cubism_model_factory.hpp"
#include "cubism_model_importer.hpp"
#include "cubism_manifest_parser.hpp"
#include "cubism_descriptors.hpp"
#include "private/redot_cubism_model_setting.hpp"
#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/packed_scene.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_state.hpp>
#include <functional>
#include <set>
#include <godot_cpp/classes/portable_compressed_texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void CubismExportValidator::_bind_methods() {
    ClassDB::bind_static_method("CubismExportValidator", D_METHOD("validate_file", "path"), &CubismExportValidator::validate_file);
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
    const Ref<Resource> extension = model->get_runtime_extension();
    if (extension.is_null() || extension->get_class() != StringName("GDExtension")
            || extension->get_path() != "res://addons/gd_cubism/gd_cubism.gdextension") {
        error("runtime_extension", "Missing native extension resource edge. Reimport before export.");
        return finish();
    }
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

Dictionary CubismExportValidator::validate_file(const String &path) {
    Array diagnostics;
    Dictionary hashes;
    int models = 0, remaining = 100000;
    std::set<uint64_t> visited;
    auto error = [&](const String &message) {
        if (diagnostics.size() >= 32) return;
        Dictionary item;
        item["path"] = path;
        item["message"] = message;
        diagnostics.push_back(item);
    };
    // Resolve native node types through inherited scenes and instance overrides.
    // Never instantiate a user's scene (which can execute scripts) for preflight.
    std::function<StringName(const Ref<SceneState> &, const String &, int)> node_type;
    node_type = [&](const Ref<SceneState> &state, const String &node_path, int depth) -> StringName {
        if (state.is_null() || !diagnostics.is_empty()) return StringName();
        if (--remaining < 0 || depth > 64) { error("Scene graph exceeds export validation limits."); return StringName(); }
        for (int i = 0; i < state->get_node_count(); ++i) {
            if (--remaining < 0) { error("Scene graph exceeds export validation limits."); return StringName(); }
            const String candidate = state->get_node_path(i);
            if (candidate == node_path && !String(state->get_node_type(i)).is_empty()) return state->get_node_type(i);
        }
        for (int i = 0; i < state->get_node_count(); ++i) {
            if (--remaining < 0) { error("Scene graph exceeds export validation limits."); return StringName(); }
            const String candidate = state->get_node_path(i);
            const Ref<PackedScene> instance = state->get_node_instance(i);
            if (instance.is_null()) continue;
            if (candidate == node_path || candidate == "." || node_path.begins_with(candidate + String("/"))) {
                const String relative = candidate == node_path ? String(".") : candidate == "." ? node_path
                    : String("./") + node_path.substr(candidate.length() + 1);
                const StringName type = node_type(instance->get_state(), relative, depth + 1);
                if (!String(type).is_empty() || !diagnostics.is_empty()) return type;
            }
        }
        return StringName();
    };
    std::function<void(const Variant &, int)> visit;
    visit = [&](const Variant &value, int depth) {
        if (!diagnostics.is_empty()) return;
        if (--remaining < 0 || depth > 64) { error("Resource graph exceeds export validation limits."); return; }
        if (value.get_type() == Variant::OBJECT) {
            const Ref<Resource> resource = value;
            if (resource.is_null()) return;
            // External resources receive their own engine export callback. Do not
            // pull excluded files back into a selected export through this graph.
            const String owner = resource->get_path().get_slice("::", 0);
            if (!owner.is_empty() && owner != path) return;
            if (!visited.insert(resource->get_instance_id()).second) return;
            const Ref<PackedScene> scene = resource;
            if (scene.is_valid()) {
                const Ref<SceneState> state = scene->get_state();
                for (int i = 0; i < state->get_node_count() && diagnostics.is_empty(); ++i) {
                    for (int j = 0; j < state->get_node_property_count(i); ++j) {
                        if (--remaining < 0) { error("Scene graph exceeds export validation limits."); return; }
                        if (state->get_node_property_name(i, j) != StringName("assets")) continue;
                        const Variant assets = state->get_node_property_value(i, j);
                        if (assets.get_type() != Variant::STRING || String(assets).is_empty()) continue;
                        const String node_path = state->get_node_path(i);
                        const StringName type = node_type(state, node_path, depth + 1);
                        if (!String(type).is_empty() && ClassDBSingleton::get_singleton()->is_parent_class(type, "GDCubismUserModel")) {
                            Ref<CubismModelResource> bridge;
                            for (int k = 0; k < state->get_node_property_count(i); ++k) {
                                if (--remaining < 0) { error("Scene graph exceeds export validation limits."); return; }
                                if (state->get_node_property_name(i, k) == StringName("_legacy_model")) bridge = state->get_node_property_value(i, k);
                            }
                            if (bridge.is_valid() && bridge->get_source_model_path() == String(assets) && bridge->get_path() == String(assets)) continue;
                            error("Legacy Cubism assets on node " + node_path + String(" has no matching imported resource dependency. Prepare the legacy source, reload and save the scene, or assign an imported model resource before export."));
                            return;
                        }
                    }
                }
            }
            const Ref<CubismModelResource> model = resource;
            if (model.is_valid()) {
                ++models;
                const Dictionary result = validate_model(model);
                if (!bool(result["ok"])) { diagnostics = result["diagnostics"]; return; }
                const PackedStringArray raw = result["raw_files"];
                const Dictionary fingerprints = model->get_dependency_fingerprints();
                for (int i = 0; i < raw.size(); ++i) {
                    const String hash = fingerprints.get(raw[i], String());
                    if (hash.is_empty() || (hashes.has(raw[i]) && hashes[raw[i]] != Variant(hash))) {
                        error("Conflicting or missing raw source fingerprint: " + raw[i]);
                        return;
                    }
                    hashes[raw[i]] = hash;
                }
                return;
            }
            const TypedArray<Dictionary> properties = resource->get_property_list();
            for (int i = 0; i < properties.size(); ++i) {
                const Dictionary property = properties[i];
                if (int64_t(property["usage"]) & PROPERTY_USAGE_STORAGE) visit(resource->get(property["name"]), depth + 1);
            }
        } else if (value.get_type() == Variant::ARRAY) {
            const Array array = value;
            for (int i = 0; i < array.size() && diagnostics.is_empty(); ++i) visit(array[i], depth + 1);
        } else if (value.get_type() == Variant::DICTIONARY) {
            const Dictionary dictionary = value;
            const Array keys = dictionary.keys();
            for (int i = 0; i < keys.size() && diagnostics.is_empty(); ++i) {
                visit(keys[i], depth + 1);
                visit(dictionary[keys[i]], depth + 1);
            }
        }
    };
    if (CubismManifestParser::validate_project_file(path)["status"] != String("file")) error("Expected a contained resource file.");
    if (diagnostics.is_empty()) {
        const Ref<Resource> resource = ResourceLoader::get_singleton()->load(path, "", ResourceLoader::CACHE_MODE_IGNORE);
        if (resource.is_null()) error("Cannot load the selected resource for export validation.");
        else visit(resource, 0);
    }
    Dictionary result;
    result["ok"] = diagnostics.is_empty();
    result["diagnostics"] = diagnostics;
    result["models"] = models;
    result["raw_hashes"] = diagnostics.is_empty() ? hashes : Dictionary();
    return result;
}
