// SPDX-License-Identifier: MIT
#include "cubism_motion_handle.hpp"
#include <godot_cpp/core/object.hpp>

void CubismMotionHandle::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_id"), &CubismMotionHandle::get_id);
    ClassDB::bind_method(D_METHOD("get_motion_id"), &CubismMotionHandle::get_motion_id);
    ClassDB::bind_method(D_METHOD("get_state"), &CubismMotionHandle::get_state);
    ClassDB::bind_method(D_METHOD("is_finished"), &CubismMotionHandle::is_finished);
    ClassDB::bind_method(D_METHOD("get_reason"), &CubismMotionHandle::get_reason);
    ClassDB::bind_method(D_METHOD("get_error"), &CubismMotionHandle::get_error);
    ClassDB::bind_method(D_METHOD("get_loop_count"), &CubismMotionHandle::get_loop_count);
    ClassDB::bind_method(D_METHOD("get_elapsed_seconds"), &CubismMotionHandle::get_elapsed_seconds);
    ClassDB::bind_method(D_METHOD("_dispatch_events"), &CubismMotionHandle::dispatch_events);
    ADD_SIGNAL(MethodInfo("finished", PropertyInfo(Variant::INT, "reason")));
    ADD_SIGNAL(MethodInfo("event", PropertyInfo(Variant::STRING, "value")));
    ADD_SIGNAL(MethodInfo("looped", PropertyInfo(Variant::INT, "loop_count")));
    BIND_ENUM_CONSTANT(PLAYING); BIND_ENUM_CONSTANT(FINISHED); BIND_ENUM_CONSTANT(NONE);
    BIND_ENUM_CONSTANT(COMPLETED); BIND_ENUM_CONSTANT(STOPPED); BIND_ENUM_CONSTANT(INTERRUPTED);
    BIND_ENUM_CONSTANT(FAILED); BIND_ENUM_CONSTANT(UNLOADED); BIND_ENUM_CONSTANT(RELOADED); BIND_ENUM_CONSTANT(MODEL_DISPOSED);
}

Ref<CubismMotionHandle> CubismMotionHandle::rejected(const StringName &id, Error code) {
    Ref<CubismMotionHandle> handle;
    handle.instantiate();
    handle->motion_id = id;
    handle->error = code;
    return handle;
}

void CubismMotionHandle::queue_event(const StringName &name, const Variant &value) {
    if (name != StringName("finished") && is_finished()) return;
    if (name != StringName("finished") && events.size() >= 100000) {
        events.clear();
        error = ERR_OUT_OF_MEMORY;
        finish(FAILED);
        return;
    }
    events.push_back({name, value});
    if (!dispatch_pending) { dispatch_pending = true; call_deferred("_dispatch_events"); }
}

void CubismMotionHandle::finish(FinishReason value) {
    if (is_finished()) return;
    state = FINISHED;
    reason = value;
    if (value == FAILED && error == OK) error = godot::FAILED;
    queue_event("finished", int(value));
}

void CubismMotionHandle::dispatch_events() {
    dispatch_pending = false;
    std::vector<Event> pending;
    pending.swap(events);
    const uint64_t id = get_instance_id();
    for (const Event &event : pending) {
        auto *handle = Object::cast_to<CubismMotionHandle>(ObjectDB::get_instance(id));
        if (!handle) return;
        handle->emit_signal(event.name, event.value);
    }
}
