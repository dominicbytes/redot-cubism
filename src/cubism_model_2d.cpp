// SPDX-License-Identifier: MIT
#include "cubism_model_2d.hpp"
#include "gd_cubism_value_parameter.hpp"
#include "gd_cubism_value_part_opacity.hpp"
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <cmath>

void CubismModel2D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_model", "resource"), &CubismModel2D::set_model);
    ClassDB::bind_method(D_METHOD("get_model"), &CubismModel2D::get_model);
    ClassDB::bind_method(D_METHOD("load_model", "resource"), &CubismModel2D::load_model);
    ClassDB::bind_method(D_METHOD("unload_model"), &CubismModel2D::unload_model);
    ClassDB::bind_method(D_METHOD("reload_model"), &CubismModel2D::reload_model);
    ClassDB::bind_method(D_METHOD("is_ready"), &CubismModel2D::is_ready);
    ClassDB::bind_method(D_METHOD("get_model_state"), &CubismModel2D::get_model_state);
    ClassDB::bind_method(D_METHOD("get_last_error"), &CubismModel2D::get_last_error);
    ClassDB::bind_method(D_METHOD("_emit_load_started", "generation"), &CubismModel2D::emit_load_started);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "model", PROPERTY_HINT_RESOURCE_TYPE, "CubismModelResource"), "set_model", "get_model");
    ADD_GROUP("Playback", "");
    ClassDB::bind_method(D_METHOD("set_playback_process_mode", "mode"), &CubismModel2D::set_playback_process_mode);
    ClassDB::bind_method(D_METHOD("get_playback_process_mode"), &CubismModel2D::get_playback_process_mode);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "playback_process_mode", PROPERTY_HINT_ENUM, "Idle,Physics,Manual"), "set_playback_process_mode", "get_playback_process_mode");
    ClassDB::bind_method(D_METHOD("set_speed_scale", "speed"), &CubismModel2D::set_speed_scale);
    ClassDB::bind_method(D_METHOD("get_speed_scale"), &CubismModel2D::get_speed_scale);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed_scale", PROPERTY_HINT_RANGE, "0,256,0.01"), "set_speed_scale", "get_speed_scale");
    ClassDB::bind_method(D_METHOD("set_paused", "value"), &CubismModel2D::set_paused);
    ClassDB::bind_method(D_METHOD("get_paused"), &CubismModel2D::get_paused);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "paused"), "set_paused", "get_paused");
    ADD_GROUP("Effects", "");
    ClassDB::bind_method(D_METHOD("set_enable_physics", "value"), &CubismModel2D::set_enable_physics);
    ClassDB::bind_method(D_METHOD("get_enable_physics"), &CubismModel2D::get_enable_physics);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_physics"), "set_enable_physics", "get_enable_physics");
    ClassDB::bind_method(D_METHOD("set_enable_pose", "value"), &CubismModel2D::set_enable_pose);
    ClassDB::bind_method(D_METHOD("get_enable_pose"), &CubismModel2D::get_enable_pose);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_pose"), "set_enable_pose", "get_enable_pose");
    ClassDB::bind_method(D_METHOD("advance", "delta"), &CubismModel2D::advance);
    ClassDB::bind_method(D_METHOD("has_parameter", "id"), &CubismModel2D::has_parameter);
    ClassDB::bind_method(D_METHOD("get_parameter_value", "id"), &CubismModel2D::get_parameter_value);
    ClassDB::bind_method(D_METHOD("set_parameter_value", "id", "value", "weight"), &CubismModel2D::set_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("add_parameter_value", "id", "value", "weight"), &CubismModel2D::add_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("multiply_parameter_value", "id", "value", "weight"), &CubismModel2D::multiply_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("set_part_opacity", "id", "opacity"), &CubismModel2D::set_part_opacity);
    ClassDB::bind_method(D_METHOD("get_parameter_ids"), &CubismModel2D::get_parameter_ids);
    ClassDB::bind_method(D_METHOD("get_part_ids"), &CubismModel2D::get_part_ids);
    ClassDB::bind_method(D_METHOD("get_canvas_info"), &CubismModel2D::get_canvas_info);
    ADD_SIGNAL(MethodInfo("model_load_started", PropertyInfo(Variant::OBJECT, "resource", PROPERTY_HINT_RESOURCE_TYPE, "CubismModelResource")));
    ADD_SIGNAL(MethodInfo("model_ready", PropertyInfo(Variant::OBJECT, "resource", PROPERTY_HINT_RESOURCE_TYPE, "CubismModelResource")));
    ADD_SIGNAL(MethodInfo("model_failed", PropertyInfo(Variant::INT, "error_code"), PropertyInfo(Variant::STRING, "message")));
    BIND_ENUM_CONSTANT(IDLE); BIND_ENUM_CONSTANT(PHYSICS); BIND_ENUM_CONSTANT(MANUAL);
    BIND_ENUM_CONSTANT(UNLOADED); BIND_ENUM_CONSTANT(LOADING); BIND_ENUM_CONSTANT(READY);
    BIND_ENUM_CONSTANT(ERROR); BIND_ENUM_CONSTANT(DISPOSING); BIND_ENUM_CONSTANT(DISPOSED);
}

