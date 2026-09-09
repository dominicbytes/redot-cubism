// SPDX-License-Identifier: MIT
#include "cubism_manifest_parser.hpp"
#include "cubism_descriptors.hpp"
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <cmath>
#include <filesystem>

using namespace godot;

namespace {
constexpr int MAX_JSON_BYTES = 4 * 1024 * 1024;
constexpr int MAX_STRING = 4096;
constexpr int MAX_NODES = 65536;
constexpr int MAX_REFERENCES = 4096;
constexpr int MAX_DIAGNOSTICS = 32;

struct Validation {
    Array diagnostics;
    PackedStringArray dependencies;
    String base;
    bool ok = true;
    int nodes = 0;
    int references = 0;

    void error(const String &path, const String &message) {
        ok = false;
        if (diagnostics.size() >= MAX_DIAGNOSTICS) return;
        Dictionary item;
        item["path"] = path;
        item["message"] = message;
        diagnostics.append(item);
    }

    bool bounded(const Variant &value, const String &path, int depth = 0) {
        if (++nodes > MAX_NODES || depth > 32) {
            error(path, "Manifest exceeds the node or nesting limit.");
            return false;
        }
        if (value.get_type() == Variant::STRING) {
            const String text = value;
            if (text.length() > MAX_STRING) {
                error(path, "String exceeds 4096 characters.");
                return false;
            }
        } else if (value.get_type() == Variant::FLOAT && !std::isfinite(static_cast<double>(value))) {
            error(path, "Numbers must be finite.");
            return false;
        } else if (value.get_type() == Variant::ARRAY) {
            const Array array = value;
            for (int i = 0; i < array.size(); ++i) {
                if (!bounded(array[i], path + String("[") + String::num_int64(i) + String("]"), depth + 1)) return false;
            }
        } else if (value.get_type() == Variant::DICTIONARY) {
            const Dictionary dict = value;
            const Array keys = dict.keys();
            for (int i = 0; i < keys.size(); ++i) {
                const String key = keys[i];
                if (!bounded(key, path, depth + 1) || !bounded(dict[key], path + String(".") + key, depth + 1)) return false;
            }
        }
        return true;
    }

    Dictionary object(const String &json) {
        Dictionary manifest;
        if (json.utf8().length() > MAX_JSON_BYTES) {
            error("$", "Manifest exceeds 4 MiB of UTF-8 JSON.");
        } else {
            // Redot replaces decoded NUL with U+FFFD. Reject it before decoding so
            // an invalid reference cannot silently become a different filename.
            for (int i = 0; i < json.length(); ++i) {
                if (json[i] == 0) error("$", "NUL characters are forbidden.");
                if (json[i] == '\\' && i + 1 < json.length()) {
                    if (json.substr(i + 1, 5) == "u0000") error("$", "NUL escapes are forbidden.");
                    ++i;
                }
            }
            Ref<JSON> parser;
            parser.instantiate();
            if (!ok) {
                // Do not invoke the decoder on input known to lose information.
            } else if (parser->parse(json) != OK || parser->get_data().get_type() != Variant::DICTIONARY) {
                error("$", "Expected a JSON object: " + parser->get_error_message());
            } else {
                // Select releasing copy assignment in the pinned redot-cpp binding.
                const Dictionary parsed = parser->get_data();
                manifest = parsed;
                bounded(manifest, "$");
            }
        }
        return manifest;
    }

    bool type(const Dictionary &dict, const String &key, Variant::Type expected, const String &path) {
        if (!dict.has(key) || dict[key].get_type() != expected) {
            error(path, "Missing field or incorrect JSON type.");
            return false;
        }
        return true;
    }

    String resolve(const String &raw, const String &path) {
        String value = raw.replace("\\", "/");
        if (value.is_empty() || value.length() > MAX_STRING || value.begins_with("/") || value.contains(":")) {
            error(path, "Expected a nonempty relative project path without a scheme or drive.");
            return String();
        }
        for (int i = 0; i < value.length(); ++i) {
            if (value[i] < 32 || value[i] == 127) {
                error(path, "Control characters are forbidden in paths.");
                return String();
            }
        }
        PackedStringArray segments = base.split("/", false);
        const PackedStringArray relative = value.split("/", false);
        for (int i = 0; i < relative.size(); ++i) {
            if (relative[i] == ".") continue;
            if (relative[i] == "..") {
                if (segments.is_empty()) {
                    error(path, "Reference escapes the project root.");
                    return String();
                }
                segments.remove_at(segments.size() - 1);
            } else {
                segments.append(relative[i]);
            }
        }
        const String resolved = "res://" + String("/").join(segments);
        if (resolved.length() > MAX_STRING) {
            error(path, "Resolved path exceeds 4096 characters.");
            return String();
        }
        return resolved;
    }

