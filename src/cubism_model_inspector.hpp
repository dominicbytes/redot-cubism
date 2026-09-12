// SPDX-License-Identifier: MIT
#ifndef CUBISM_MODEL_INSPECTOR_HPP
#define CUBISM_MODEL_INSPECTOR_HPP
#include "cubism_model_resource.hpp"
#include <godot_cpp/classes/editor_inspector_plugin.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/classes/label.hpp>

class CubismModelSummary : public godot::VBoxContainer {
    GDCLASS(CubismModelSummary, godot::VBoxContainer);
    godot::Ref<CubismModelResource> model;
    godot::Label *summary = nullptr;
    void refresh();
protected:
    static void _bind_methods() {}
public:
    CubismModelSummary();
    ~CubismModelSummary();
    void set_model(const godot::Ref<CubismModelResource> &resource);
};

class CubismModelInspector : public godot::EditorInspectorPlugin {
    GDCLASS(CubismModelInspector, godot::EditorInspectorPlugin);
protected:
    static void _bind_methods() {}
public:
    bool _can_handle(godot::Object *object) const override;
    void _parse_begin(godot::Object *object) override;
};
#endif
