// SPDX-License-Identifier: MIT
#include "cubism_model_2d.hpp"
#include "gd_cubism_value_parameter.hpp"
#include "gd_cubism_value_part_opacity.hpp"
#include "cubism_animator.hpp"
#include "cubism_procedural_effects.hpp"
#include "cubism_lip_sync.hpp"
#include "cubism_character_controller.hpp"
#include "private/internal_cubism_user_model.hpp"
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <cmath>
#include <limits>

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
    ClassDB::bind_method(D_METHOD("set_autoplay", "value"), &CubismModel2D::set_autoplay);
    ClassDB::bind_method(D_METHOD("get_autoplay"), &CubismModel2D::get_autoplay);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "autoplay"), "set_autoplay", "get_autoplay");
    ClassDB::bind_method(D_METHOD("set_default_motion", "motion_id"), &CubismModel2D::set_default_motion);
    ClassDB::bind_method(D_METHOD("get_default_motion"), &CubismModel2D::get_default_motion);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "default_motion"), "set_default_motion", "get_default_motion");
    ClassDB::bind_method(D_METHOD("set_default_expression", "expression_id"), &CubismModel2D::set_default_expression);
    ClassDB::bind_method(D_METHOD("get_default_expression"), &CubismModel2D::get_default_expression);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "default_expression"), "set_default_expression", "get_default_expression");
    ClassDB::bind_method(D_METHOD("_start_autoplay", "generation"), &CubismModel2D::start_autoplay);
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
    ClassDB::bind_method(D_METHOD("set_deterministic_seed", "seed"), &CubismModel2D::set_deterministic_seed);
    ClassDB::bind_method(D_METHOD("get_deterministic_seed"), &CubismModel2D::get_deterministic_seed);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "deterministic_seed"), "set_deterministic_seed", "get_deterministic_seed");
    ADD_GROUP("Effects", "");
    ClassDB::bind_method(D_METHOD("set_enable_eye_blink", "value"), &CubismModel2D::set_enable_eye_blink);
    ClassDB::bind_method(D_METHOD("get_enable_eye_blink"), &CubismModel2D::get_enable_eye_blink);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_eye_blink"), "set_enable_eye_blink", "get_enable_eye_blink");
    ClassDB::bind_method(D_METHOD("set_enable_breath", "value"), &CubismModel2D::set_enable_breath);
    ClassDB::bind_method(D_METHOD("get_enable_breath"), &CubismModel2D::get_enable_breath);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_breath"), "set_enable_breath", "get_enable_breath");
    ClassDB::bind_method(D_METHOD("set_enable_look_target", "value"), &CubismModel2D::set_enable_look_target);
    ClassDB::bind_method(D_METHOD("get_enable_look_target"), &CubismModel2D::get_enable_look_target);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_look_target"), "set_enable_look_target", "get_enable_look_target");
    ClassDB::bind_method(D_METHOD("set_enable_lip_sync", "value"), &CubismModel2D::set_enable_lip_sync);
    ClassDB::bind_method(D_METHOD("get_enable_lip_sync"), &CubismModel2D::get_enable_lip_sync);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_lip_sync"), "set_enable_lip_sync", "get_enable_lip_sync");
    ClassDB::bind_method(D_METHOD("set_look_target", "local_target", "weight"), &CubismModel2D::set_look_target, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("clear_look_target"), &CubismModel2D::clear_look_target);
    ClassDB::bind_method(D_METHOD("set_enable_physics", "value"), &CubismModel2D::set_enable_physics);
    ClassDB::bind_method(D_METHOD("get_enable_physics"), &CubismModel2D::get_enable_physics);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_physics"), "set_enable_physics", "get_enable_physics");
    ClassDB::bind_method(D_METHOD("set_enable_pose", "value"), &CubismModel2D::set_enable_pose);
    ClassDB::bind_method(D_METHOD("get_enable_pose"), &CubismModel2D::get_enable_pose);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_pose"), "set_enable_pose", "get_enable_pose");
    ClassDB::bind_method(D_METHOD("advance", "delta"), &CubismModel2D::advance);
    ClassDB::bind_method(D_METHOD("play_motion", "motion_id", "priority", "loop", "speed"), &CubismModel2D::play_motion, DEFVAL(CubismMotionPriority::NORMAL), DEFVAL(false), DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("play_motion_from_group", "group", "index", "priority", "loop", "speed"), &CubismModel2D::play_motion_from_group, DEFVAL(CubismMotionPriority::NORMAL), DEFVAL(false), DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("stop_motion", "fade_out_seconds"), &CubismModel2D::stop_motion, DEFVAL(-1.0));
    ClassDB::bind_method(D_METHOD("get_motion_ids"), &CubismModel2D::get_motion_ids);
    ClassDB::bind_method(D_METHOD("set_expression", "expression_id", "fade_seconds"), &CubismModel2D::set_expression, DEFVAL(-1.0));
    ClassDB::bind_method(D_METHOD("clear_expression", "fade_seconds"), &CubismModel2D::clear_expression, DEFVAL(-1.0));
    ClassDB::bind_method(D_METHOD("get_expression_ids"), &CubismModel2D::get_expression_ids);
    ClassDB::bind_method(D_METHOD("_expression_changed", "expression_id", "generation"), &CubismModel2D::expression_changed);
    ClassDB::bind_method(D_METHOD("_deferred_clear_expression", "fade_seconds", "generation"), &CubismModel2D::deferred_clear_expression);
    ClassDB::bind_method(D_METHOD("_motion_started", "handle"), &CubismModel2D::motion_started);
    ClassDB::bind_method(D_METHOD("_deferred_stop_motion", "fade_seconds", "generation"), &CubismModel2D::deferred_stop_motion);
    ClassDB::bind_method(D_METHOD("has_parameter", "id"), &CubismModel2D::has_parameter);
    ClassDB::bind_method(D_METHOD("get_parameter_value", "id"), &CubismModel2D::get_parameter_value);
    ClassDB::bind_method(D_METHOD("set_parameter_value", "id", "value", "weight"), &CubismModel2D::set_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("add_parameter_value", "id", "value", "weight"), &CubismModel2D::add_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("multiply_parameter_value", "id", "value", "weight"), &CubismModel2D::multiply_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("set_part_opacity", "id", "opacity"), &CubismModel2D::set_part_opacity);
    ClassDB::bind_method(D_METHOD("get_parameter_ids"), &CubismModel2D::get_parameter_ids);
    ClassDB::bind_method(D_METHOD("get_part_ids"), &CubismModel2D::get_part_ids);
    ClassDB::bind_method(D_METHOD("get_canvas_info"), &CubismModel2D::get_canvas_info);
    ClassDB::bind_method(D_METHOD("get_hit_area_names"), &CubismModel2D::get_hit_area_names);
    ClassDB::bind_method(D_METHOD("hit_test", "hit_area", "local_point"), &CubismModel2D::hit_test);
    ClassDB::bind_method(D_METHOD("set_hit_test_target", "local_point"), &CubismModel2D::set_hit_test_target);
    ClassDB::bind_method(D_METHOD("clear_hit_test_target"), &CubismModel2D::clear_hit_test_target);
    ClassDB::bind_method(D_METHOD("_refresh_hit_areas"), &CubismModel2D::refresh_hit_areas);
    ADD_SIGNAL(MethodInfo("hit_area_entered", PropertyInfo(Variant::STRING_NAME, "hit_area")));
    ADD_SIGNAL(MethodInfo("hit_area_exited", PropertyInfo(Variant::STRING_NAME, "hit_area")));
    ADD_SIGNAL(MethodInfo("model_load_started", PropertyInfo(Variant::OBJECT, "resource", PROPERTY_HINT_RESOURCE_TYPE, "CubismModelResource")));
    ADD_SIGNAL(MethodInfo("model_ready", PropertyInfo(Variant::OBJECT, "resource", PROPERTY_HINT_RESOURCE_TYPE, "CubismModelResource")));
    ADD_SIGNAL(MethodInfo("model_failed", PropertyInfo(Variant::INT, "error_code"), PropertyInfo(Variant::STRING, "message")));
    const PropertyInfo handle_property(Variant::OBJECT, "handle", PROPERTY_HINT_RESOURCE_TYPE, "CubismMotionHandle");
    ADD_SIGNAL(MethodInfo("motion_started", handle_property, PropertyInfo(Variant::STRING_NAME, "motion_id")));
    ADD_SIGNAL(MethodInfo("motion_event", handle_property, PropertyInfo(Variant::STRING, "event_value")));
    ADD_SIGNAL(MethodInfo("motion_looped", handle_property, PropertyInfo(Variant::INT, "loop_count")));
    ADD_SIGNAL(MethodInfo("motion_finished", handle_property, PropertyInfo(Variant::STRING_NAME, "motion_id"), PropertyInfo(Variant::INT, "reason")));
    ADD_SIGNAL(MethodInfo("runtime_warning", PropertyInfo(Variant::INT, "code"), PropertyInfo(Variant::STRING, "message")));
    ADD_SIGNAL(MethodInfo("expression_changed", PropertyInfo(Variant::STRING_NAME, "expression_id")));
    BIND_ENUM_CONSTANT(IDLE); BIND_ENUM_CONSTANT(PHYSICS); BIND_ENUM_CONSTANT(MANUAL);
    BIND_ENUM_CONSTANT(UNLOADED); BIND_ENUM_CONSTANT(LOADING); BIND_ENUM_CONSTANT(READY);
    BIND_ENUM_CONSTANT(ERROR); BIND_ENUM_CONSTANT(DISPOSING); BIND_ENUM_CONSTANT(DISPOSED);
}

