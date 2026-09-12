// SPDX-License-Identifier: MIT
#include "cubism_import_options.hpp"
#include "cubism_manifest_parser.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

using namespace godot;

Dictionary cubism_import_defaults() {
    Dictionary options;
    options["validation/strict_optional_files"] = false;
    options["motions/import_manifest_motions"] = true;
    options["expressions/import"] = true;
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
        else if (input[keys[i]].get_type() != Variant::BOOL) message = "Expected a boolean import option.";
        else if (keys[i] == Variant("motions/convert_to_redot_animation") && bool(input[keys[i]])) message = "Redot Animation conversion is not available in P0.";
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
    return parsed;
}
