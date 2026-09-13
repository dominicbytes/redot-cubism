// SPDX-License-Identifier: MIT
#ifndef CUBISM_MODEL_2D_HPP
#define CUBISM_MODEL_2D_HPP

#include "gd_cubism_user_model.hpp"

// Preferred API. The internal legacy runtime retains native allocation and
// renderer ownership; it is neither exposed nor serialized as a scene child.
class CubismModel2D : public godot::Node2D {
    GDCLASS(CubismModel2D, godot::Node2D)

public:
    enum PlaybackProcessMode { IDLE, PHYSICS, MANUAL };
    enum ModelState { UNLOADED, LOADING, READY, ERROR, DISPOSING, DISPOSED };

private:
    GDCubismUserModel *runtime = nullptr;
    Ref<CubismModelResource> model;
    PlaybackProcessMode playback_process_mode = IDLE;
    bool paused = false;
    bool load_requested = false;
    uint64_t generation = 0;
    void emit_load_started(uint64_t expected_generation);
    void on_model_ready();
    void on_model_failed(const Dictionary &error);
    void step(double delta);
    int parameter_index(const StringName &id) const;
    Error queue_parameter(const StringName &id, double value, double weight, int operation);

protected:
    static void _bind_methods();
    void _notification(int what);

public:
    CubismModel2D();
    void set_model(const Ref<CubismModelResource> &resource) { load_model(resource); }
    Ref<CubismModelResource> get_model() const { return model; }
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
    void advance(double delta);
    bool has_parameter(const StringName &id) const { return parameter_index(id) >= 0; }
    double get_parameter_value(const StringName &id) const;
    Error set_parameter_value(const StringName &id, double value, double weight = 1.0) { return queue_parameter(id, value, weight, 0); }
    Error add_parameter_value(const StringName &id, double value, double weight = 1.0) { return queue_parameter(id, value, weight, 1); }
    Error multiply_parameter_value(const StringName &id, double value, double weight = 1.0) { return queue_parameter(id, value, weight, 2); }
    Error set_part_opacity(const StringName &id, double opacity);
    PackedStringArray get_parameter_ids() const;
    PackedStringArray get_part_ids() const;
    Dictionary get_canvas_info() const { return is_ready() ? runtime->get_canvas_info() : Dictionary(); }
};

VARIANT_ENUM_CAST(CubismModel2D::PlaybackProcessMode);
VARIANT_ENUM_CAST(CubismModel2D::ModelState);
#endif