CubismModel2D::CubismModel2D() {
    runtime = memnew(GDCubismUserModel);
    runtime->enable_preferred_animation();
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
            call_deferred("_start_autoplay", generation);
            set_playback_process_mode(playback_process_mode);
            break;
        case NOTIFICATION_EXIT_TREE:
            notify_controller(CubismSpeechHandle::UNLOADED);
            reset_hit_tracking();
            ++generation;
            autoplay_started = false;
            motion_requested = false;
            expression_requested = false;
            set_process_internal(false);
            set_physics_process_internal(false);
            break;
        case NOTIFICATION_INTERNAL_PROCESS:
            if (playback_process_mode == IDLE) step(get_process_delta_time());
            break;
        case NOTIFICATION_INTERNAL_PHYSICS_PROCESS:
            if (playback_process_mode == PHYSICS) step(get_physics_process_delta_time());
            break;
        case NOTIFICATION_VISIBILITY_CHANGED:
            if (!is_visible_in_tree()) notify_controller(CubismSpeechHandle::HIDDEN);
            if (hit_target_active || !hovered_hit_areas.is_empty()) queue_hit_refresh();
            break;
        case NOTIFICATION_PAUSED:
        case NOTIFICATION_UNPAUSED:
        case NOTIFICATION_DISABLED:
        case NOTIFICATION_ENABLED:
            if (hit_target_active || !hovered_hit_areas.is_empty()) queue_hit_refresh();
            break;
        case NOTIFICATION_PREDELETE:
            if (runtime->is_native_busy()) { cancel_free(); queue_free(); }
            else {
                notify_controller(CubismSpeechHandle::MODEL_DISPOSED);
                if (auto *lip = Object::cast_to<CubismLipSync>(ObjectDB::get_instance(runtime->get_procedural_effects()->lip_sync_id))) lip->set_target_model(nullptr);
                runtime->get_animator()->clear(CubismMotionHandle::MODEL_DISPOSED);
            }
            break;
    }
}

