// SPDX-License-Identifier: MIT
#include "cubism_character_controller.hpp"
#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <algorithm>
#include <cmath>

void CubismCharacterController::_bind_methods() {
#define CUE_PROPERTY(type, name) \
    ClassDB::bind_method(D_METHOD("set_" #name, "value"), &CubismCharacterController::set_##name); \
    ClassDB::bind_method(D_METHOD("get_" #name), &CubismCharacterController::get_##name); \
    ADD_PROPERTY(PropertyInfo(type, #name), "set_" #name, "get_" #name);
    ClassDB::bind_method(D_METHOD("set_target_model", "value"), &CubismCharacterController::set_target_model);
    ClassDB::bind_method(D_METHOD("get_target_model"), &CubismCharacterController::get_target_model);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "target_model", PROPERTY_HINT_NODE_TYPE, "CubismModel2D"), "set_target_model", "get_target_model");
    CUE_PROPERTY(Variant::STRING_NAME, voice_bus)
    CUE_PROPERTY(Variant::BOOL, manual_process)
    CUE_PROPERTY(Variant::BOOL, manual_audio_clock)
    CUE_PROPERTY(Variant::BOOL, paused)
    CUE_PROPERTY(Variant::FLOAT, cue_offset_seconds)
#undef CUE_PROPERTY
    ClassDB::bind_method(D_METHOD("perform", "motion_id", "expression_id"), &CubismCharacterController::perform, DEFVAL(StringName()));
    ClassDB::bind_method(D_METHOD("speak", "stream", "motion_id", "expression_id", "profile"), &CubismCharacterController::speak, DEFVAL(StringName()), DEFVAL(StringName()), DEFVAL(Ref<CubismLipSyncProfile>()));
    ClassDB::bind_method(D_METHOD("stop_speaking", "fade_seconds"), &CubismCharacterController::stop_speaking, DEFVAL(0.1));
    ClassDB::bind_method(D_METHOD("advance", "delta"), &CubismCharacterController::advance);
    ClassDB::bind_method(D_METHOD("submit_audio_clock", "position_seconds", "finished"), &CubismCharacterController::submit_audio_clock, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("get_audio_position"), &CubismCharacterController::get_audio_position);
    ClassDB::bind_method(D_METHOD("get_model_time"), &CubismCharacterController::get_model_time);
    ClassDB::bind_method(D_METHOD("get_sync_error"), &CubismCharacterController::get_sync_error);
    ClassDB::bind_method(D_METHOD("get_motion_handle"), &CubismCharacterController::get_motion_handle);
    ClassDB::bind_method(D_METHOD("is_speaking"), &CubismCharacterController::is_speaking);
}

CubismCharacterController::CubismCharacterController() {
    voice = memnew(AudioStreamPlayer);
    voice->set_name("Voice");
    add_child(voice, false, Node::INTERNAL_MODE_BACK);
    voice->connect("finished", callable_mp(this, &CubismCharacterController::audio_finished));
    lip = memnew(CubismLipSync);
    lip->set_name("LipSync");
    lip->set_enabled(false);
    add_child(lip, false, Node::INTERNAL_MODE_BACK);
    set_process_internal(true);
}

CubismModel2D *CubismCharacterController::get_target_model() const {
    return Object::cast_to<CubismModel2D>(ObjectDB::get_instance(target_id));
}

Error CubismCharacterController::set_target_model(CubismModel2D *value) {
    if (busy) return ERR_BUSY;
    const uint64_t next = value ? uint64_t(value->get_instance_id()) : 0;
    if (next == target_id) return OK;
    terminate(CubismSpeechHandle::INTERRUPTED);
    target_id = next;
    return OK;
}

Error CubismCharacterController::set_voice_bus(const StringName &value) {
    if (speech.is_valid()) return ERR_BUSY;
    voice_bus = value;
    return OK;
}

Error CubismCharacterController::set_manual_process(bool value) {
    if (speech.is_valid()) return ERR_BUSY;
    manual_process = value;
    set_process_internal(!value);
    return OK;
}

Error CubismCharacterController::set_manual_audio_clock(bool value) {
    if (speech.is_valid()) return ERR_BUSY;
    manual_audio_clock = value;
    return OK;
}

Error CubismCharacterController::set_cue_offset_seconds(double value) {
    if (speech.is_valid()) return ERR_BUSY;
    // Negative offsets require synchronous pre-roll, bounded to one minute.
    if (!std::isfinite(value) || value < -60.0 || value > 60.0) return ERR_INVALID_PARAMETER;
    cue_offset = value;
    return OK;
}

void CubismCharacterController::set_paused(bool value) {
    paused = value;
    if (speech.is_valid() && has_audio && !manual_audio_clock) {
        auto *target = get_target_model();
        voice->set_stream_paused(paused || !can_process() || (target && (target->get_paused() || !target->can_process())));
    }
}

void CubismCharacterController::_notification(int what) {
    if (what == NOTIFICATION_INTERNAL_PROCESS) tick(get_process_delta_time());
    else if (what == NOTIFICATION_PAUSED || what == NOTIFICATION_UNPAUSED || what == NOTIFICATION_DISABLED || what == NOTIFICATION_ENABLED) set_paused(paused);
    else if (what == NOTIFICATION_EXIT_TREE) terminate(CubismSpeechHandle::UNLOADED);
    else if (what == NOTIFICATION_PREDELETE) {
        if (busy) { cancel_free(); queue_free(); }
        else terminate(CubismSpeechHandle::CONTROLLER_DISPOSED);
    }
}

void CubismCharacterController::cleanup() {
    voice->stop();
    voice->set_stream(Ref<AudioStream>());
    voice->set_volume_db(0);
    lip->set_enabled(false);
    lip->set_target_model(nullptr);
    if (auto *target = get_target_model()) target->release_controller_clock(get_instance_id());
    speech.unref();
    fade_remaining = 0;
}

void CubismCharacterController::model_unavailable(CubismModel2D *model, CubismSpeechHandle::FinishReason reason) {
    if (model != get_target_model() || speech.is_null()) return;
    const Ref<CubismSpeechHandle> ending = speech;
    // Teardown/reload itself supplies the native motion's terminal reason.
    // Hiding leaves the model alive, so stop its remaining motion explicitly.
    if (reason == CubismSpeechHandle::HIDDEN) model->stop_motion(0);
    cleanup();
    ending->finish(reason);
}

void CubismCharacterController::terminate(CubismSpeechHandle::FinishReason reason, Error error, double fade) {
    if (speech.is_null()) return;
    const Ref<CubismSpeechHandle> ending = speech;
    // Cancelling a delayed cue must not start its pending motion during the fade.
    motion_started = true;
    if (auto *target = get_target_model()) {
        if (target->get_runtime_generation() == generation) target->stop_motion(fade);
    }
    if (fade > 0 && !ending->is_finished()) {
        fade_duration = fade_remaining = fade;
    } else cleanup();
    ending->finish(reason, error);
}

Ref<CubismSpeechHandle> CubismCharacterController::perform(const StringName &motion_id, const StringName &expression_id) {
    return begin(Ref<AudioStream>(), motion_id, expression_id, Ref<CubismLipSyncProfile>());
}

Ref<CubismSpeechHandle> CubismCharacterController::speak(const Ref<AudioStream> &stream, const StringName &motion_id, const StringName &expression_id, const Ref<CubismLipSyncProfile> &profile) {
    if (stream.is_null()) {
        Ref<CubismSpeechHandle> rejected; rejected.instantiate(); rejected->error = ERR_INVALID_PARAMETER;
        return rejected;
    }
    return begin(stream, motion_id, expression_id, profile);
}

Ref<CubismSpeechHandle> CubismCharacterController::begin(const Ref<AudioStream> &stream, const StringName &motion_id, const StringName &expression_id, const Ref<CubismLipSyncProfile> &profile) {
    Ref<CubismSpeechHandle> result; result.instantiate();
    auto reject = [&](Error error) { result->error = error; return result; };
    if (busy) return reject(ERR_BUSY);
    auto *target = get_target_model();
    if (!is_inside_tree() || !target || !target->is_inside_tree() || !target->is_ready()) return reject(ERR_UNCONFIGURED);
    if (target->is_queued_for_deletion() || !target->is_visible_in_tree()) return reject(ERR_UNAVAILABLE);
    if (motion_id != StringName() && !target->get_motion_ids().has(String(motion_id))) return reject(ERR_DOES_NOT_EXIST);
    if (expression_id != StringName() && !target->get_expression_ids().has(String(expression_id))) return reject(ERR_DOES_NOT_EXIST);
    const double length = stream.is_valid() ? stream->get_length() : 0;
    if (stream.is_valid() && (!std::isfinite(length) || length <= 0)) return reject(ERR_INVALID_DATA);
    if (stream.is_valid() && !manual_audio_clock && AudioServer::get_singleton()->get_bus_index(voice_bus) < 0) return reject(ERR_DOES_NOT_EXIST);
    terminate(CubismSpeechHandle::INTERRUPTED);
    Error error = target->claim_controller_clock(get_instance_id());
    if (error != OK) return reject(error);
    if (profile.is_valid() && stream.is_valid()) {
        error = lip->set_target_model(target);
        if (error != OK) { target->release_controller_clock(get_instance_id()); return reject(error); }
    }
    speech = result;
    result->terminal = false; result->reason = CubismSpeechHandle::NONE; result->error = OK;
    generation = target->get_runtime_generation();
    requested_motion = motion_id;
    motion.unref(); motion_started = false;
    has_audio = stream.is_valid(); audio_done = !has_audio; driver_done = false; submitted_done = false;
    voice_length = length; audio_position = 0; submitted_position = 0; model_time = 0; sync_error = 0;
    // Offset belongs to voiced synchronization. perform starts the same motion at zero.
    start_at = has_audio && motion_id != StringName() ? std::max(0.0, cue_offset) : 0;
    preroll = has_audio && motion_id != StringName() ? std::max(0.0, -cue_offset) : 0;
    target->stop_motion(0);
    if (expression_id != StringName()) error = target->set_expression(expression_id);
    if (error == OK && start_at == 0) error = start_motion();
    busy = true;
    if (error == OK && preroll > 0) error = advance_model_to(preroll);
    busy = false;
    if (error != OK) { terminate(CubismSpeechHandle::FAILED, error); return result; }
    lip->set_profile(profile);
    lip->set_input_mode(CubismLipSync::AUDIO_BUS_PEAK);
    lip->set_audio_bus(voice_bus);
    lip->set_enabled(has_audio && profile.is_valid() && !manual_audio_clock);
    if (has_audio && !manual_audio_clock) {
        voice->set_bus(voice_bus);
        voice->set_stream(stream);
        voice->play();
        if (!voice->has_stream_playback()) { terminate(CubismSpeechHandle::FAILED, ERR_CANT_OPEN); return result; }
        set_paused(paused);
    }
    if (!has_audio && requested_motion == StringName()) terminate(CubismSpeechHandle::COMPLETED);
    return result;
}

Error CubismCharacterController::start_motion() {
    motion_started = true;
    if (requested_motion == StringName()) return OK;
    motion = get_target_model()->play_motion(requested_motion, CubismMotionPriority::FORCE, false, 1);
    return motion->get_error();
}

Error CubismCharacterController::advance_model_to(double position) {
    auto *target = get_target_model();
    if (!target || !std::isfinite(position) || position < model_time) return ERR_INVALID_PARAMETER;
    // Bounded replay protects SDK deltas and avoids unbounded work after a clock jump.
    if (position - model_time > 60) return ERR_UNAVAILABLE;
    while (position - model_time > 1e-9) {
        if (!motion_started && model_time + 1e-9 >= start_at) {
            const Error error = start_motion();
            if (error != OK) return error;
        }
        double next = std::min(position, model_time + 0.1);
        if (!motion_started) next = std::min(next, start_at);
        if (!target->advance_controller_clock(get_instance_id(), next - model_time)) return ERR_UNAVAILABLE;
        model_time = next;
        if (speech.is_null() || !is_inside_tree() || is_queued_for_deletion() || target->is_queued_for_deletion() || target->get_runtime_generation() != generation) return ERR_UNAVAILABLE;
    }
    return OK;
}

void CubismCharacterController::advance(double delta) { if (manual_process) tick(delta); }

Error CubismCharacterController::submit_audio_clock(double position_seconds, bool finished) {
    if (!manual_audio_clock || !has_audio || speech.is_null()) return ERR_UNCONFIGURED;
    if (!std::isfinite(position_seconds) || position_seconds < 0 || position_seconds > voice_length) return ERR_INVALID_PARAMETER;
    submitted_position = position_seconds;
    submitted_done = finished;
    return OK;
}

void CubismCharacterController::stop_speaking(double fade_seconds) {
    if (busy || !std::isfinite(fade_seconds) || fade_seconds < 0 || fade_seconds > 60) return;
    terminate(CubismSpeechHandle::STOPPED, OK, fade_seconds);
}

void CubismCharacterController::tick(double delta) {
    if (busy || speech.is_null() || !is_inside_tree() || !can_process()) return;
    if (!std::isfinite(delta) || delta < 0 || delta > 60) { terminate(CubismSpeechHandle::FAILED, ERR_INVALID_PARAMETER); return; }
    auto *target = get_target_model();
    if (!target || target->is_queued_for_deletion()) { terminate(CubismSpeechHandle::MODEL_DISPOSED); return; }
    if (!target->is_ready() || !target->is_inside_tree() || target->get_runtime_generation() != generation) { terminate(CubismSpeechHandle::UNLOADED); return; }
    if (!target->is_visible_in_tree()) { terminate(CubismSpeechHandle::HIDDEN); return; }
    set_paused(paused);
    if (paused || target->get_paused() || !target->can_process()) return;
    if (target->get_speed_scale() != 1.0) { terminate(CubismSpeechHandle::FAILED, ERR_UNAVAILABLE); return; }
    if (fade_remaining > 0) {
        const double fade_step = std::min(delta, fade_remaining);
        fade_remaining -= fade_step;
        if (fade_remaining > 0) voice->set_volume_db(float(20.0 * std::log10(fade_remaining / fade_duration)));
        busy = true;
        const Error error = advance_model_to(model_time + fade_step);
        busy = false;
        if (error != OK || fade_remaining == 0) cleanup();
        return;
    }
    if (motion.is_valid() && motion->is_finished() && motion->get_reason() != CubismMotionHandle::COMPLETED) {
        terminate(CubismSpeechHandle::INTERRUPTED); return;
    }
    double destination = model_time + delta;
    if (has_audio && !audio_done) {
        double estimate;
        if (manual_audio_clock) {
            estimate = submitted_position;
            audio_done = submitted_done;
        } else if (driver_done) {
            // The player has already discarded its clock. Drain the audible tail
            // from the last estimate to the known prerecorded stream duration.
            estimate = std::min(voice_length, audio_position + delta);
            audio_done = estimate >= voice_length;
        } else {
            auto *server = AudioServer::get_singleton();
            const double position = voice->get_playback_position();
            // Read activity AFTER the clock: the mixer can discard playback
            // between these calls, causing a subsequent clock read to return 0.
            if (!voice->is_playing() && !voice->get_stream_paused()) {
                driver_done = true;
                estimate = std::min(voice_length, audio_position + delta);
            } else {
                estimate = std::clamp(position + server->get_time_since_last_mix() - server->get_output_latency(), 0.0, voice_length);
            }
            audio_done = estimate >= voice_length;
        }
        if (!std::isfinite(estimate) || estimate < audio_position - 0.05) { terminate(CubismSpeechHandle::FAILED, ERR_UNAVAILABLE); return; }
        audio_position = std::max(audio_position, estimate);
        destination = audio_position + preroll;
        if (audio_done) lip->set_enabled(false);
    }
    busy = true;
    const Error error = advance_model_to(destination);
    busy = false;
    if (error != OK) { terminate(CubismSpeechHandle::FAILED, error); return; }
    speech->elapsed_seconds = std::max(0.0, model_time - preroll);
    sync_error = has_audio && !audio_done ? model_time - preroll - audio_position : 0;
    if (audio_done && motion_started && (motion.is_null() || motion->is_finished())) terminate(CubismSpeechHandle::COMPLETED);
}
