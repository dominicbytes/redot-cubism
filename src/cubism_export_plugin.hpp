// SPDX-License-Identifier: MIT
#ifndef CUBISM_EXPORT_PLUGIN_HPP
#define CUBISM_EXPORT_PLUGIN_HPP
#include <godot_cpp/classes/editor_export_plugin.hpp>
#include <godot_cpp/variant/dictionary.hpp>

class CubismExportPlugin : public godot::EditorExportPlugin {
    GDCLASS(CubismExportPlugin, godot::EditorExportPlugin);
    godot::Dictionary injected;
    godot::Dictionary seen_raw;
    bool shaders_added = false;
protected:
    static void _bind_methods() {}
public:
    godot::String _get_name() const override;
    void _export_begin(const godot::PackedStringArray &features, bool debug, const godot::String &path, uint32_t flags) override;
    void _export_file(const godot::String &path, const godot::String &type, const godot::PackedStringArray &features) override;
    void _export_end() override;
};
#endif