Error CubismModel2D::load_model(const Ref<CubismModelResource> &resource) {
    notify_controller(CubismSpeechHandle::UNLOADED);
    reset_hit_tracking();
    model = resource;
    load_requested = model.is_valid();
    ++generation;
    autoplay_started = false;
    motion_requested = false;
    expression_requested = false;
    if (!load_requested) { runtime->unload_selected_model(); return OK; }
    call_deferred("_emit_load_started", generation);
    runtime->set_model(model);
    if (!load_requested || is_ready()) return OK;
    if (runtime->is_native_busy()) return ERR_BUSY;
    return godot::Error(int(runtime->get_last_error().get("code", FAILED)));
}

void CubismModel2D::unload_model() {
    notify_controller(CubismSpeechHandle::UNLOADED);
    reset_hit_tracking();
    load_requested = false;
    ++generation;
    runtime->unload_selected_model();
}

String CubismModel2D::get_last_error() const { return runtime->get_last_error().get("message", ""); }

void CubismModel2D::emit_load_started(uint64_t expected_generation) {
    if (expected_generation == generation && load_requested && !is_queued_for_deletion()) emit_signal("model_load_started", model);
}

void CubismModel2D::on_model_ready() {
    start_autoplay(generation);
    if (load_requested && is_ready() && !is_queued_for_deletion()) emit_signal("model_ready", model);
}

