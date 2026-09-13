// SPDX-License-Identifier: MIT
#include "cubism_import_options.hpp"
#include "cubism_manifest_parser.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/global_constants.hpp>

using namespace godot;

namespace {
const char *MAXIMUM_FILES_SETTING = "cubism/import/maximum_file_count";
constexpr int DEFAULT_MAXIMUM_FILES = 1024;
constexpr int HARD_MAXIMUM_FILES = 4096;
}

void register_cubism_import_settings() {
    auto *settings = ProjectSettings::get_singleton();
    if (!settings->has_setting(MAXIMUM_FILES_SETTING)) settings->set_setting(MAXIMUM_FILES_SETTING, DEFAULT_MAXIMUM_FILES);
    settings->set_initial_value(MAXIMUM_FILES_SETTING, DEFAULT_MAXIMUM_FILES);
    Dictionary info;
    info["name"] = MAXIMUM_FILES_SETTING;
    info["type"] = Variant::INT;
    info["hint"] = PROPERTY_HINT_RANGE;
    info["hint_string"] = "1,4096,1";
    settings->add_property_info(info);
    settings->set_as_basic(MAXIMUM_FILES_SETTING, true);
}

Variant cubism_maximum_file_count() {
    return ProjectSettings::get_singleton()->get_setting(MAXIMUM_FILES_SETTING, DEFAULT_MAXIMUM_FILES);
}

Dictionary cubism_import_defaults() {
    Dictionary options;
    options["validation/strict_optional_files"] = false;
    options["motions/import_manifest_motions"] = true;
    options["expressions/import"] = true;
    options["rendering/mask_quality"] = 1;
    options["motions/convert_to_redot_animation"] = false;
    return options;
}

Dictionary validate_cubism_import_options(const Dictionary &input) {
    Dictionary options = cubism_import_defaults();
    Array diagnostics;
    const Array keys = input.keys();
    for (int i = 0; i < keys.size(); ++i) {
        String message;
        if (!options.has(keys[i])) message = "Unknown or unavailable import option.";
        else if (String(keys[i]) == "rendering/mask_quality") {
            const Variant value = input[keys[i]];
            if (value.get_type() != Variant::INT || int64_t(value) < 0 || int64_t(value) > 2)
                message = "Expected Low (0), Medium (1), or High (2) mask quality.";
            else options[keys[i]] = value;
        }
        else if (input[keys[i]].get_type() != Variant::BOOL) message = "Expected a boolean import option.";
        else if (String(keys[i]) == "motions/convert_to_redot_animation" && bool(input[keys[i]])) message = "Redot Animation conversion is not available in P0.";
        else options[keys[i]] = input[keys[i]];
        if (!message.is_empty() && diagnostics.size() < 32) {
            Dictionary diagnostic;
            diagnostic["path"] = keys[i];
            diagnostic["message"] = message;
            diagnostics.push_back(diagnostic);
        }
    }
    Dictionary result;
    result["ok"] = diagnostics.is_empty();
    result["options"] = options;
    result["diagnostics"] = diagnostics;
    return result;
}

Dictionary parse_cubism_import_manifest(const String &text, const String &path, const Dictionary &options) {
    Dictionary parsed = CubismManifestParser::parse_manifest(text, path);
    if (!bool(parsed["ok"])) return parsed;
    Dictionary manifest = parsed["manifest"];
    Dictionary files = manifest["FileReferences"];
    Dictionary omitted;
    if (!bool(options.get("expressions/import", true))) {
        const Array expressions = files.get("Expressions", Array());
        for (int i = 0; i < expressions.size(); ++i) {
            const Dictionary expression = expressions[i];
            omitted[expression["File"]] = true;
        }
        files.erase("Expressions");
    }
    if (!bool(options.get("motions/import_manifest_motions", true))) {
        const Dictionary motions = files.get("Motions", Dictionary());
        const Array groups = motions.values();
        for (int i = 0; i < groups.size(); ++i) {
            const Array entries = groups[i];
            for (int j = 0; j < entries.size(); ++j) {
                const Dictionary motion = entries[j];
                omitted[motion["File"]] = true;
                if (motion.has("Sound")) omitted[motion["Sound"]] = true;
            }
        }
        files.erase("Motions");
    }
    // These categories have distinct source suffixes; their references cannot
    // also supply a retained MOC, PNG, physics, pose or display-info dependency.
    const PackedStringArray original = parsed["dependencies"];
    PackedStringArray dependencies;
    for (int i = 0; i < original.size(); ++i) {
        if (!omitted.has(original[i])) dependencies.push_back(original[i]);
    }
    parsed["dependencies"] = dependencies;
    const Variant limit = cubism_maximum_file_count();
    String message;
    if (limit.get_type() != Variant::INT || int64_t(limit) < 1 || int64_t(limit) > HARD_MAXIMUM_FILES) {
        message = "Expected an integer file limit between 1 and 4096.";
    } else if (dependencies.size() + 1 > int64_t(limit)) {
        message = "Model requires " + String::num_int64(dependencies.size() + 1) + String(" files, exceeding the project import limit of ") + String::num_int64(limit) + String(".");
    }
    if (!message.is_empty()) {
        Dictionary diagnostic;
        diagnostic["path"] = String("project_settings.") + MAXIMUM_FILES_SETTING;
        diagnostic["message"] = message;
        Array diagnostics;
        diagnostics.push_back(diagnostic);
        parsed["ok"] = false;
        parsed["diagnostics"] = diagnostics;
        parsed["manifest"] = Dictionary();
    }
    return parsed;
}
