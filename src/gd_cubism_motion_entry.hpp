// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
#ifndef GD_CUBISM_MOTION_ENTRY_H
#define GD_CUBISM_MOTION_ENTRY_H
// ----------------------------------------------------------------- include(s)
#include <godot_cpp/core/property_info.hpp>
#include <godot_cpp/classes/resource.hpp>

#include <CubismFramework.hpp>
#include <Motion/CubismExpressionMotionManager.hpp>
#include <Motion/CubismMotionQueueEntry.hpp>


// ------------------------------------------------------------------ define(s)
// --------------------------------------------------------------- namespace(s)
using namespace godot;


// -------------------------------------------------------------------- enum(s)
// ------------------------------------------------------------------- const(s)
// ------------------------------------------------------------------ static(s)
// ----------------------------------------------------------- class:forward(s)
class InternalCubismUserModel;
class GDCubismUserModel;


// ------------------------------------------------------------------- class(s)
class GDCubismMotionQueueEntryHandle : public Resource {
    GDCLASS(GDCubismMotionQueueEntryHandle, Resource)
    friend GDCubismUserModel;

public:
    enum HandleError {
        OK = godot::Error::OK,
        FAILED = godot::Error::FAILED
    };
    enum FinishReason {
        PLAYING,
        COMPLETED,
        STOPPED,
        INTERRUPTED,
        UNLOADED,
        RELOADED,
        MODEL_DESTROYED,
        PLAYBACK_ERROR
    };

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("get_error"), &GDCubismMotionQueueEntryHandle::get_error);
        ADD_PROPERTY(PropertyInfo(Variant::INT, "error"), "", "get_error");
        ClassDB::bind_method(D_METHOD("is_finished"), &GDCubismMotionQueueEntryHandle::is_finished);
        ClassDB::bind_method(D_METHOD("get_reason"), &GDCubismMotionQueueEntryHandle::get_reason);
        ClassDB::bind_method(D_METHOD("_emit_finished"), &GDCubismMotionQueueEntryHandle::emit_finished);
        ADD_SIGNAL(MethodInfo("finished", PropertyInfo(Variant::INT, "reason")));

        BIND_ENUM_CONSTANT(OK);
        BIND_ENUM_CONSTANT(FAILED);
        BIND_ENUM_CONSTANT(PLAYING);
        BIND_ENUM_CONSTANT(COMPLETED);
        BIND_ENUM_CONSTANT(STOPPED);
        BIND_ENUM_CONSTANT(INTERRUPTED);
        BIND_ENUM_CONSTANT(UNLOADED);
        BIND_ENUM_CONSTANT(RELOADED);
        BIND_ENUM_CONSTANT(MODEL_DESTROYED);
        BIND_ENUM_CONSTANT(PLAYBACK_ERROR);
    }

public:
    HandleError get_error() const {
        return _error;
    }
    bool is_finished() const { return _reason != PLAYING; }
    FinishReason get_reason() const { return _reason; }

private:
    Csm::CubismMotionQueueEntryHandle _handle = Csm::InvalidMotionQueueEntryHandleValue;
    HandleError _error = FAILED;
    FinishReason _reason = PLAYBACK_ERROR;
    bool _emitted = false;
    void finish(FinishReason reason, bool notify = true) {
        if (is_finished()) return;
        _handle = Csm::InvalidMotionQueueEntryHandleValue;
        _reason = reason;
        if (notify) call_deferred("_emit_finished");
    }
    void emit_finished() {
        if (_emitted || !is_finished()) return;
        _emitted = true;
        emit_signal("finished", _reason);
    }
};

VARIANT_ENUM_CAST(GDCubismMotionQueueEntryHandle::HandleError);
VARIANT_ENUM_CAST(GDCubismMotionQueueEntryHandle::FinishReason);


class GDCubismMotionEntry : public godot::Resource {
    GDCLASS(GDCubismMotionEntry, godot::Resource)
    friend GDCubismUserModel;

protected:
    static void _bind_methods() {}

};


// ------------------------------------------------------------------ method(s)


#endif // GD_CUBISM_MOTION_ENTRY_H
