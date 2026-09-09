// SPDX-License-Identifier: MIT
#ifndef CUBISM_MANIFEST_PARSER_HPP
#define CUBISM_MANIFEST_PARSER_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

// Import validation helpers; neither method loads a model or a resource.
class CubismManifestParser : public godot::RefCounted {
    GDCLASS(CubismManifestParser, godot::RefCounted);
protected:
    static void _bind_methods();
public:
    // Filesystem-independent schema and lexical path validation.
    static godot::Dictionary parse_manifest(const godot::String &json, const godot::String &source_path);
    // Physical filesystem snapshot, not a virtual/exported resource lookup.
    static godot::Dictionary validate_project_file(const godot::String &path);
};

#endif