    String reference(const Variant &value, const String &path, const String &suffix, const String &alternate = String()) {
        if (++references > MAX_REFERENCES) {
            error(path, "Manifest exceeds 4096 file references.");
            return String();
        }
        if (value.get_type() != Variant::STRING) {
            error(path, "File reference must be a string.");
            return String();
        }
        const String resolved = resolve(value, path);
        if (resolved.is_empty()) return resolved;
        if (!resolved.ends_with(suffix) && (alternate.is_empty() || !resolved.ends_with(alternate))) {
            error(path, "Unsupported source file suffix; expected " + suffix + (alternate.is_empty() ? String() : " or " + alternate) + String("."));
            return String();
        }
        if (!dependencies.has(resolved)) dependencies.append(resolved);
        return resolved;
    }

    void optional_reference(Dictionary &files, const String &key, const String &suffix) {
        if (files.has(key)) files[key] = reference(files[key], "FileReferences." + key, suffix);
    }

    void numeric(const Dictionary &dict, const String &key, const String &path) {
        if (!dict.has(key)) return;
        const Variant value = dict[key];
        if ((value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) ||
                !std::isfinite(static_cast<double>(value)) || std::abs(static_cast<double>(value)) > 3.402823466e38) {
            error(path, "Expected a finite Framework float.");
        }
    }
};
}

void CubismManifestParser::_bind_methods() {
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("parse_physics", "json"), &CubismManifestParser::parse_physics);
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("parse_pose", "json"), &CubismManifestParser::parse_pose);
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("read_project_json", "path"), &CubismManifestParser::read_project_json);
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("parse_motion", "json", "group", "index", "source_path"), &CubismManifestParser::parse_motion);
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("parse_manifest", "json", "source_path"), &CubismManifestParser::parse_manifest);
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("validate_project_file", "path"), &CubismManifestParser::validate_project_file);
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("parse_expression", "json", "expression_id", "source_path"), &CubismManifestParser::parse_expression);
}

Dictionary CubismManifestParser::parse_expression(const String &json, const String &expression_id, const String &source_path) {
    Validation v;
    const Dictionary data = v.object(json);
    String normalized;
    if (!source_path.begins_with("res://") || !source_path.ends_with(".exp3.json")) {
        v.error("source_path", "Expected a res:// path ending in .exp3.json.");
    } else {
        normalized = v.resolve(source_path.substr(6), "source_path");
    }
    if (expression_id.is_empty() || expression_id.length() > MAX_STRING) v.error("expression_id", "Expected a nonempty bounded expression ID.");
    for (int i = 0; i < expression_id.length(); ++i) {
        if (expression_id[i] == 0) v.error("expression_id", "NUL characters are forbidden in IDs.");
    }
    Ref<CubismExpressionDescriptor> expression;
    TypedArray<CubismExpressionParameter> parameters;
    if (v.ok) {
        if (data.has("Type") && (data["Type"].get_type() != Variant::STRING || String(data["Type"]) != "Live2D Expression")) {
            v.error("Type", "Expected Live2D Expression when Type is present.");
        }
        v.numeric(data, "FadeInTime", "FadeInTime");
        v.numeric(data, "FadeOutTime", "FadeOutTime");
        if (v.type(data, "Parameters", Variant::ARRAY, "Parameters")) {
            const Array entries = data["Parameters"];
            if (entries.size() > 4096) v.error("Parameters", "At most 4096 expression parameters are supported.");
            else for (int i = 0; i < entries.size(); ++i) {
                const String path = "Parameters[" + String::num_int64(i) + String("]");
                if (entries[i].get_type() != Variant::DICTIONARY) { v.error(path, "Expected a parameter object."); continue; }
                const Dictionary entry = entries[i];
                if (!v.type(entry, "Id", Variant::STRING, path + String(".Id"))) continue;
                if (String(entry["Id"]).is_empty()) v.error(path + String(".Id"), "Parameter ID must be nonempty.");
                if (!entry.has("Value")) v.error(path + String(".Value"), "Parameter value is required.");
                else v.numeric(entry, "Value", path + String(".Value"));
                auto operation = CubismExpressionParameter::ADD;
                if (entry.has("Blend") && entry["Blend"].get_type() != Variant::NIL) {
                    if (entry["Blend"].get_type() != Variant::STRING) v.error(path + String(".Blend"), "Expected a blend name.");
                    else {
                        const String blend = entry["Blend"];
                        if (blend == "Multiply") operation = CubismExpressionParameter::MULTIPLY;
                        else if (blend == "Overwrite") operation = CubismExpressionParameter::OVERWRITE;
                        else if (blend != "Add") v.error(path + String(".Blend"), "Unsupported expression blend operation.");
                    }
                }
                if (!v.ok) continue;
                Ref<CubismExpressionParameter> parameter;
                parameter.instantiate();
                parameter->set_id(entry["Id"]);
                parameter->set_value(entry["Value"]);
                parameter->set_operation(operation);
                parameters.append(parameter);
            }
        }
    }
    if (v.ok) {
        expression.instantiate();
        expression->set_id(expression_id);
        expression->set_source_path(normalized);
        // Pinned Framework R5's DefaultFadeTime is 1 second.
        expression->set_fade_in_seconds(data.get("FadeInTime", 1.0));
        expression->set_fade_out_seconds(data.get("FadeOutTime", 1.0));
        expression->set_parameters(parameters);
    }
    Dictionary result;
    result["ok"] = v.ok;
    result["diagnostics"] = v.diagnostics;
    result["expression"] = expression;
    result["source_data"] = v.ok ? data : Dictionary();
    return result;
}

