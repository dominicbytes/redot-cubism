// SPDX-License-Identifier: MIT
#ifndef CUBISM_MODEL_IMPORTER_HPP
#define CUBISM_MODEL_IMPORTER_HPP
#include <godot_cpp/classes/editor_import_plugin.hpp>

class CubismModelImporter : public godot::EditorImportPlugin {
    GDCLASS(CubismModelImporter, godot::EditorImportPlugin);
protected:
    static void _bind_methods();
public:
    static godot::String fingerprint(const godot::Dictionary &files, const godot::Dictionary &options);
    static godot::Error import_model(const godot::String &source_file, const godot::String &destination, bool strict_optional_files = false);
    static godot::Error import_model_with_options(const godot::String &source_file, const godot::String &destination, const godot::Dictionary &options);
    godot::String _get_importer_name() const override;
    godot::String _get_visible_name() const override;
    godot::PackedStringArray _get_recognized_extensions() const override;
    godot::String _get_save_extension() const override;
    godot::String _get_resource_type() const override;
    int32_t _get_preset_count() const override;
    godot::TypedArray<godot::Dictionary> _get_import_options(const godot::String &path, int32_t preset_index) const override;
    bool _get_option_visibility(const godot::String &path, const godot::StringName &option_name, const godot::Dictionary &options) const override;
    float _get_priority() const override;
    int32_t _get_import_order() const override;
    int32_t _get_format_version() const override;
    bool _can_import_threaded() const override;
    godot::Error _import(const godot::String &source_file, const godot::String &save_path,
        const godot::Dictionary &options, const godot::TypedArray<godot::String> &platform_variants,
        const godot::TypedArray<godot::String> &gen_files) const override;
};
#endif