void CubismModel2D::start_autoplay(uint64_t expected_generation) {
    if (expected_generation != generation || autoplay_started || !autoplay || !load_requested
        || !is_ready() || !is_inside_tree() || is_queued_for_deletion()) return;
    autoplay_started = true;
    if (!motion_requested && default_motion != StringName()) {
        const Ref<CubismMotionHandle> handle = play_motion(default_motion, CubismMotionPriority::IDLE,
            runtime->get_animator()->get_default_loop(default_motion));
        if (handle->get_error() != OK) call_deferred("emit_signal", "runtime_warning", handle->get_error(), "Cannot autoplay motion: " + String(default_motion));
    }
    if (!expression_requested && default_expression != StringName()) {
        const Error error = set_expression(default_expression);
        if (error != OK) call_deferred("emit_signal", "runtime_warning", error, "Cannot autoplay expression: " + String(default_expression));
    }
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

void CubismModel2D::step(double delta, bool controller) {
    if (controller_clock_id && !controller) return;
    if (!paused && is_ready() && is_inside_tree() && can_process()) runtime->advance(delta);
    if (hit_target_active || !hovered_hit_areas.is_empty()) queue_hit_refresh();
}

void CubismModel2D::advance(double delta) { if (playback_process_mode == MANUAL) step(delta); }

void CubismModel2D::notify_controller(CubismSpeechHandle::FinishReason reason) {
    if (auto *controller = Object::cast_to<CubismCharacterController>(ObjectDB::get_instance(controller_clock_id))) controller->model_unavailable(this, reason);
}

Error CubismModel2D::claim_controller_clock(uint64_t controller) {
    if (runtime->is_native_busy() || is_queued_for_deletion()) return ERR_BUSY;
    if (controller_clock_id && controller_clock_id != controller && ObjectDB::get_instance(controller_clock_id)) return ERR_ALREADY_IN_USE;
    if (controller_clock_id == controller) return OK;
    before_controller_mode = playback_process_mode;
    before_controller_speed = get_speed_scale();
    controller_clock_id = controller;
    set_playback_process_mode(MANUAL);
    set_speed_scale(1);
    return OK;
}

void CubismModel2D::release_controller_clock(uint64_t controller) {
    if (controller_clock_id != controller) return;
    controller_clock_id = 0;
    set_playback_process_mode(before_controller_mode);
    set_speed_scale(before_controller_speed);
}

bool CubismModel2D::advance_controller_clock(uint64_t controller, double delta) {
    if (controller_clock_id != controller || runtime->is_native_busy() || paused || !is_ready() || !is_inside_tree() || !can_process()) return false;
    step(delta, true);
    return true;
}

void CubismModel2D::set_enable_eye_blink(bool value) { runtime->get_procedural_effects()->enable_eye_blink = value; }
bool CubismModel2D::get_enable_eye_blink() const { return runtime->get_procedural_effects()->enable_eye_blink; }
void CubismModel2D::set_enable_breath(bool value) { runtime->get_procedural_effects()->enable_breath = value; }
bool CubismModel2D::get_enable_breath() const { return runtime->get_procedural_effects()->enable_breath; }
void CubismModel2D::set_deterministic_seed(int64_t value) { runtime->get_procedural_effects()->set_seed(value); }
int64_t CubismModel2D::get_deterministic_seed() const { return runtime->get_procedural_effects()->get_seed(); }

void CubismModel2D::set_enable_look_target(bool value) { runtime->get_procedural_effects()->enable_look_target = value; }
bool CubismModel2D::get_enable_look_target() const { return runtime->get_procedural_effects()->enable_look_target; }

void CubismModel2D::set_look_target(const Vector2 &local_target, double weight) {
    if (!std::isfinite(local_target.x) || !std::isfinite(local_target.y) || !std::isfinite(weight) || weight < 0.0 || weight > 1.0) {
        call_deferred("emit_signal", "runtime_warning", ERR_INVALID_PARAMETER, "Invalid look target or weight.");
        return;
    }
    if (!is_ready()) {
        call_deferred("emit_signal", "runtime_warning", ERR_UNCONFIGURED, "Look target requires a loaded model.");
        return;
    }
    const Vector2 direction = runtime->internal_model->look_direction(local_target);
    runtime->get_procedural_effects()->set_look_target(direction.x, direction.y, float(weight));
}

void CubismModel2D::clear_look_target() { runtime->get_procedural_effects()->clear_look_target(); }

void CubismModel2D::set_enable_lip_sync(bool value) { runtime->get_procedural_effects()->enable_lip_sync = value; }
bool CubismModel2D::get_enable_lip_sync() const { return runtime->get_procedural_effects()->enable_lip_sync; }

Error CubismModel2D::attach_lip_sync(uint64_t component) {
    if (is_queued_for_deletion()) return ERR_UNAVAILABLE;
    auto *effects = runtime->get_procedural_effects();
    if (effects->lip_sync_id != component && ObjectDB::get_instance(effects->lip_sync_id)) return ERR_ALREADY_IN_USE;
    effects->lip_sync_id = component;
    return OK;
}

void CubismModel2D::detach_lip_sync(uint64_t component) {
    auto *effects = runtime->get_procedural_effects();
    if (effects->lip_sync_id == component) effects->lip_sync_id = 0;
}

PackedStringArray CubismModel2D::get_hit_area_names() const {
    PackedStringArray names;
    if (is_ready()) for (const Dictionary area : runtime->get_hit_areas()) {
        const String name = area["name"];
        if (!names.has(name)) names.push_back(name);
    }
    return names;
}

bool CubismModel2D::hit_test(const StringName &hit_area, const Vector2 &local_point) const {
    return is_ready() && std::isfinite(local_point.x) && std::isfinite(local_point.y)
        && runtime->internal_model->hit_test(hit_area, local_point);
}

void CubismModel2D::set_hit_test_target(const Vector2 &local_point) {
    if (!std::isfinite(local_point.x) || !std::isfinite(local_point.y)) {
        call_deferred("emit_signal", "runtime_warning", ERR_INVALID_PARAMETER, "Invalid hit-test target.");
        return;
    }
    hit_target = local_point;
    hit_target_active = true;
    queue_hit_refresh();
}

void CubismModel2D::clear_hit_test_target() {
    hit_target_active = false;
    queue_hit_refresh();
}

void CubismModel2D::reset_hit_tracking() {
    hit_target_active = false;
    hit_reset = true;
    queue_hit_refresh();
}

void CubismModel2D::queue_hit_refresh() {
    ++hit_revision;
    if (!hit_refresh_pending && !is_queued_for_deletion()) {
        hit_refresh_pending = true;
        call_deferred("_refresh_hit_areas");
    }
}

void CubismModel2D::refresh_hit_areas() {
    hit_refresh_pending = false;
    if (is_queued_for_deletion()) return;
    PackedStringArray current;
    if (!hit_reset && hit_target_active && is_inside_tree() && is_visible_in_tree() && can_process()) {
        for (const String &name : get_hit_area_names()) if (hit_test(name, hit_target)) current.push_back(name);
    }
    const uint64_t revision = hit_revision;
    const PackedStringArray previous = hovered_hit_areas;
    for (const String &name : previous) {
        if (current.has(name)) continue;
        hovered_hit_areas.remove_at(hovered_hit_areas.find(name));
        emit_signal("hit_area_exited", StringName(name));
        if (revision != hit_revision || is_queued_for_deletion()) return;
    }
    if (hit_reset) {
        hit_reset = false;
        if (hit_target_active) queue_hit_refresh();
        return;
    }
    for (const String &name : current) {
        if (hovered_hit_areas.has(name)) continue;
        hovered_hit_areas.push_back(name);
        emit_signal("hit_area_entered", StringName(name));
        if (revision != hit_revision || is_queued_for_deletion()) return;
    }
}

PackedStringArray CubismModel2D::get_motion_ids() const { return runtime->get_animator()->get_motion_ids(); }

PackedStringArray CubismModel2D::get_expression_ids() const {
    return is_ready() ? runtime->internal_model->get_expression_ids() : PackedStringArray();
}

Error CubismModel2D::set_expression(const StringName &id, double fade_seconds) {
    if (!std::isfinite(fade_seconds) || (fade_seconds < 0.0 && fade_seconds != -1.0)
        || fade_seconds > double(std::numeric_limits<float>::max())) return ERR_INVALID_PARAMETER;
    if (!is_ready()) return ERR_UNCONFIGURED;
    if (runtime->is_native_busy()) return ERR_BUSY;
    const Error result = runtime->internal_model->preferred_expression_set(id, fade_seconds);
    if (result == OK) {
        expression_requested = true;
        call_deferred("_expression_changed", id, generation);
    }
    return result;
}

void CubismModel2D::clear_expression(double fade_seconds) {
    if (!std::isfinite(fade_seconds) || (fade_seconds < 0.0 && fade_seconds != -1.0)
        || fade_seconds > double(std::numeric_limits<float>::max())) {
        call_deferred("emit_signal", "runtime_warning", ERR_INVALID_PARAMETER, "Invalid expression fade duration.");
        return;
    }
    if (!is_ready()) return;
    expression_requested = true;
    if (runtime->is_native_busy()) { call_deferred("_deferred_clear_expression", fade_seconds, generation); return; }
    runtime->internal_model->preferred_expression_clear(fade_seconds);
    call_deferred("_expression_changed", StringName(), generation);
}

void CubismModel2D::deferred_clear_expression(double fade_seconds, uint64_t expected_generation) {
    if (generation == expected_generation) clear_expression(fade_seconds);
}

void CubismModel2D::expression_changed(const StringName &id, uint64_t expected_generation) {
    if (generation == expected_generation && is_ready() && !is_queued_for_deletion()) emit_signal("expression_changed", id);
}

Ref<CubismMotionHandle> CubismModel2D::play_motion(const StringName &id, CubismMotionPriority::Priority priority, bool loop, double speed) {
    if (!is_ready()) return CubismMotionHandle::rejected(id, ERR_UNCONFIGURED);
    if (runtime->is_native_busy()) return CubismMotionHandle::rejected(id, ERR_BUSY);
    const Ref<CubismMotionHandle> handle = runtime->get_animator()->play(*runtime->internal_model, id, priority, loop, speed);
    if (handle->get_error() != OK) return handle;
    motion_requested = true;
    motions[handle->get_id()] = handle;
    handle->connect("event", callable_mp(this, &CubismModel2D::motion_event).bind(handle->get_id()));
    handle->connect("looped", callable_mp(this, &CubismModel2D::motion_looped).bind(handle->get_id()));
    handle->connect("finished", callable_mp(this, &CubismModel2D::motion_finished).bind(handle->get_id()));
    call_deferred("_motion_started", handle);
    return handle;
}

Ref<CubismMotionHandle> CubismModel2D::play_motion_from_group(const StringName &group, int index, CubismMotionPriority::Priority priority, bool loop, double speed) {
    return play_motion(runtime->get_animator()->find_motion(group, index), priority, loop, speed);
}

void CubismModel2D::stop_motion(double fade_seconds) {
    if (!std::isfinite(fade_seconds) || (fade_seconds < 0.0 && fade_seconds != -1.0) || fade_seconds > double(std::numeric_limits<float>::max()) / 256.0) {
        call_deferred("emit_signal", "runtime_warning", ERR_INVALID_PARAMETER, "Invalid motion fade duration.");
        return;
    }
    motion_requested = true;
    if (runtime->is_native_busy()) { call_deferred("_deferred_stop_motion", fade_seconds, generation); return; }
    runtime->get_animator()->stop(fade_seconds);
}

void CubismModel2D::deferred_stop_motion(double fade_seconds, uint64_t expected_generation) {
    if (generation == expected_generation) stop_motion(fade_seconds);
}

void CubismModel2D::motion_started(const Ref<CubismMotionHandle> &handle) {
    if (!is_queued_for_deletion()) emit_signal("motion_started", handle, handle->get_motion_id());
}

void CubismModel2D::motion_event(const String &value, int64_t id) {
    const auto found = motions.find(id);
    if (found != motions.end() && !is_queued_for_deletion()) {
        const Ref<CubismMotionHandle> handle = found->second;
        emit_signal("motion_event", handle, value);
    }
}

void CubismModel2D::motion_looped(int64_t count, int64_t id) {
    const auto found = motions.find(id);
    if (found != motions.end() && !is_queued_for_deletion()) {
        const Ref<CubismMotionHandle> handle = found->second;
        emit_signal("motion_looped", handle, count);
    }
}

void CubismModel2D::motion_finished(int reason, int64_t id) {
    const auto found = motions.find(id);
    if (found == motions.end()) return;
    const Ref<CubismMotionHandle> handle = found->second;
    motions.erase(found);
    if (!is_queued_for_deletion()) emit_signal("motion_finished", handle, handle->get_motion_id(), reason);
}

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