Dictionary CubismManifestParser::validate_project_file(const String &path) {
    Dictionary result;
    result["status"] = "unsafe";
    result["path"] = path;
    result["message"] = "Expected a normalized res:// file path.";
    if (!path.begins_with("res://") || path.length() > MAX_STRING) return result;
    const String relative = path.substr(6);
    if (relative.is_empty() || relative.begins_with("/") || relative.contains(":") || relative.contains("\\")) return result;
    for (int i = 0; i < relative.length(); ++i) {
        if (relative[i] < 32 || relative[i] == 127) return result;
    }
    const PackedStringArray parts = relative.split("/", true);
    for (int i = 0; i < parts.size(); ++i) {
        if (parts[i].is_empty() || parts[i] == "." || parts[i] == "..") return result;
    }

    namespace fs = std::filesystem;
    std::error_code ec;
    const CharString root_utf8 = ProjectSettings::get_singleton()->globalize_path("res://").utf8();
    const fs::path root = fs::canonical(fs::u8path(root_utf8.get_data()), ec);
    if (ec) {
        result["status"] = "error";
        result["message"] = "Cannot resolve the physical project root.";
        return result;
    }
    fs::path candidate = root;
    for (int i = 0; i < parts.size(); ++i) {
        const CharString component = parts[i].utf8();
        candidate /= fs::u8path(component.get_data());
        const fs::file_status link_status = fs::symlink_status(candidate, ec);
        if (ec && ec != std::errc::no_such_file_or_directory) {
            result["status"] = "error";
            result["message"] = "Cannot inspect a path component.";
            return result;
        }
        ec.clear();
        // weakly_canonical alone can leave a dangling symlink unresolved.
        // Do not classify it as an ordinary, safely contained missing file.
        if (fs::is_symlink(link_status) && !fs::exists(candidate, ec)) {
            result["status"] = "error";
            result["message"] = "A symlink target is missing or cannot be resolved.";
            return result;
        }
        if (ec) {
            result["status"] = "error";
            result["message"] = "Cannot resolve a symlink target.";
            return result;
        }
    }
    const fs::path physical = fs::weakly_canonical(candidate, ec);
    if (ec) {
        result["status"] = "error";
        result["message"] = "Cannot resolve the physical file path.";
        return result;
    }
    auto child = physical.begin();
    for (auto parent = root.begin(); parent != root.end(); ++parent, ++child) {
        if (child == physical.end() || *child != *parent) {
            result["message"] = "Physical path escapes the project root.";
            return result;
        }
    }
    const fs::file_status status = fs::status(physical, ec);
    if (ec && ec != std::errc::no_such_file_or_directory) {
        result["status"] = "error";
        result["message"] = "Cannot inspect the resolved file.";
    } else if (!fs::exists(status)) {
        result["status"] = "missing";
        result["message"] = "The project file does not exist.";
    } else if (!fs::is_regular_file(status)) {
        result["status"] = "error";
        result["message"] = "The reference is not a regular file.";
    } else {
        result["status"] = "file";
        result["message"] = String();
    }
    return result;
}

