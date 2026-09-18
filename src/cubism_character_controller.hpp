// SPDX-License-Identifier: MIT
#ifndef CUBISM_CHARACTER_CONTROLLER_HPP
#define CUBISM_CHARACTER_CONTROLLER_HPP
#include "cubism_model_2d.hpp"
#include "cubism_lip_sync.hpp"
#include "cubism_speech_handle.hpp"
#include <godot_cpp/classes/audio_stream_player.hpp>
#include <godot_cpp/classes/audio_stream.hpp>

class CubismCharacterController : public Node {
    GDCLASS(CubismCharacterController, Node)
    friend class CubismModel2D;
    uint64_t target_id = 0;
    uint64_t generation = 0;
    AudioStreamPlayer *voice = nullptr;
    CubismLipSync *lip = nullptr;
    Ref<CubismSpeechHandle> speech;
    Ref<CubismMotionHandle> motion;
    Ref<CubismMotionHandle> idle;
    StringName idle_motion;
    bool auto_return_to_idle = false;
    enum Transition { NO_TRANSITION, SHOWING, HIDING };
    Transition transition = NO_TRANSITION;
    double transition_seconds = 0.2;
    double transition_elapsed = 0;
    double transition_from = 0;
    double transition_alpha = 1;
    uint64_t transition_generation = 0;
    StringName requested_motion;
    StringName voice_bus = "Master";
    bool manual_process = false;
    bool manual_audio_clock = false;
    bool paused = false;
    bool busy = false;
    bool has_audio = false;
    bool audio_done = false;
    bool driver_done = false;
    bool submitted_done = false;
    bool motion_started = false;
    double submitted_position = 0;
    double audio_position = 0;
    double voice_length = 0;
    double cue_offset = 0;
    double start_at = 0;
    double model_time = 0;
    double preroll = 0;
    double fade_remaining = 0;
    double fade_duration = 0;
    double sync_error = 0;
    void tick(double delta);
    Error start_idle();
    void cancel_transition();
    Error change_visibility(bool show, const StringName &kind);
    void tick_transition(double delta);
    Error advance_model_to(double position);
    Error start_motion();
    void audio_finished() { driver_done = true; }
    void cleanup();
    void model_unavailable(CubismModel2D *model, CubismSpeechHandle::FinishReason reason);
    void terminate(CubismSpeechHandle::FinishReason reason, Error error = OK, double fade = 0);
    Ref<CubismSpeechHandle> begin(const Ref<AudioStream> &stream, const StringName &motion_id, const StringName &expression_id, const Ref<CubismLipSyncProfile> &profile);
protected:
    static void _bind_methods();
    void _notification(int what);
public:
    CubismCharacterController();
    Error set_target_model(CubismModel2D *value);
    CubismModel2D *get_target_model() const;
    Error set_voice_bus(const StringName &value);
    StringName get_voice_bus() const { return voice_bus; }
    Error set_manual_process(bool value);
    bool get_manual_process() const { return manual_process; }
    Error set_manual_audio_clock(bool value);
    bool get_manual_audio_clock() const { return manual_audio_clock; }
    Error set_cue_offset_seconds(double value);
    double get_cue_offset_seconds() const { return cue_offset; }
    void set_paused(bool value);
    bool get_paused() const { return paused; }
    Ref<CubismSpeechHandle> perform(const StringName &motion_id, const StringName &expression_id = StringName());
    Ref<CubismSpeechHandle> speak(const Ref<AudioStream> &stream, const StringName &motion_id = StringName(), const StringName &expression_id = StringName(), const Ref<CubismLipSyncProfile> &profile = Ref<CubismLipSyncProfile>());
    void stop_speaking(double fade_seconds = 0.1);
    void advance(double delta);
    Error submit_audio_clock(double position_seconds, bool finished = false);
    double get_audio_position() const { return audio_position; }
    double get_model_time() const { return model_time; }
    double get_sync_error() const { return sync_error; }
    Ref<CubismMotionHandle> get_motion_handle() const { return motion; }
    bool is_speaking() const { return speech.is_valid() && !speech->is_finished(); }
    void set_idle_motion(const StringName &value) { idle_motion = value; }
    StringName get_idle_motion() const { return idle_motion; }
    void set_auto_return_to_idle(bool value) { auto_return_to_idle = value; }
    bool get_auto_return_to_idle() const { return auto_return_to_idle; }
    Error return_to_idle();
    bool is_idle() const { return idle.is_valid() && !idle->is_finished(); }
    Error set_transition_seconds(double value);
    double get_transition_seconds() const { return transition_seconds; }
    Error show_character(const StringName &kind = "none") { return change_visibility(true, kind); }
    Error hide_character(const StringName &kind = "none") { return change_visibility(false, kind); }
    Error look_at_screen_position(const Vector2 &position);
    Dictionary capture_state() const;
    Error restore_state(const Dictionary &state);
};
#endif
