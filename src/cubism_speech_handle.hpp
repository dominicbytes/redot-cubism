// SPDX-License-Identifier: MIT
#ifndef CUBISM_SPEECH_HANDLE_HPP
#define CUBISM_SPEECH_HANDLE_HPP
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
using namespace godot;

class CubismSpeechHandle : public RefCounted {
    GDCLASS(CubismSpeechHandle, RefCounted)
    friend class CubismCharacterController;
public:
    enum FinishReason { NONE, COMPLETED, STOPPED, INTERRUPTED, HIDDEN, UNLOADED, MODEL_DISPOSED, CONTROLLER_DISPOSED, FAILED };
private:
    bool terminal = true;
    bool finish_pending = false;
    FinishReason reason = FAILED;
    Error error = godot::FAILED;
    double elapsed_seconds = 0;
    void finish(FinishReason value, Error code = OK);
    void dispatch_finished();
protected:
    static void _bind_methods();
public:
    bool is_finished() const { return terminal; }
    FinishReason get_reason() const { return reason; }
    Error get_error() const { return error; }
    double get_elapsed_seconds() const { return elapsed_seconds; }
};
VARIANT_ENUM_CAST(CubismSpeechHandle::FinishReason);
#endif
