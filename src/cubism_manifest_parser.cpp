// SPDX-License-Identifier: MIT
#include "cubism_manifest_parser.hpp"
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <cmath>

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
    ClassDB::bind_static_method("CubismManifestParser", D_METHOD("parse_manifest", "json", "source_path"), &CubismManifestParser::parse_manifest);
}

Dictionary CubismManifestParser::parse_manifest(const String &json, const String &source_path) {
    Validation v;
    Dictionary manifest;
    if (json.utf8().length() > MAX_JSON_BYTES) {
        v.error("$", "Manifest exceeds 4 MiB of UTF-8 JSON.");
    } else {
        // Redot replaces decoded NUL with U+FFFD. Reject it before decoding so
        // an invalid reference cannot silently become a different filename.
        for (int i = 0; i < json.length(); ++i) {
            if (json[i] == 0) v.error("$", "NUL characters are forbidden.");
            if (json[i] == '\\' && i + 1 < json.length()) {
                if (json.substr(i + 1, 5) == "u0000") v.error("$", "NUL escapes are forbidden.");
                ++i;
            }
        }
        Ref<JSON> parser;
        parser.instantiate();
        if (!v.ok) {
            // Do not invoke the decoder on input known to lose information.
        } else if (parser->parse(json) != OK || parser->get_data().get_type() != Variant::DICTIONARY) {
            v.error("$", "Expected a JSON object: " + parser->get_error_message());
        } else {
            // Select releasing copy assignment in the pinned redot-cpp binding.
            const Dictionary parsed = parser->get_data();
            manifest = parsed;
            v.bounded(manifest, "$");
        }
    }
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
