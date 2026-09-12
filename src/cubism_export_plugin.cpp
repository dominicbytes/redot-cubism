// SPDX-License-Identifier: MIT
#include "cubism_export_plugin.hpp"
#include "cubism_export_validator.hpp"
#include "cubism_manifest_parser.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
String CubismExportPlugin::_get_name() const { return "RedotCubismRawDependencies"; }
void CubismExportPlugin::_export_begin(const PackedStringArray &, bool, const String &, uint32_t) {
    injected.clear();
    seen_raw.clear();
    shaders_added = false;
}
void CubismExportPlugin::_export_end() {
    injected.clear();
    seen_raw.clear();
    shaders_added = false;
}
void CubismExportPlugin::_export_file(const String &path, const String &type, const PackedStringArray &) {
    if (path.begins_with("res://addons/gd_cubism/editor/")) { skip(); return; }
    // Avoid duplicate PCK entries when an include filter/all-resources selection
    // already exports raw files or shaders. Imported files still need normal remaps.
    if (!FileAccess::file_exists(path + String(".import"))) {
        if (injected.has(path)) { skip(); return; }
        if (path.ends_with(".json") || path.ends_with(".moc3") || path.ends_with(".gdshader")) seen_raw[path] = true;
    }
    if (type != "CubismModelResource" && !path.ends_with(".res") && !path.ends_with(".tres")
            && !path.ends_with(".tscn") && !path.ends_with(".scn")) return;
    const Dictionary checked = CubismExportValidator::validate_file(path);
    if (!bool(checked["ok"])) {
        UtilityFunctions::push_error("Cubism export validation failed: ", path, " ", checked["diagnostics"]);
        return;
    }
    if (int(checked["models"]) == 0) return;
    const Dictionary hashes = checked["raw_hashes"];
    const Array files = hashes.keys();
    // Stage this model's payload before adding any file. Ordinary engine export
    // callbacks cannot cancel export; checked output promotion remains mandatory.
    Dictionary payload;
    for (int i = 0; i < files.size(); ++i) {
        const String file = files[i];
        if (injected.has(file) && injected[file] == hashes[file]) continue;
        if (injected.has(file) || CubismManifestParser::validate_project_file(file)["status"] != String("file")) {
            UtilityFunctions::push_error("Cubism export source is conflicting or unavailable: ", file);
            return;
        }
        const Ref<FileAccess> input = FileAccess::open(file, FileAccess::READ);
        const uint64_t limit = file.ends_with(".json") ? 4ULL * 1024 * 1024 : 64ULL * 1024 * 1024;
        if (input.is_null() || input->get_length() > limit) {
            UtilityFunctions::push_error("Cubism export source exceeds read limit: ", file);
            return;
        }
        const uint64_t size = input->get_length();
        const PackedByteArray bytes = input->get_buffer(size);
        Ref<HashingContext> hash;
        hash.instantiate();
        hash->start(HashingContext::HASH_SHA256);
        if (!bytes.is_empty()) hash->update(bytes);
        if (uint64_t(bytes.size()) != size || hash->finish().hex_encode() != String(hashes[file])) {
            UtilityFunctions::push_error("Cubism export source changed after validation: ", file);
            return;
        }
        if (!seen_raw.has(file)) payload[file] = bytes;
    }
    if (!shaders_added) {
        for (const char *name : {"mask", "mask_add", "mask_add_inv", "mask_mix", "mask_mix_inv", "mask_mul", "mask_mul_inv", "norm_add", "norm_mix", "norm_mul"}) {
            const String file = String("res://addons/gd_cubism/res/shader/2d_cubism_") + name + String(".gdshader");
            if (seen_raw.has(file)) continue;
            if (CubismManifestParser::validate_project_file(file)["status"] != String("file")) {
                UtilityFunctions::push_error("Missing Cubism export shader: ", file);
                return;
            }
            const Ref<FileAccess> input = FileAccess::open(file, FileAccess::READ);
            if (input.is_null() || input->get_length() > 1024 * 1024) {
                UtilityFunctions::push_error("Cannot read Cubism export shader: ", file);
                return;
            }
            const uint64_t size = input->get_length();
            const PackedByteArray bytes = input->get_buffer(size);
            if (uint64_t(bytes.size()) != size) {
                UtilityFunctions::push_error("Cubism export shader changed during read: ", file);
                return;
            }
            payload[file] = bytes;
        }
    }
    const Array paths = payload.keys();
    for (int i = 0; i < paths.size(); ++i) {
        add_file(paths[i], payload[paths[i]], false);
        if (!hashes.has(paths[i])) injected[paths[i]] = "shader";
    }
    injected.merge(hashes, true);
    shaders_added = true;
}
