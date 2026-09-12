// SPDX-License-Identifier: MIT
#include "cubism_model_inspector.hpp"
#include <godot_cpp/classes/text_server.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

CubismModelSummary::CubismModelSummary() {
    set_name("CubismModelSummary");
    summary = memnew(Label);
    summary->set_name("Summary");
    summary->set_autowrap_mode(TextServer::AUTOWRAP_WORD_SMART);
    summary->set_text("Cubism Model");
    add_child(summary);
}

CubismModelSummary::~CubismModelSummary() {
    if (model.is_valid()) model->disconnect("changed", callable_mp(this, &CubismModelSummary::refresh));
}

void CubismModelSummary::set_model(const Ref<CubismModelResource> &resource) {
    if (model.is_valid()) model->disconnect("changed", callable_mp(this, &CubismModelSummary::refresh));
    model = resource;
    if (model.is_valid()) model->connect("changed", callable_mp(this, &CubismModelSummary::refresh));
    refresh();
}

void CubismModelSummary::refresh() {
    if (model.is_null()) { summary->set_text("Cubism Model"); return; }
    String text = "Cubism Model\n";
    if (model->get_source_model_path().is_empty()) {
        text += "No imported source. Use Project > Tools > Import Cubism Model.";
    } else {
        text += String("Source: ") + model->get_source_model_path().substr(0, 4096);
        int64_t motions = 0;
        const Dictionary groups = model->get_motion_groups();
        const Array values = groups.values();
        for (int i = 0; i < values.size(); ++i) {
            if (values[i].get_type() == Variant::ARRAY) motions += Array(values[i]).size();
        }
        text += String("\nTextures: ") + String::num_int64(model->get_textures().size());
        text += String("\nMotions: ") + String::num_int64(motions) + String(" in ") + String::num_int64(groups.size()) + String(" groups");
        text += String("\nExpressions: ") + String::num_int64(model->get_expressions().size());
        const Vector2 canvas = model->get_canvas_size();
        text += String("\nCanvas: ") + String::num(canvas.x) + String(" x ") + String::num(canvas.y) + String(" px");
        text += String("\nHit areas: ") + String::num_int64(model->get_hit_areas().size());
    }
    const PackedStringArray warnings = model->get_import_warnings();
    text += String("\n\nImport warnings: ") + (warnings.is_empty() ? String("None recorded") : String::num_int64(warnings.size()));
    for (int i = 0; i < warnings.size() && i < 8; ++i) text += String("\n- ") + warnings[i].substr(0, 512);
    if (warnings.size() > 8) text += String("\nMore warnings are available in Import Warnings below.");
    // Plain text: imported metadata must never be interpreted as rich-text markup.
    summary->set_text(text);
}

bool CubismModelInspector::_can_handle(Object *object) const {
    return Object::cast_to<CubismModelResource>(object) != nullptr;
}

void CubismModelInspector::_parse_begin(Object *object) {
    auto *model = Object::cast_to<CubismModelResource>(object);
    if (!model) return;
    auto *control = memnew(CubismModelSummary);
    control->set_model(Ref<CubismModelResource>(model));
    add_custom_control(control);
}
