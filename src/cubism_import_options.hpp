// SPDX-License-Identifier: MIT
#ifndef CUBISM_IMPORT_OPTIONS_HPP
#define CUBISM_IMPORT_OPTIONS_HPP
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

godot::Dictionary cubism_import_defaults();
void register_cubism_import_settings();
godot::Variant cubism_maximum_file_count();
godot::Dictionary validate_cubism_import_options(const godot::Dictionary &options);
godot::Dictionary parse_cubism_import_manifest(const godot::String &text, const godot::String &path, const godot::Dictionary &options);
#endif
