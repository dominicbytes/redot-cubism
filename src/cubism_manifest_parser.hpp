// SPDX-License-Identifier: MIT
#ifndef CUBISM_MANIFEST_PARSER_HPP
#define CUBISM_MANIFEST_PARSER_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

// Import validation helpers; no method creates a live SDK model.
class CubismManifestParser : public godot::RefCounted {
    GDCLASS(CubismManifestParser, godot::RefCounted);
protected:
    static void _bind_methods();
public:
    // Filesystem-independent schema and lexical path validation.
    static godot::Dictionary parse_manifest(const godot::String &json, const godot::String &source_path);
    static godot::Dictionary parse_expression(const godot::String &json, const godot::String &expression_id, const godot::String &source_path);
    static godot::Dictionary parse_motion(const godot::String &json, const godot::String &group, int index, const godot::String &source_path);
    static godot::Dictionary parse_user_data(const godot::String &json);
    static godot::Dictionary parse_display_info(const godot::String &json);
    static godot::Dictionary parse_physics(const godot::String &json);
    static godot::Dictionary parse_pose(const godot::String &json);
    static godot::Dictionary read_project_json(const godot::String &path);
    // Physical filesystem snapshot, not a virtual/exported resource lookup.
    static godot::Dictionary validate_project_file(const godot::String &path);
};

#endif