Dictionary CubismManifestParser::parse_manifest(const String &json, const String &source_path) {
    Validation v;
    Dictionary manifest = v.object(json);
    if (!source_path.begins_with("res://") || !source_path.ends_with(".model3.json")) {
        v.error("source_path", "Expected a res:// path ending in .model3.json.");
    } else {
        const String normalized = v.resolve(source_path.substr(6), "source_path");
        if (!normalized.is_empty()) v.base = normalized.substr(6).get_base_dir();
    }
    if (v.ok) {
        const Variant version = manifest.get("Version", Variant());
        if ((version.get_type() != Variant::INT && version.get_type() != Variant::FLOAT) || static_cast<double>(version) != 3.0) {
            v.error("Version", "Only model settings version 3 is supported.");
        }
        if (v.type(manifest, "FileReferences", Variant::DICTIONARY, "FileReferences")) {
            Dictionary files = manifest["FileReferences"];
            files["Moc"] = v.reference(files.get("Moc", Variant()), "FileReferences.Moc", ".moc3");
            if (v.type(files, "Textures", Variant::ARRAY, "FileReferences.Textures")) {
                Array textures = files["Textures"];
                if (textures.size() > 64) v.error("FileReferences.Textures", "At most 64 textures are supported.");
                else for (int i = 0; i < textures.size(); ++i) textures[i] = v.reference(textures[i], "FileReferences.Textures[" + String::num_int64(i) + String("]"), ".png");
            }
            v.optional_reference(files, "Physics", ".physics3.json");
            v.optional_reference(files, "Pose", ".pose3.json");
            v.optional_reference(files, "DisplayInfo", ".cdi3.json");
            v.optional_reference(files, "UserData", ".userdata3.json");
            if (files.has("Expressions") && v.type(files, "Expressions", Variant::ARRAY, "FileReferences.Expressions")) {
                Array expressions = files["Expressions"];
                Dictionary names;
                if (expressions.size() > 512) v.error("FileReferences.Expressions", "At most 512 expressions are supported.");
                else for (int i = 0; i < expressions.size(); ++i) {
                    const String path = "FileReferences.Expressions[" + String::num_int64(i) + String("]");
                    if (expressions[i].get_type() != Variant::DICTIONARY) { v.error(path, "Expected an expression object."); continue; }
                    Dictionary expression = expressions[i];
                    if (v.type(expression, "Name", Variant::STRING, path + String(".Name"))) {
                        const String name = expression["Name"];
                        if (name.is_empty() || names.has(name)) v.error(path + String(".Name"), "Expression name must be nonempty and unique.");
                        names[name] = true;
                    }
                    expression["File"] = v.reference(expression.get("File", Variant()), path + String(".File"), ".exp3.json");
                }
            }
            if (files.has("Motions") && v.type(files, "Motions", Variant::DICTIONARY, "FileReferences.Motions")) {
                Dictionary motions = files["Motions"];
                Array groups = motions.keys();
                groups.sort();
                if (groups.size() > 64) v.error("FileReferences.Motions", "At most 64 motion groups are supported.");
                else for (int i = 0; i < groups.size(); ++i) {
                    const String group = groups[i];
                    const String path = "FileReferences.Motions." + group;
                    if (group.is_empty()) v.error(path, "Motion group name must be nonempty.");
                    if (!v.type(motions, group, Variant::ARRAY, path)) continue;
                    const Array entries = motions[group];
                    if (entries.size() > 512) { v.error(path, "At most 512 motions per group are supported."); continue; }
                    for (int j = 0; j < entries.size(); ++j) {
                        const String item_path = path + String("[") + String::num_int64(j) + String("]");
                        if (entries[j].get_type() != Variant::DICTIONARY) { v.error(item_path, "Expected a motion object."); continue; }
                        Dictionary motion = entries[j];
                        motion["File"] = v.reference(motion.get("File", Variant()), item_path + String(".File"), ".motion3.json");
                        if (motion.has("Sound") && motion["Sound"] != String()) motion["Sound"] = v.reference(motion["Sound"], item_path + String(".Sound"), ".wav", ".ogg");
                        v.numeric(motion, "FadeInTime", item_path + String(".FadeInTime"));
                        v.numeric(motion, "FadeOutTime", item_path + String(".FadeOutTime"));
                    }
                }
            }
        }
        if (manifest.has("Layout") && v.type(manifest, "Layout", Variant::DICTIONARY, "Layout")) {
            const Dictionary layout = manifest["Layout"];
            const Array keys = layout.keys();
            for (int i = 0; i < keys.size(); ++i) v.numeric(layout, keys[i], "Layout." + String(keys[i]));
        }
        for (const String field : {String("Groups"), String("HitAreas")}) {
            if (!manifest.has(field) || !v.type(manifest, field, Variant::ARRAY, field)) continue;
            const Array entries = manifest[field];
            Dictionary identifiers;
            for (int i = 0; i < entries.size(); ++i) {
                const String path = field + String("[") + String::num_int64(i) + String("]");
                if (entries[i].get_type() != Variant::DICTIONARY) { v.error(path, "Expected an object."); continue; }
                const Dictionary entry = entries[i];
                const String identity_key = field == "Groups" ? "Name" : "Id";
                if (v.type(entry, identity_key, Variant::STRING, path + String(".") + identity_key)) {
                    const String id = entry[identity_key];
                    if (id.is_empty() || identifiers.has(id)) v.error(path + String(".") + identity_key, "Identifier must be nonempty and unique.");
                    identifiers[id] = true;
                }
                if (field == "HitAreas") {
                    v.type(entry, "Name", Variant::STRING, path + String(".Name"));
                } else {
                    v.type(entry, "Target", Variant::STRING, path + String(".Target"));
                    if (v.type(entry, "Ids", Variant::ARRAY, path + String(".Ids"))) {
                        const Array ids = entry["Ids"];
                        for (int j = 0; j < ids.size(); ++j) {
                            if (ids[j].get_type() != Variant::STRING || String(ids[j]).is_empty()) {
                                v.error(path + String(".Ids[") + String::num_int64(j) + String("]"), "Expected a nonempty ID string.");
                            }
                        }
                    }
                }
            }
        }
    }
    v.dependencies.sort();
    Dictionary result;
    result["ok"] = v.ok;
    result["diagnostics"] = v.diagnostics;
    result["dependencies"] = v.dependencies;
    // Never offer a partially normalized manifest as usable input.
    result["manifest"] = v.ok ? manifest : Dictionary();
    return result;
}

