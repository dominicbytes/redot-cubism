// SPDX-License-Identifier: MIT
#ifndef CUBISM_LIP_SYNC_HPP
#define CUBISM_LIP_SYNC_HPP
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

using namespace godot;
class CubismModel2D;
class InternalCubismUserModel;

class CubismLipSyncProfile : public Resource {
    GDCLASS(CubismLipSyncProfile, Resource)
    double gain = 1.0;
    double noise_gate = 0.02;
    double attack = 0.03;
    double release = 0.08;
    double minimum = 0.0;
    double maximum = 0.8;
    double mouth_form_value = 0.0;
    PackedStringArray parameter_ids;
    StringName mouth_form_parameter;
    bool blend_with_authored = false;
    Error set_number(double &field, double value, double low, double high);
protected:
    static void _bind_methods();
public:
    Error set_gain(double value);
    double get_gain() const { return gain; }
    Error set_noise_gate(double value);
    double get_noise_gate() const { return noise_gate; }
    Error set_attack(double value);
    double get_attack() const { return attack; }
    Error set_release(double value);
    double get_release() const { return release; }
    Error set_minimum(double value);
    double get_minimum() const { return minimum; }
    Error set_maximum(double value);
    double get_maximum() const { return maximum; }
    Error set_mouth_form_value(double value);
    double get_mouth_form_value() const { return mouth_form_value; }
    void set_parameter_ids(const PackedStringArray &value) { parameter_ids = value; emit_changed(); }
    PackedStringArray get_parameter_ids() const { return parameter_ids; }
    void set_mouth_form_parameter(const StringName &value) { mouth_form_parameter = value; emit_changed(); }
    StringName get_mouth_form_parameter() const { return mouth_form_parameter; }
    void set_blend_with_authored(bool value) { blend_with_authored = value; emit_changed(); }
    bool get_blend_with_authored() const { return blend_with_authored; }
};

class CubismLipSync : public Node {
    GDCLASS(CubismLipSync, Node)
public:
    enum InputMode { MANUAL_VALUE, AUDIO_BUS_PEAK };
private:
    uint64_t target_id = 0;
    Ref<CubismLipSyncProfile> profile;
    Ref<CubismLipSyncProfile> defaults;
    InputMode input_mode = MANUAL_VALUE;
    StringName audio_bus = "Master";
    bool enabled = true;
    double sample = 0.0;
    double envelope = 0.0;
    Error last_error = OK;
    static bool db_amplitude(double db, double &value);
protected:
    static void _bind_methods();
    void _notification(int what);
public:
    CubismLipSync();
    Error set_target_model(CubismModel2D *value);
    CubismModel2D *get_target_model() const;
    void set_profile(const Ref<CubismLipSyncProfile> &value);
    Ref<CubismLipSyncProfile> get_profile() const { return profile; }
    void set_input_mode(InputMode value);
    InputMode get_input_mode() const { return input_mode; }
    void set_audio_bus(const StringName &value) { audio_bus = value; reset(); }
    StringName get_audio_bus() const { return audio_bus; }
    void set_enabled(bool value) { enabled = value; if (!enabled) reset(); }
    bool get_enabled() const { return enabled; }
    Error submit_sample(double value);
    Error submit_peak_db(double left_db, double right_db);
    double get_envelope() const { return envelope; }
    double get_output_value() const;
    Error get_last_error() const { return last_error; }
    void reset();
    void apply(InternalCubismUserModel &runtime, double delta);
};

VARIANT_ENUM_CAST(CubismLipSync::InputMode);
#endif
