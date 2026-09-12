// SPDX-License-Identifier: MIT
#include "cubism_model_factory.hpp"
#include "cubism_manifest_parser.hpp"
#include "cubism_model_resource.hpp"
#include "cubism_descriptors.hpp"
#include "cubism_build_info.hpp"
#include "cubism_import_options.hpp"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <Model/CubismMoc.hpp>
#include <Model/CubismModel.hpp>
#include <cmath>
using namespace godot;
namespace Csm = Live2D::Cubism::Framework;
namespace Core = Live2D::Cubism::Core;
namespace {
String digest(const PackedByteArray &bytes) {
    Ref<HashingContext> hash;
    hash.instantiate();
    hash->start(HashingContext::HASH_SHA256);
    if (!bytes.is_empty()) hash->update(bytes);
    return hash->finish().hex_encode();
}
struct Inspection {
    Csm::CubismMoc *moc = nullptr;
    Csm::CubismModel *model = nullptr;
    ~Inspection() {
        if (model) moc->DeleteModel(model);
        if (moc) Csm::CubismMoc::Delete(moc);
    }
};
}
void CubismModelFactory::_bind_methods() {
    ClassDB::bind_static_method("CubismModelFactory", D_METHOD("build", "source_path", "strict_optional_files"), &CubismModelFactory::build, DEFVAL(false));
    ClassDB::bind_static_method("CubismModelFactory", D_METHOD("build_with_options", "source_path", "options"), &CubismModelFactory::build_with_options);
}
Dictionary CubismModelFactory::build(const String &source_path, bool strict_optional_files) {
    Dictionary options;
    options["validation/strict_optional_files"] = strict_optional_files;
    return build_with_options(source_path, options);
}
Dictionary CubismModelFactory::build_with_options(const String &source_path, const Dictionary &input_options) {
    const Dictionary checked = validate_cubism_import_options(input_options);
    if (!bool(checked["ok"])) {
        Dictionary result;
        result["ok"] = false;
        result["diagnostics"] = checked["diagnostics"];
        result["warnings"] = PackedStringArray();
        result["model"] = Variant();
        return result;
    }
    const Dictionary options = checked["options"];
    const bool strict_optional_files = options["validation/strict_optional_files"];
    Array diagnostics;
    PackedStringArray warnings;
    Dictionary fingerprints;
    bool ok = true;
    uint64_t total_bytes = 0;
    uint64_t texture_pixels = 0;
    auto error = [&](const String &path, const String &message) {
        ok = false;
        if (diagnostics.size() >= 32) return;
        Dictionary item; item["path"] = path; item["message"] = message; diagnostics.append(item);
    };
    auto exists = [&](const String &path, const String &property, bool optional) {
        const Dictionary result = CubismManifestParser::validate_project_file(path);
        if (result["status"] == String("file")) return true;
        if (optional && !strict_optional_files && result["status"] == String("missing")) {
            if (warnings.size() < 32) warnings.append(property + String(": missing optional file ") + path);
            fingerprints[path] = "missing";
        } else error(property, result["message"]);
        return false;
    };
    auto read = [&](const String &path, const String &property) -> PackedByteArray {
        const Ref<FileAccess> file = FileAccess::open(ProjectSettings::get_singleton()->globalize_path(path), FileAccess::READ);
        if (file.is_null()) { error(property, "Cannot open source file."); return {}; }
        const uint64_t size = file->get_length();
        const uint64_t limit = path.ends_with(".json") ? 4 * 1024 * 1024 : 64 * 1024 * 1024;
        if (size > limit || total_bytes + size > 512 * 1024 * 1024) { error(property, "Source exceeds the per-file or 512 MiB aggregate import limit."); return {}; }
        total_bytes += size;
        const PackedByteArray bytes = file->get_buffer(size);
        if (uint64_t(bytes.size()) != size || file->get_length() != size) { error(property, "Source changed length or could not be read completely."); return {}; }
        fingerprints[path] = digest(bytes);
        return bytes;
    };
    auto json = [&](const String &path, const String &property) -> String {
        const Dictionary decoded = CubismManifestParser::read_project_json(path);
        if (!bool(decoded["ok"])) { error(property, decoded["message"]); return {}; }
        const uint64_t size = int64_t(decoded["byte_length"]);
        if (total_bytes + size > 512 * 1024 * 1024) { error(property, "Sources exceed the 512 MiB aggregate import limit."); return {}; }
        total_bytes += size;
        fingerprints[path] = decoded["sha256"];
        return decoded["text"];
    };
    auto validated = [&](const Dictionary &result, const String &property) {
        if (bool(result["ok"])) return true;
        const Array errors = result["diagnostics"];
        for (int i = 0; i < errors.size(); ++i) {
            const Dictionary item = errors[i];
            error(property + String(":") + String(item["path"]), item["message"]);
        }
        return false;
    };
    Ref<CubismModelResource> resource;
    if (exists(source_path, "source_path", false)) {
        const String source = json(source_path, "source_path");
        const Dictionary parsed = parse_cubism_import_manifest(source, source_path, options);
        if (ok && validated(parsed, "source_path")) {
            const Dictionary manifest = parsed["manifest"];
            const Dictionary files = manifest["FileReferences"];
            const String moc_path = files["Moc"];
            PackedStringArray dependencies = parsed["dependencies"];
            resource.instantiate();
            resource->set_source_model_path(source_path);
            resource->set_source_hash(fingerprints[source_path]);
            resource->set_moc_path(moc_path);
            resource->set_layout(manifest.get("Layout", Dictionary()));
            resource->set_metadata(manifest);
            resource->set_sdk_compatibility(CubismBuildInfo::get_versions());
            resource->set_import_options(options);
            // Validate every physical reference before ResourceLoader sees any asset.
            for (int i = 0; i < dependencies.size(); ++i) {
                const Dictionary status = CubismManifestParser::validate_project_file(dependencies[i]);
                if (status["status"] != String("file") && status["status"] != String("missing")) error(dependencies[i], status["message"]);
            }
            Inspection inspection;
            if (ok && exists(moc_path, "FileReferences.Moc", false)) {
                const PackedByteArray bytes = read(moc_path, "FileReferences.Moc");
                if (ok && bytes.size() < 64) error("FileReferences.Moc", "MOC3 source is truncated.");
                if (ok) {
                    const auto version = Csm::CubismMoc::GetMocVersionFromBuffer(bytes.ptr(), bytes.size());
                    if (version == Core::csmMocVersion_Unknown || version > Core::csmGetLatestMocVersion()) error("FileReferences.Moc", "Unsupported MOC3 version.");
                    else {
                        inspection.moc = Csm::CubismMoc::Create(bytes.ptr(), bytes.size(), true);
                        if (inspection.moc) inspection.model = inspection.moc->CreateModel();
                        if (!inspection.model) error("FileReferences.Moc", "MOC3 consistency or model creation failed.");
                        else resource->set_moc_version(version);
                    }
                }
            }
            const Array texture_paths = files["Textures"];
            if (inspection.model) {
                Core::csmVector2 size, origin; float scale = 0;
                Core::csmReadCanvasInfo(inspection.model->GetModel(), &size, &origin, &scale);
                if (!std::isfinite(size.X) || !std::isfinite(size.Y) || !std::isfinite(origin.X) || !std::isfinite(origin.Y) || !std::isfinite(scale) || scale <= 0) error("FileReferences.Moc", "Invalid canvas dimensions or scale.");
                resource->set_canvas_size(Vector2(size.X, size.Y));
                resource->set_canvas_origin(Vector2(origin.X, origin.Y));
                resource->set_pixels_per_unit(scale);
                if (inspection.model->GetOffscreenCount()) error("FileReferences.Moc", "Offscreen compositing is unsupported.");
                for (int i = 0; i < inspection.model->GetDrawableCount(); ++i) {
                    const int index = inspection.model->GetDrawableTextureIndex(i);
                    if (index < 0 || index >= texture_paths.size()) error("FileReferences.Textures", "MOC drawable references an unavailable texture index.");
                    const auto blend = inspection.model->GetDrawableBlendModeType(i);
                    const auto color = blend.GetColorBlendType();
                    if (blend.GetAlphaBlendType() != Core::csmAlphaBlendType_Over || (color != Core::csmColorBlendType_Normal && color != Core::csmColorBlendType_AddCompatible && color != Core::csmColorBlendType_MultiplyCompatible)) error("FileReferences.Moc", "Unsupported drawable blend mode.");
                }
            }
            for (const String key : {String("Physics"), String("Pose"), String("UserData"), String("DisplayInfo")}) {
                if (!ok || !files.has(key)) continue;
                const String path = files[key];
                if (!exists(path, "FileReferences." + key, true)) continue;
                const String text = json(path, "FileReferences." + key);
                const Dictionary result = key == "Physics" ? CubismManifestParser::parse_physics(text) : key == "Pose" ? CubismManifestParser::parse_pose(text) : key == "UserData" ? CubismManifestParser::parse_user_data(text) : CubismManifestParser::parse_display_info(text);
                if (!validated(result, "FileReferences." + key)) continue;
                if (key == "Physics") resource->set_physics_path(path);
                else if (key == "Pose") resource->set_pose_path(path);
                else if (key == "UserData") resource->set_user_data_path(path);
                else resource->set_display_info_path(path);
            }
            Array expressions;
            const Array expression_entries = files.get("Expressions", Array());
            for (int i = 0; ok && i < expression_entries.size(); ++i) {
                const Dictionary entry = expression_entries[i];
                const String path = entry["File"];
                const String property = "FileReferences.Expressions[" + String::num_int64(i) + String("]");
                if (!exists(path, property, true)) continue;
                const Dictionary result = CubismManifestParser::parse_expression(json(path, property), entry["Name"], path);
                if (validated(result, property)) expressions.append(result["expression"]);
            }
            resource->set_expressions(expressions);
            Dictionary motion_groups;
            const Dictionary motions = files.get("Motions", Dictionary());
            const Array groups = motions.keys();
            for (int i = 0; ok && i < groups.size(); ++i) {
                const String group = groups[i];
                const Array entries = motions[group];
                Array descriptors;
                for (int j = 0; ok && j < entries.size(); ++j) {
                    const Dictionary entry = entries[j];
                    const String path = entry["File"];
                    const String property = "FileReferences.Motions." + group + String("[") + String::num_int64(j) + String("]");
                    if (!exists(path, property, false)) continue;
                    const Dictionary result = CubismManifestParser::parse_motion(json(path, property), group, j, path);
                    if (!validated(result, property)) continue;
                    Ref<CubismMotionDescriptor> motion = result["motion"];
                    if (entry.has("FadeInTime") && double(entry["FadeInTime"]) >= 0) motion->set_fade_in_seconds(entry["FadeInTime"]);
                    if (entry.has("FadeOutTime") && double(entry["FadeOutTime"]) >= 0) motion->set_fade_out_seconds(entry["FadeOutTime"]);
                    const String sound_path = entry.get("Sound", String());
                    if (!sound_path.is_empty() && exists(sound_path, property + String(".Sound"), true)) {
                        read(sound_path, property + String(".Sound"));
                        if (ok) {
                            Ref<AudioStream> sound = ResourceLoader::get_singleton()->load(sound_path, "AudioStream");
                            if (sound.is_null()) error(property + String(".Sound"), "Expected an imported audio stream.");
                            else { motion->set_sound_path(sound_path); motion->set_sound(sound); }
                        }
                    }
                    descriptors.append(motion);
                }
                motion_groups[group] = descriptors;
            }
            resource->set_motion_groups(motion_groups);
            TypedArray<Texture2D> textures;
            PackedStringArray paths;
            for (int i = 0; ok && i < texture_paths.size(); ++i) {
                const String path = texture_paths[i];
                if (!exists(path, "FileReferences.Textures", false)) break;
                const PackedByteArray bytes = read(path, "FileReferences.Textures");
                if (!ok) break;
                const uint8_t signature[] = {137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82};
                bool png = bytes.size() >= 33;
                for (int j = 0; png && j < 16; ++j) png = bytes[j] == signature[j];
                if (!png) { error("FileReferences.Textures", "Expected a PNG source with an IHDR header."); break; }
                auto dimension = [&](int offset) -> uint64_t {
                    return (uint64_t(bytes[offset]) << 24) | (uint64_t(bytes[offset + 1]) << 16) | (uint64_t(bytes[offset + 2]) << 8) | bytes[offset + 3];
                };
                const uint64_t width = dimension(16), height = dimension(20);
                if (!width || !height || width > 16384 || height > 16384 || width * height > 64 * 1024 * 1024 || texture_pixels + width * height > 128 * 1024 * 1024) {
                    error("FileReferences.Textures", "PNG dimensions exceed the per-texture or aggregate pixel limit."); break;
                }
                texture_pixels += width * height;
                Ref<Texture2D> texture = ResourceLoader::get_singleton()->load(path, "Texture2D");
                if (texture.is_null()) error("FileReferences.Textures", "Expected an imported texture.");
                else { textures.append(texture); paths.append(path); }
            }
            resource->set_textures(textures);
            resource->set_texture_paths(paths);
            resource->set_hit_areas(manifest.get("HitAreas", Array()));
            const Array parameter_groups = manifest.get("Groups", Array());
            for (int i = 0; i < parameter_groups.size(); ++i) {
                const Dictionary group = parameter_groups[i];
                if (group["Target"] != String("Parameter")) continue;
                if (group["Name"] == String("EyeBlink")) resource->set_eye_blink_parameter_ids(group["Ids"]);
                if (group["Name"] == String("LipSync")) resource->set_lip_sync_parameter_ids(group["Ids"]);
            }
            resource->set_dependency_paths(dependencies);
            resource->set_dependency_fingerprints(fingerprints);
            resource->set_import_warnings(warnings);
        }
    }
    Dictionary result;
    result["ok"] = ok;
    result["diagnostics"] = diagnostics;
    result["warnings"] = warnings;
    result["model"] = ok ? resource : Ref<CubismModelResource>();
    return result;
}
