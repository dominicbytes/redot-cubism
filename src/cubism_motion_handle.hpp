// SPDX-License-Identifier: MIT
#ifndef CUBISM_MOTION_HANDLE_HPP
#define CUBISM_MOTION_HANDLE_HPP
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <vector>
using namespace godot;

class CubismMotionPriority : public RefCounted {
    GDCLASS(CubismMotionPriority, RefCounted)
public:
    enum Priority { NONE, IDLE, NORMAL, FORCE };
protected:
    static void _bind_methods() {
        BIND_ENUM_CONSTANT(NONE); BIND_ENUM_CONSTANT(IDLE);
        BIND_ENUM_CONSTANT(NORMAL); BIND_ENUM_CONSTANT(FORCE);
    }
};

class CubismMotionHandle : public RefCounted {
    GDCLASS(CubismMotionHandle, RefCounted)
    friend class CubismAnimator;
public:
    enum State { PLAYING, FINISHED };
    enum FinishReason { NONE, COMPLETED, STOPPED, INTERRUPTED, FAILED, UNLOADED, RELOADED, MODEL_DISPOSED };
private:
    StringName motion_id;
    State state = FINISHED;
    FinishReason reason = FAILED;
    Error error = godot::FAILED;
    int64_t loop_count = 0;
    double elapsed_seconds = 0.0;
    struct Event { StringName name; Variant value; };
    std::vector<Event> events;
    bool dispatch_pending = false;
    void queue_event(const StringName &name, const Variant &value);
    void dispatch_events();
    void finish(FinishReason value);
protected:
    static void _bind_methods();
public:
    static Ref<CubismMotionHandle> rejected(const StringName &id, Error code);
    int64_t get_id() const { return get_instance_id(); }
    StringName get_motion_id() const { return motion_id; }
    State get_state() const { return state; }
    bool is_finished() const { return state == FINISHED; }
    FinishReason get_reason() const { return reason; }
    Error get_error() const { return error; }
    int64_t get_loop_count() const { return loop_count; }
    double get_elapsed_seconds() const { return elapsed_seconds; }
};
VARIANT_ENUM_CAST(CubismMotionPriority::Priority);
VARIANT_ENUM_CAST(CubismMotionHandle::State);
VARIANT_ENUM_CAST(CubismMotionHandle::FinishReason);
#endif
