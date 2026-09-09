// SPDX-License-Identifier: MIT
#ifndef CUBISM_MANIFEST_PARSER_HPP
#define CUBISM_MANIFEST_PARSER_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

// Pure syntax validation. The importer must still check physical paths, files,
// MOC compatibility and imported resource types before constructing a model.
class CubismManifestParser : public godot::RefCounted {
    GDCLASS(CubismManifestParser, godot::RefCounted);
protected:
    static void _bind_methods();
public:
    static godot::Dictionary parse_manifest(const godot::String &json, const godot::String &source_path);
};

#endif