CubismModel2D::CubismModel2D() {
    runtime = memnew(GDCubismUserModel);
    runtime->set_name("CubismRuntime");
    runtime->set_process_callback(GDCubismUserModel::MANUAL);
    add_child(runtime, false, Node::INTERNAL_MODE_BACK);
    runtime->connect("model_ready", callable_mp(this, &CubismModel2D::on_model_ready));
    runtime->connect("model_failed", callable_mp(this, &CubismModel2D::on_model_failed));
    set_playback_process_mode(IDLE);
}

void CubismModel2D::_notification(int what) {
    switch (what) {
        case NOTIFICATION_ENTER_TREE:
            if (load_requested && !is_ready()) call_deferred("_emit_load_started", ++generation);
            set_playback_process_mode(playback_process_mode);
            break;
        case NOTIFICATION_EXIT_TREE:
            ++generation;
            set_process_internal(false);
            set_physics_process_internal(false);
            break;
        case NOTIFICATION_INTERNAL_PROCESS:
            if (playback_process_mode == IDLE) step(get_process_delta_time());
            break;
        case NOTIFICATION_INTERNAL_PHYSICS_PROCESS:
            if (playback_process_mode == PHYSICS) step(get_physics_process_delta_time());
            break;
        case NOTIFICATION_PREDELETE:
            if (runtime->is_native_busy()) { cancel_free(); queue_free(); }
            break;
    }
}

Error CubismModel2D::load_model(const Ref<CubismModelResource> &resource) {
    model = resource;
    load_requested = model.is_valid();
    ++generation;
    if (!load_requested) { runtime->unload_selected_model(); return OK; }
    call_deferred("_emit_load_started", generation);
    runtime->set_model(model);
    if (!load_requested || is_ready()) return OK;
    if (runtime->is_native_busy()) return ERR_BUSY;
    return godot::Error(int(runtime->get_last_error().get("code", FAILED)));
}

void CubismModel2D::unload_model() {
    load_requested = false;
    ++generation;
    runtime->unload_selected_model();
}

String CubismModel2D::get_last_error() const { return runtime->get_last_error().get("message", ""); }

void CubismModel2D::emit_load_started(uint64_t expected_generation) {
    if (expected_generation == generation && load_requested && !is_queued_for_deletion()) emit_signal("model_load_started", model);
}

void CubismModel2D::on_model_ready() {
    if (load_requested && is_ready() && !is_queued_for_deletion()) emit_signal("model_ready", model);
}

void CubismModel2D::on_model_failed(const Dictionary &error) {
    if (load_requested && !is_queued_for_deletion()) emit_signal("model_failed", error.get("code", FAILED), error.get("message", ""));
}

void CubismModel2D::set_playback_process_mode(PlaybackProcessMode mode) {
    if (mode < IDLE || mode > MANUAL) return;
    playback_process_mode = mode;
    set_process_internal(mode == IDLE);
    set_physics_process_internal(mode == PHYSICS);
}

void CubismModel2D::step(double delta) {
    if (!paused && is_ready() && is_inside_tree() && can_process()) runtime->advance(delta);
}

void CubismModel2D::advance(double delta) { if (playback_process_mode == MANUAL) step(delta); }

int CubismModel2D::parameter_index(const StringName &id) const {
    if (!is_ready()) return -1;
    const Array parameters = runtime->get_parameters();
    for (int i = 0; i < parameters.size(); ++i) {
        const Ref<GDCubismParameter> parameter = parameters[i];
        if (parameter->get_id() == String(id)) return i;
    }
    return -1;
}

double CubismModel2D::get_parameter_value(const StringName &id) const {
    const int index = parameter_index(id);
    return index < 0 ? 0.0 : runtime->evaluated_parameter(index);
}

Error CubismModel2D::queue_parameter(const StringName &id, double value, double weight, int operation) {
    if (!std::isfinite(value) || !std::isfinite(weight) || weight < 0.0 || weight > 1.0) return ERR_INVALID_PARAMETER;
    if (!is_ready()) return ERR_UNCONFIGURED;
    const int index = parameter_index(id);
    if (index < 0) return ERR_DOES_NOT_EXIST;
    return runtime->queue_post_effect_write(index, value, weight, operation);
}

Error CubismModel2D::set_part_opacity(const StringName &id, double opacity) {
    if (!std::isfinite(opacity)) return ERR_INVALID_PARAMETER;
    if (!is_ready()) return ERR_UNCONFIGURED;
    const Array parts = runtime->get_part_opacities();
    for (int i = 0; i < parts.size(); ++i) {
        const Ref<GDCubismPartOpacity> part = parts[i];
        if (part->get_id() == String(id)) return runtime->queue_post_effect_write(i, CLAMP(opacity, 0.0, 1.0), 1.0, 3);
    }
    return ERR_DOES_NOT_EXIST;
}

PackedStringArray CubismModel2D::get_parameter_ids() const {
    PackedStringArray ids;
    if (is_ready()) for (const Ref<GDCubismParameter> parameter : runtime->get_parameters()) ids.push_back(parameter->get_id());
    return ids;
}

PackedStringArray CubismModel2D::get_part_ids() const {
    PackedStringArray ids;
    if (is_ready()) for (const Ref<GDCubismPartOpacity> part : runtime->get_part_opacities()) ids.push_back(part->get_id());
    return ids;
}
