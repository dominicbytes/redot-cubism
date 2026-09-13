// SPDX-License-Identifier: MIT
#ifndef CUBISM_MODEL_2D_HPP
#define CUBISM_MODEL_2D_HPP

#include "gd_cubism_user_model.hpp"
#include "cubism_motion_handle.hpp"
#include "cubism_speech_handle.hpp"
#include <map>

// Preferred API. The internal legacy runtime retains native allocation and
// renderer ownership; it is neither exposed nor serialized as a scene child.
class CubismModel2D : public godot::Node2D {
    GDCLASS(CubismModel2D, godot::Node2D)
    friend class CubismCharacterController;
    friend class CubismEffect;
    friend class GDCubismUserModel;
    friend class InternalCubismUserModel;

public:
    enum PlaybackProcessMode { IDLE, PHYSICS, MANUAL };
    enum ModelState { UNLOADED, LOADING, READY, ERROR, DISPOSING, DISPOSED };
    enum MaskQuality { MASK_LOW, MASK_MEDIUM, MASK_HIGH, MASK_CUSTOM };
    enum ParameterLayer {
        LAYER_BASE = GDCubismUserModel::WRITE_BASE,
        LAYER_MOTION = GDCubismUserModel::WRITE_MOTION,
        LAYER_EXPRESSION = GDCubismUserModel::WRITE_EXPRESSION,
        LAYER_EFFECT = GDCubismUserModel::WRITE_EFFECT,
        LAYER_PHYSICS = GDCubismUserModel::WRITE_PHYSICS,
        LAYER_POSE = GDCubismUserModel::WRITE_POSE,
        LAYER_POST_EFFECT = GDCubismUserModel::WRITE_POST_EFFECT
    };

private:
    struct CustomEffect { uint64_t id; uint64_t revision; int64_t priority; String name; };
    std::vector<CustomEffect> custom_effects;
    uint64_t custom_effect_generation = 0;
    uint64_t active_custom_effect = 0;
    uint64_t active_custom_effect_revision = 0;
    void begin_custom_effects();
    void apply_custom_effects(double delta);
    Error write_custom_effect(uint64_t effect, uint64_t revision, const StringName &id, double value, double weight, int operation);
    GDCubismUserModel *runtime = nullptr;
    Ref<CubismModelResource> model;
    PlaybackProcessMode playback_process_mode = IDLE;
    bool paused = false;
    MaskQuality mask_quality = MASK_MEDIUM;
    int custom_mask_limit = 1024;
    void update_mask_limit();
    bool load_requested = false;
    bool autoplay = false;
    StringName default_motion;
    StringName default_expression;
    bool autoplay_started = false;
    bool motion_requested = false;
    bool expression_requested = false;
    StringName selected_expression;
    Vector2 requested_look_target;
    double requested_look_weight = 1.0;
    bool requested_look_active = false;
    bool controller_state_available(uint64_t owner) const;
    void start_autoplay(uint64_t expected_generation);
    uint64_t generation = 0;
    uint64_t controller_clock_id = 0;
    PlaybackProcessMode before_controller_mode = IDLE;
    float before_controller_speed = 1;
    std::map<int64_t, Ref<CubismMotionHandle>> motions;
    void motion_started(const Ref<CubismMotionHandle> &handle);
    void motion_event(const String &value, int64_t id);
    void motion_looped(int64_t count, int64_t id);
    void motion_finished(int reason, int64_t id);
    void deferred_stop_motion(double fade_seconds, uint64_t expected_generation);
    void deferred_clear_expression(double fade_seconds, uint64_t expected_generation);
    void expression_changed(const StringName &id, uint64_t expected_generation);
    void emit_load_started(uint64_t expected_generation);
    void on_model_ready();
    void on_model_failed(const Dictionary &error);
    void step(double delta, bool controller = false);
    void notify_controller(CubismSpeechHandle::FinishReason reason);
    Vector2 hit_target;
    bool hit_target_active = false;
    bool hit_refresh_pending = false;
    bool hit_reset = false;
    uint64_t hit_revision = 0;
    PackedStringArray hovered_hit_areas;
    void queue_hit_refresh();
    void refresh_hit_areas();
    void reset_hit_tracking();
    int parameter_index(const StringName &id) const;
    Error queue_parameter(const StringName &id, double value, double weight, int operation, ParameterLayer layer);

protected:
    static void _bind_methods();
    void _notification(int what);

public:
    CubismModel2D();
    void set_mask_quality(MaskQuality value);
    MaskQuality get_mask_quality() const { return mask_quality; }
    void set_custom_mask_limit(int64_t value);
    int64_t get_custom_mask_limit() const { return custom_mask_limit; }
    void set_model(const Ref<CubismModelResource> &resource) { load_model(resource); }
    Ref<CubismModelResource> get_model() const { return model; }
    void set_autoplay(bool value) { autoplay = value; }
    bool get_autoplay() const { return autoplay; }
    void set_default_motion(const StringName &id) { default_motion = id; }
    StringName get_default_motion() const { return default_motion; }
    void set_default_expression(const StringName &id) { default_expression = id; }
    StringName get_default_expression() const { return default_expression; }
    Error load_model(const Ref<CubismModelResource> &resource);
    void unload_model();
    Error reload_model() { return load_model(model); }
    bool is_ready() const { return runtime->is_initialized(); }
    ModelState get_model_state() const { return ModelState(runtime->get_model_state()); }
    String get_last_error() const;
    void set_playback_process_mode(PlaybackProcessMode mode);
    PlaybackProcessMode get_playback_process_mode() const { return playback_process_mode; }
    void set_speed_scale(float speed) { runtime->set_speed_scale(speed); }
    float get_speed_scale() const { return runtime->get_speed_scale(); }
    void set_paused(bool value) { paused = value; }
    bool get_paused() const { return paused; }
    void set_enable_physics(bool value) { runtime->set_physics_evaluate(value); }
    bool get_enable_physics() const { return runtime->get_physics_evaluate(); }
    void set_enable_pose(bool value) { runtime->set_pose_update(value); }
    bool get_enable_pose() const { return runtime->get_pose_update(); }
    void set_enable_eye_blink(bool value);
    bool get_enable_eye_blink() const;
    void set_enable_breath(bool value);
    bool get_enable_breath() const;
    void set_deterministic_seed(int64_t value);
    int64_t get_deterministic_seed() const;
    void set_enable_look_target(bool value);
    bool get_enable_look_target() const;
    void set_look_target(const Vector2 &local_target, double weight = 1.0);
    void clear_look_target();
    PackedStringArray get_hit_area_names() const;
    bool hit_test(const StringName &hit_area, const Vector2 &local_point) const;
    void set_hit_test_target(const Vector2 &local_point);
    void clear_hit_test_target();
    void set_enable_lip_sync(bool value);
    bool get_enable_lip_sync() const;
    Error attach_lip_sync(uint64_t component);
    void detach_lip_sync(uint64_t component);
    void advance(double delta);
    uint64_t get_runtime_generation() const { return generation; }
    Error claim_controller_clock(uint64_t controller);
    void release_controller_clock(uint64_t controller);
    bool advance_controller_clock(uint64_t controller, double delta);
    Ref<CubismMotionHandle> play_motion(const StringName &id, CubismMotionPriority::Priority priority = CubismMotionPriority::NORMAL, bool loop = false, double speed = 1.0);
    Ref<CubismMotionHandle> play_motion_from_group(const StringName &group, int index, CubismMotionPriority::Priority priority = CubismMotionPriority::NORMAL, bool loop = false, double speed = 1.0);
    void stop_motion(double fade_seconds = -1.0);
    PackedStringArray get_motion_ids() const;
    Error set_expression(const StringName &id, double fade_seconds = -1.0);
    void clear_expression(double fade_seconds = -1.0);
    PackedStringArray get_expression_ids() const;
    bool has_parameter(const StringName &id) const { return parameter_index(id) >= 0; }
    double get_parameter_value(const StringName &id) const;
    Error set_parameter_value(const StringName &id, double value, double weight = 1.0, ParameterLayer layer = LAYER_POST_EFFECT) { return queue_parameter(id, value, weight, 0, layer); }
    Error add_parameter_value(const StringName &id, double value, double weight = 1.0, ParameterLayer layer = LAYER_POST_EFFECT) { return queue_parameter(id, value, weight, 1, layer); }
    Error multiply_parameter_value(const StringName &id, double value, double weight = 1.0, ParameterLayer layer = LAYER_POST_EFFECT) { return queue_parameter(id, value, weight, 2, layer); }
    Error set_part_opacity(const StringName &id, double opacity);
    PackedStringArray get_parameter_ids() const;
    PackedStringArray get_part_ids() const;
    Dictionary get_canvas_info() const { return is_ready() ? runtime->get_canvas_info() : Dictionary(); }
};

VARIANT_ENUM_CAST(CubismModel2D::PlaybackProcessMode);
VARIANT_ENUM_CAST(CubismModel2D::ModelState);
VARIANT_ENUM_CAST(CubismModel2D::ParameterLayer);
VARIANT_ENUM_CAST(CubismModel2D::MaskQuality);
#endif
