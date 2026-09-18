// SPDX-License-Identifier: MIT
#include "cubism_speech_handle.hpp"

void CubismSpeechHandle::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_finished"), &CubismSpeechHandle::is_finished);
    ClassDB::bind_method(D_METHOD("get_reason"), &CubismSpeechHandle::get_reason);
    ClassDB::bind_method(D_METHOD("get_error"), &CubismSpeechHandle::get_error);
    ClassDB::bind_method(D_METHOD("get_elapsed_seconds"), &CubismSpeechHandle::get_elapsed_seconds);
    ClassDB::bind_method(D_METHOD("_dispatch_finished"), &CubismSpeechHandle::dispatch_finished);
    ADD_SIGNAL(MethodInfo("finished", PropertyInfo(Variant::INT, "reason")));
    BIND_ENUM_CONSTANT(NONE); BIND_ENUM_CONSTANT(COMPLETED); BIND_ENUM_CONSTANT(STOPPED);
    BIND_ENUM_CONSTANT(INTERRUPTED); BIND_ENUM_CONSTANT(HIDDEN); BIND_ENUM_CONSTANT(UNLOADED);
    BIND_ENUM_CONSTANT(MODEL_DISPOSED); BIND_ENUM_CONSTANT(CONTROLLER_DISPOSED); BIND_ENUM_CONSTANT(FAILED);
}

void CubismSpeechHandle::finish(FinishReason value, Error code) {
    if (terminal) return;
    terminal = true;
    reason = value;
    error = code;
    finish_pending = true;
    call_deferred("_dispatch_finished");
}

void CubismSpeechHandle::dispatch_finished() {
    if (!finish_pending) return;
    finish_pending = false;
    emit_signal("finished", int(reason));
}
