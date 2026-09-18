// SPDX-License-Identifier: MIT
#include "cubism_character_controller.hpp"
#include <godot_cpp/classes/audio_server.hpp>
#include <cmath>
#include <limits>

namespace {
bool number(const Variant &value, double minimum, double maximum) {
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) return false;
    const double converted = value;
    return std::isfinite(converted) && converted >= minimum && converted <= maximum;
}

Error validate_state(const Dictionary &state, const CubismModel2D *target) {
    if (state.size() != 17 || !number(state.get("version", Variant()), 1, 1)) return ERR_INVALID_DATA;
    for (const char *key : {"model_source", "model_fingerprint", "idle_motion", "expression_id", "voice_bus"}) {
        if (state.get(key, Variant()).get_type() != Variant::STRING) return ERR_INVALID_DATA;
    }
    for (const char *key : {"idle_active", "auto_return_to_idle", "paused", "visible", "look_active"}) {
        if (state.get(key, Variant()).get_type() != Variant::BOOL) return ERR_INVALID_DATA;
    }
    if (!number(state.get("cue_offset_seconds", Variant()), -60, 60) ||
            !number(state.get("transition_seconds", Variant()), 0, 60) ||
            !number(state.get("look_weight", Variant()), 0, 1)) return ERR_INVALID_DATA;
    const double limit = std::numeric_limits<real_t>::max();
    for (const char *key : {"transform", "modulate", "look_target"}) {
        const Variant value = state.get(key, Variant());
        if (value.get_type() != Variant::ARRAY) return ERR_INVALID_DATA;
        const Array components = value;
        const int count = String(key) == "transform" ? 6 : (String(key) == "modulate" ? 4 : 2);
        if (components.size() != count) return ERR_INVALID_DATA;
        for (int i = 0; i < count; ++i) if (!number(components[i], -limit, limit)) return ERR_INVALID_DATA;
    }
    const Ref<CubismModelResource> model = target->get_model();
    if (String(state["model_source"]) != model->get_source_model_path() ||
            String(state["model_fingerprint"]) != model->get_import_fingerprint()) return ERR_INVALID_DATA;
    const String idle = state["idle_motion"], expression = state["expression_id"];
    if ((!idle.is_empty() && !target->get_motion_ids().has(idle)) ||
            (!expression.is_empty() && !target->get_expression_ids().has(expression))) return ERR_DOES_NOT_EXIST;
    if (bool(state["idle_active"]) && (idle.is_empty() || !bool(state["visible"]))) return ERR_INVALID_DATA;
    if (AudioServer::get_singleton()->get_bus_index(String(state["voice_bus"])) < 0) return ERR_DOES_NOT_EXIST;
    return OK;
}
}

Dictionary CubismCharacterController::capture_state() const {
    Dictionary result;
    result["ok"] = false;
    result["error"] = ERR_UNCONFIGURED;
    result["state"] = Dictionary();
    auto *target = get_target_model();
    if (!is_inside_tree() || !target || !target->is_inside_tree() || !target->is_ready()) return result;
    if (is_queued_for_deletion() || target->is_queued_for_deletion()) { result["error"] = ERR_UNAVAILABLE; return result; }
    if (busy || speech.is_valid() || transition != NO_TRANSITION || !target->controller_state_available(get_instance_id())) {
        result["error"] = ERR_BUSY; return result;
    }
    // Only a controller-owned idle loop is a stable checkpoint motion choice.
    for (const auto &entry : target->motions) {
        if (!entry.second->is_finished() && entry.second != idle) { result["error"] = ERR_BUSY; return result; }
    }
    if (is_idle() && idle->get_motion_id() != idle_motion) { result["error"] = ERR_BUSY; return result; }
    Dictionary state;
    state["version"] = 1;
    state["model_source"] = target->get_model()->get_source_model_path();
    state["model_fingerprint"] = target->get_model()->get_import_fingerprint();
    state["idle_motion"] = String(idle_motion);
    state["idle_active"] = is_idle();
    state["expression_id"] = String(target->selected_expression);
    state["voice_bus"] = String(voice_bus);
    state["cue_offset_seconds"] = cue_offset;
    state["transition_seconds"] = transition_seconds;
    state["auto_return_to_idle"] = auto_return_to_idle;
    state["paused"] = paused;
    state["visible"] = target->is_visible();
    const Transform2D transform = target->get_transform();
    state["transform"] = Array::make(transform[0].x, transform[0].y, transform[1].x, transform[1].y, transform[2].x, transform[2].y);
    const Color color = target->get_modulate();
    state["modulate"] = Array::make(color.r, color.g, color.b, color.a);
    state["look_active"] = target->requested_look_active;
    const Vector2 look = target->requested_look_active ? target->requested_look_target : Vector2();
    state["look_target"] = Array::make(look.x, look.y);
    state["look_weight"] = target->requested_look_active ? target->requested_look_weight : 1.0;
    const Error error = validate_state(state, target);
    result["error"] = error;
    result["ok"] = error == OK;
    if (error == OK) result["state"] = state;
    return result;
}

Error CubismCharacterController::restore_state(const Dictionary &input) {
    if (busy) return ERR_BUSY;
    auto *target = get_target_model();
    if (!is_inside_tree() || !target || !target->is_inside_tree() || !target->is_ready()) return ERR_UNCONFIGURED;
    if (is_queued_for_deletion() || target->is_queued_for_deletion()) return ERR_UNAVAILABLE;
    if (!target->controller_state_available(get_instance_id())) return ERR_BUSY;
    const Error validation = validate_state(input, target);
    if (validation != OK) return validation;
    // Scene callbacks may mutate the caller's dictionary. Copy only after its
    // bounded, primitive-only schema has been validated.
    const Dictionary state = input.duplicate(true);
    const uint64_t revision = target->get_runtime_generation();
    auto available = [&]() {
        auto *current = get_target_model();
        return !is_queued_for_deletion() && is_inside_tree() && current == target && current &&
                !current->is_queued_for_deletion() && current->is_inside_tree() && current->is_ready() &&
                current->get_runtime_generation() == revision;
    };
    cancel_transition();
    terminate(CubismSpeechHandle::INTERRUPTED);
    busy = true;
    target->stop_motion(0);
    target->clear_expression(0);
    Error error = OK;
    const String expression = state["expression_id"];
    if (!expression.is_empty()) error = target->set_expression(expression, 0);
    if (error != OK) { busy = false; return error; }
    idle_motion = String(state["idle_motion"]);
    voice_bus = String(state["voice_bus"]);
    cue_offset = state["cue_offset_seconds"];
    transition_seconds = state["transition_seconds"];
    auto_return_to_idle = state["auto_return_to_idle"];
    paused = state["paused"];
    const Array transform = state["transform"], color = state["modulate"], look = state["look_target"];
    target->set_transform(Transform2D(Vector2(transform[0], transform[1]), Vector2(transform[2], transform[3]), Vector2(transform[4], transform[5])));
    if (!available()) { busy = false; return ERR_UNAVAILABLE; }
    target->set_modulate(Color(color[0], color[1], color[2], color[3]));
    if (!available()) { busy = false; return ERR_UNAVAILABLE; }
    if (bool(state["look_active"])) target->set_look_target(Vector2(look[0], look[1]), state["look_weight"]);
    else target->clear_look_target();
    target->set_visible(state["visible"]);
    if (!available()) { busy = false; return ERR_UNAVAILABLE; }
    // Fresh handles restore checkpoint choices without seeking an existing
    // voice or deserializing a native animation queue.
    if (bool(state["idle_active"])) error = start_idle();
    busy = false;
    return error;
}