Dictionary CubismManifestParser::parse_motion(const String &json, const String &group, int index, const String &source_path) {
    Validation v;
    const Dictionary data = v.object(json);
    String normalized;
    if (!source_path.begins_with("res://") || !source_path.ends_with(".motion3.json")) v.error("source_path", "Expected a res:// motion3.json path.");
    else normalized = v.resolve(source_path.substr(6), "source_path");
    if (group.is_empty() || group.length() > MAX_STRING || index < 0) v.error("identity", "Expected a nonempty bounded group and nonnegative index.");
    for (int i = 0; i < group.length(); ++i) if (group[i] == 0) v.error("identity", "NUL characters are forbidden.");
    Ref<CubismMotionDescriptor> motion;
    TypedArray<CubismMotionEvent> events;
    if (v.ok) {
        const Variant version = data.get("Version", Variant());
        if ((version.get_type() != Variant::INT && version.get_type() != Variant::FLOAT) || double(version) != 3.0) v.error("Version", "Expected motion version 3.");
        if (v.type(data, "Meta", Variant::DICTIONARY, "Meta") && v.type(data, "Curves", Variant::ARRAY, "Curves")) {
            const Dictionary meta = data["Meta"];
            const Array curves = data["Curves"];
            auto number = [&](const Dictionary &object, const String &key, const String &path) {
                if (!object.has(key)) v.error(path, "Required number is missing.");
                v.numeric(object, key, path);
            };
            auto value_or_zero = [](const Dictionary &object, const String &key) -> double {
                const Variant value = object.get(key, Variant());
                return value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT ? double(value) : 0.0;
            };
            auto count = [&](const String &key, int actual, bool optional = false) {
                const String path = "Meta." + key;
                if (optional && !meta.has(key) && actual == 0) return;
                number(meta, key, path);
                const Variant declared = meta.get(key, Variant());
                if ((declared.get_type() == Variant::INT || declared.get_type() == Variant::FLOAT) && double(declared) != actual) v.error(path, "Declared count does not match decoded data.");
            };
            number(meta, "Duration", "Meta.Duration");
            number(meta, "Fps", "Meta.Fps");
            if (float(value_or_zero(meta, "Duration")) <= 0.0) v.error("Meta.Duration", "Duration must be positive.");
            if (float(value_or_zero(meta, "Fps")) <= 0.0) v.error("Meta.Fps", "Frame rate must be positive.");
            v.type(meta, "Loop", Variant::BOOL, "Meta.Loop");
            if (meta.has("AreBeziersRestricted")) v.type(meta, "AreBeziersRestricted", Variant::BOOL, "Meta.AreBeziersRestricted");
            for (const String key : {String("FadeInTime"), String("FadeOutTime")}) v.numeric(meta, key, "Meta." + key);
            int segments = 0;
            int points = 0;
            int previous_target = 0;
            for (int i = 0; i < curves.size(); ++i) {
                const String path = "Curves[" + String::num_int64(i) + String("]");
                if (curves[i].get_type() != Variant::DICTIONARY) { v.error(path, "Expected a curve object."); continue; }
                const Dictionary curve = curves[i];
                if (v.type(curve, "Target", Variant::STRING, path + String(".Target"))) {
                    const String target = curve["Target"];
                    const int target_order = target == "Model" ? 0 : target == "Parameter" ? 1 : 2;
                    if (target_order < previous_target) v.error(path + String(".Target"), "SDK playback requires Model, Parameter, then PartOpacity curves.");
                    previous_target = target_order;
                    if (target != "Model" && target != "Parameter" && target != "PartOpacity") v.error(path + String(".Target"), "Unsupported curve target.");
                }
                if (v.type(curve, "Id", Variant::STRING, path + String(".Id")) && String(curve["Id"]).is_empty()) v.error(path + String(".Id"), "Expected a nonempty curve ID.");
                for (const String key : {String("FadeInTime"), String("FadeOutTime")}) v.numeric(curve, key, path + String(".") + key);
                if (!v.type(curve, "Segments", Variant::ARRAY, path + String(".Segments"))) continue;
                const Array values = curve["Segments"];
                bool numeric_values = true;
                for (int j = 0; j < values.size(); ++j) {
                    const Variant value = values[j];
                    if ((value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) || !std::isfinite(double(value)) || std::abs(double(value)) > 3.402823466e38) numeric_values = false;
                }
                if (!numeric_values || values.size() < 5) { v.error(path + String(".Segments"), "Expected finite points and at least one complete segment."); continue; }
                ++points;
                float previous_time = double(values[0]);
                if (previous_time < 0) v.error(path + String(".Segments"), "Curve time must be nonnegative.");
                for (int j = 2; j < values.size();) {
                    const double kind = values[j];
                    if (kind != 0 && kind != 1 && kind != 2 && kind != 3) { v.error(path + String(".Segments"), "Unknown segment type."); break; }
                    const int width = kind == 1 ? 7 : 3;
                    if (j + width > values.size()) { v.error(path + String(".Segments"), "Truncated segment."); break; }
                    const float end_time = double(values[j + width - 2]);
                    if (end_time <= previous_time) v.error(path + String(".Segments"), "Segment endpoint times must increase at Framework float precision.");
                    previous_time = end_time;
                    ++segments;
                    points += kind == 1 ? 3 : 1;
                    j += width;
                }
            }
            count("CurveCount", curves.size());
            count("TotalSegmentCount", segments);
            count("TotalPointCount", points);
            if (data.has("UserData") && v.type(data, "UserData", Variant::ARRAY, "UserData")) {
                const Array entries = data["UserData"];
                for (int i = 0; i < entries.size(); ++i) {
                    const String path = "UserData[" + String::num_int64(i) + String("]");
                    if (entries[i].get_type() != Variant::DICTIONARY) { v.error(path, "Expected an event object."); continue; }
                    const Dictionary entry = entries[i];
                    number(entry, "Time", path + String(".Time"));
                    if (!v.type(entry, "Value", Variant::STRING, path + String(".Value"))) continue;
                    const double time = value_or_zero(entry, "Time");
                    if (time < 0 || time > value_or_zero(meta, "Duration")) v.error(path + String(".Time"), "Event must lie within the motion duration.");
                    Ref<CubismMotionEvent> event;
                    event.instantiate();
                    event->set_time_seconds(time);
                    event->set_value(entry["Value"]);
                    events.append(event);
                }
            }
            count("UserDataCount", events.size(), true);
            // TotalUserDataSize is not consumed by the pinned motion parser.
            // Preserve it as metadata; do not guess whether it counts bytes or characters.
            if (meta.has("TotalUserDataSize")) v.numeric(meta, "TotalUserDataSize", "Meta.TotalUserDataSize");
            if (v.ok) {
                motion.instantiate();
                motion->set_id(group + String("/") + String::num_int64(index));
                motion->set_group(group);
                motion->set_index(index);
                motion->set_source_path(normalized);
                motion->set_duration_seconds(meta["Duration"]);
                motion->set_loop(meta["Loop"]);
                const double fade_in = meta.get("FadeInTime", 1.0);
                const double fade_out = meta.get("FadeOutTime", 1.0);
                motion->set_fade_in_seconds(fade_in < 0 ? 1.0 : fade_in);
                motion->set_fade_out_seconds(fade_out < 0 ? 1.0 : fade_out);
                motion->set_events(events);
                motion->set_metadata(data);
            }
        }
    }
    Dictionary result;
    result["ok"] = v.ok;
    result["diagnostics"] = v.diagnostics;
    result["motion"] = motion;
    return result;
}

