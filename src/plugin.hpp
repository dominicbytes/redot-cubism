// SPDX-License-Identifier: MIT
#ifndef GD_CUBISM_PLUGIN
#define GD_CUBISM_PLUGIN
// ----------------------------------------------------------------- include(s)
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/classes/editor_plugin.hpp>
#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/spin_box.hpp>
#include "cubism_model_importer.hpp"
#include "cubism_model_inspector.hpp"
#include "cubism_export_plugin.hpp"
#include "cubism_dependency_tracker.hpp"
#include <godot_cpp/classes/editor_file_dialog.hpp>

// ------------------------------------------------------------------ define(s)
// --------------------------------------------------------------- namespace(s)
using namespace godot;

// -------------------------------------------------------------------- enum(s)
// ------------------------------------------------------------------- const(s)
// ----------------------------------------------------------- class:forward(s)
class GDCubismUserModel;

// ------------------------------------------------------------------- class(s)
class GDCubismPlugin : public EditorPlugin {
    GDCLASS(GDCubismPlugin, EditorPlugin);

private:
    Ref<CubismModelImporter> model_importer;
    Ref<CubismModelInspector> model_inspector;
    Ref<CubismExportPlugin> export_plugin;
    CubismDependencyTracker *dependency_tracker = nullptr;
    EditorFileDialog *cubism_source_dialog = nullptr;
    EditorFileDialog *cubism_save_dialog = nullptr;
    Node *checked_export_ui = nullptr;
    String cubism_source_path;
    bool legacy_source_import = false;
    void show_cubism_import_dialog();
    void show_legacy_cubism_import_dialog();
    void select_cubism_source(const String &path);
    void save_cubism_resource(const String &path);
    void show_checked_export();
    const Color selected_border_color = Color(239.0 / 255.0, 120.0 / 255.0, 62.0 / 255.0, 1.0);

    GDCubismUserModel *selected_model;
    Rect2 selected_rect;
    bool drag;
    Vector2 drag_position;
    Vector2 base_position;

    Button *p_snapmode_button;
    SpinBox *p_snapsize_spinbox;
    
protected:
    static void _bind_methods() {}

private:
    Rect2 get_cubism_model_rect(GDCubismUserModel *selected_model) const;
    PackedVector2Array get_cubism_model_vertex(GDCubismUserModel *model) const;
    bool update_selected_info();

public:
    void _enter_tree() override;
    void _exit_tree() override;
    void _input(const Ref<InputEvent> &p_event) override;

    void _edit(Object *p_object) override;
    bool _handles(Object *p_object) const override;
    bool _forward_canvas_gui_input(const Ref<InputEvent> &p_event) override;
    void _forward_canvas_draw_over_viewport(Control *p_viewport_control) override;
};

#endif // GD_CUBISM_PLUGIN