Dictionary CubismManifestParser::read_project_json(const String &path) {
    Dictionary result = validate_project_file(path);
    result["ok"] = false;
    result["text"] = String();
    if (result["status"] != String("file")) return result;
    result["status"] = "error";
    // Use the physical path rather than resource remapping or a script-bearing
    // ResourceLoader. Containment remains a snapshot, not an atomic open policy.
    const Ref<FileAccess> file = FileAccess::open(ProjectSettings::get_singleton()->globalize_path(path), FileAccess::READ);
    if (file.is_null()) {
        result["message"] = "Cannot open the project JSON file.";
        return result;
    }
    const uint64_t length = file->get_length();
    if (length > MAX_JSON_BYTES) {
        result["message"] = "JSON source exceeds 4 MiB.";
        return result;
    }
    const PackedByteArray bytes = file->get_buffer(length);
    if (uint64_t(bytes.size()) != length || file->get_length() != length) {
        result["message"] = "JSON source changed length or could not be read completely.";
        return result;
    }
    // Reject malformed UTF-8 before Redot's decoder can replace invalid bytes
    // or print decoding errors. This also rejects embedded NUL without truncation.
    bool valid = true;
    for (int64_t i = 0; i < bytes.size() && valid;) {
        const uint8_t first = bytes[i++];
        if (first == 0) { valid = false; break; }
        if (first < 0x80) continue;
        int continuation = 0;
        uint32_t point = 0;
        uint32_t minimum = 0;
        if (first >= 0xc2 && first <= 0xdf) { continuation = 1; point = first & 0x1f; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { continuation = 2; point = first & 0x0f; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { continuation = 3; point = first & 0x07; minimum = 0x10000; }
        else { valid = false; break; }
        if (i + continuation > bytes.size()) { valid = false; break; }
        for (int j = 0; j < continuation; ++j) {
            const uint8_t next = bytes[i++];
            if ((next & 0xc0) != 0x80) { valid = false; break; }
            point = (point << 6) | (next & 0x3f);
        }
        if (point < minimum || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)) valid = false;
    }
    if (!valid) {
        result["message"] = "JSON source must be valid UTF-8 without embedded NUL.";
        return result;
    }
    // Redot removes exactly one initial UTF-8 BOM during decoding.
    String text;
    if (!bytes.is_empty() && text.parse_utf8(reinterpret_cast<const char *>(bytes.ptr()), bytes.size()) != OK) {
        result["message"] = "Cannot decode JSON source as UTF-8.";
        return result;
    }
    result["ok"] = true;
    result["status"] = "file";
    result["message"] = String();
    result["text"] = text;
    return result;
}

Dictionary CubismManifestParser::parse_pose(const String &json) {
    Validation v;
    const Dictionary data = v.object(json);
    double fade = 0.5;
    if (v.ok) {
        if (data.has("Type") && (data["Type"].get_type() != Variant::STRING || String(data["Type"]) != "Live2D Pose")) v.error("Type", "Expected Live2D Pose when Type is present.");
        // The pinned SDK treats absent/null/negative fade as its 0.5s default.
        if (data.has("FadeInTime") && data["FadeInTime"].get_type() != Variant::NIL) {
            v.numeric(data, "FadeInTime", "FadeInTime");
            if (v.ok) {
                fade = data["FadeInTime"];
                if (fade < 0) fade = 0.5;
            }
        }
        if (v.type(data, "Groups", Variant::ARRAY, "Groups")) {
            const Array groups = data["Groups"];
            for (int i = 0; i < groups.size(); ++i) {
                const String path = "Groups[" + String::num_int64(i) + String("]");
                if (groups[i].get_type() != Variant::ARRAY) { v.error(path, "Expected an array of pose parts."); continue; }
                const Array parts = groups[i];
                for (int j = 0; j < parts.size(); ++j) {
                    const String part_path = path + String("[") + String::num_int64(j) + String("]");
                    if (parts[j].get_type() != Variant::DICTIONARY) { v.error(part_path, "Expected a pose part object."); continue; }
                    const Dictionary part = parts[j];
                    if (v.type(part, "Id", Variant::STRING, part_path + String(".Id")) && String(part["Id"]).is_empty()) v.error(part_path + String(".Id"), "Expected a nonempty part ID.");
                    if (!part.has("Link") || part["Link"].get_type() == Variant::NIL) continue;
                    if (!v.type(part, "Link", Variant::ARRAY, part_path + String(".Link"))) continue;
                    const Array links = part["Link"];
                    for (int k = 0; k < links.size(); ++k) {
                        if (links[k].get_type() != Variant::STRING || String(links[k]).is_empty()) v.error(part_path + String(".Link[") + String::num_int64(k) + String("]"), "Expected a nonempty linked part ID.");
                    }
                }
            }
        }
    }
    Dictionary result;
    result["ok"] = v.ok;
    result["diagnostics"] = v.diagnostics;
    result["pose"] = v.ok ? data : Dictionary();
    result["fade_in_seconds"] = fade;
    return result;
}

Dictionary CubismManifestParser::parse_physics(const String &json) {
    Validation v;
    const Dictionary data = v.object(json);
    auto object = [&](const Dictionary &parent, const String &key, const String &path) -> Dictionary {
        return v.type(parent, key, Variant::DICTIONARY, path) ? Dictionary(parent[key]) : Dictionary();
    };
    auto number = [&](const Dictionary &parent, const String &key, const String &path) -> double {
        if (!parent.has(key)) v.error(path, "Required number is missing.");
        v.numeric(parent, key, path);
        const Variant value = parent.get(key, Variant());
        return value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT ? double(value) : 0.0;
    };
    auto vector = [&](const Dictionary &parent, const String &key, const String &path) {
        const Dictionary coordinates = object(parent, key, path);
        number(coordinates, "X", path + String(".X"));
        number(coordinates, "Y", path + String(".Y"));
    };
    if (v.ok) {
        if (number(data, "Version", "Version") != 3) v.error("Version", "Expected physics version 3.");
        const Dictionary meta = object(data, "Meta", "Meta");
        const Dictionary forces = object(meta, "EffectiveForces", "Meta.EffectiveForces");
        vector(forces, "Gravity", "Meta.EffectiveForces.Gravity");
        vector(forces, "Wind", "Meta.EffectiveForces.Wind");
        if (meta.has("Fps")) {
            const double fps = number(meta, "Fps", "Meta.Fps");
            // Bound SDK fixed-step work; absent/zero uses the runtime delta.
            if (fps < 0 || fps > 1000) v.error("Meta.Fps", "Physics FPS must be between 0 and 1000.");
        }
        int inputs = 0, outputs = 0, particles = 0;
        Array settings;
        if (v.type(data, "PhysicsSettings", Variant::ARRAY, "PhysicsSettings")) settings = data["PhysicsSettings"];
        for (int i = 0; i < settings.size(); ++i) {
            const String path = "PhysicsSettings[" + String::num_int64(i) + String("]");
            if (settings[i].get_type() != Variant::DICTIONARY) { v.error(path, "Expected a physics setting object."); continue; }
            const Dictionary setting = settings[i];
            const Dictionary normalization = object(setting, "Normalization", path + String(".Normalization"));
            for (const String key : {String("Position"), String("Angle")}) {
                const String normal_path = path + String(".Normalization.") + key;
                const Dictionary values = object(normalization, key, normal_path);
                for (const String field : {String("Minimum"), String("Maximum"), String("Default")}) number(values, field, normal_path + String(".") + field);
            }
            Array vertices;
            if (v.type(setting, "Vertices", Variant::ARRAY, path + String(".Vertices"))) vertices = setting["Vertices"];
            if (vertices.is_empty()) v.error(path + String(".Vertices"), "A physics setting requires a root particle.");
            particles += vertices.size();
            for (int j = 0; j < vertices.size(); ++j) {
                const String vertex_path = path + String(".Vertices[") + String::num_int64(j) + String("]");
                if (vertices[j].get_type() != Variant::DICTIONARY) { v.error(vertex_path, "Expected a particle object."); continue; }
                const Dictionary vertex = vertices[j];
                for (const String key : {String("Mobility"), String("Delay"), String("Acceleration"), String("Radius")}) number(vertex, key, vertex_path + String(".") + key);
                vector(vertex, "Position", vertex_path + String(".Position"));
            }
            for (const String key : {String("Input"), String("Output")}) {
                const String io_path = path + String(".") + key;
                if (!v.type(setting, key, Variant::ARRAY, io_path)) continue;
                const Array entries = setting[key];
                // SDK forms pointers to both arrays before entering their loops.
                if (entries.is_empty()) v.error(io_path, "A physics setting requires at least one input and output.");
                if (key == "Input") inputs += entries.size(); else outputs += entries.size();
                for (int j = 0; j < entries.size(); ++j) {
                    const String entry_path = io_path + String("[") + String::num_int64(j) + String("]");
                    if (entries[j].get_type() != Variant::DICTIONARY) { v.error(entry_path, "Expected an input/output object."); continue; }
                    const Dictionary entry = entries[j];
                    number(entry, "Weight", entry_path + String(".Weight"));
                    v.type(entry, "Reflect", Variant::BOOL, entry_path + String(".Reflect"));
                    if (v.type(entry, "Type", Variant::STRING, entry_path + String(".Type"))) {
                        const String type = entry["Type"];
                        if (type != "X" && type != "Y" && type != "Angle") v.error(entry_path + String(".Type"), "Expected X, Y or Angle.");
                    }
                    const String target_key = key == "Input" ? "Source" : "Destination";
                    const String target_path = entry_path + String(".") + target_key;
                    const Dictionary target = object(entry, target_key, target_path);
                    if (v.type(target, "Id", Variant::STRING, target_path + String(".Id")) && String(target["Id"]).is_empty()) v.error(target_path + String(".Id"), "Expected a nonempty parameter ID.");
                    if (v.type(target, "Target", Variant::STRING, target_path + String(".Target")) && String(target["Target"]) != "Parameter") v.error(target_path + String(".Target"), "Only parameter targets are supported.");
                    if (key == "Output") {
                        number(entry, "Scale", entry_path + String(".Scale"));
                        const double index = number(entry, "VertexIndex", entry_path + String(".VertexIndex"));
                        if (index < 1 || index >= vertices.size() || std::floor(index) != index) v.error(entry_path + String(".VertexIndex"), "Expected a non-root particle index within this setting.");
                    }
                }
            }
        }
        for (const String key : {String("PhysicsSettingCount"), String("TotalInputCount"), String("TotalOutputCount"), String("VertexCount")}) {
            const double declared = number(meta, key, "Meta." + key);
            const int actual = key == "PhysicsSettingCount" ? settings.size() : key == "TotalInputCount" ? inputs : key == "TotalOutputCount" ? outputs : particles;
            if (declared != actual) v.error("Meta." + key, "Declared count does not match decoded arrays.");
        }
    }
    Dictionary result;
    result["ok"] = v.ok;
    result["diagnostics"] = v.diagnostics;
    result["physics"] = v.ok ? data : Dictionary();
    return result;
}
