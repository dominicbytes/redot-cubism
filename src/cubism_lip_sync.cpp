// SPDX-License-Identifier: MIT
#include "cubism_lip_sync.hpp"
#include "cubism_model_2d.hpp"
#include "private/internal_cubism_user_model.hpp"
#include <godot_cpp/classes/audio_server.hpp>
#include <cmath>
#include <limits>
#include <algorithm>

Error CubismLipSyncProfile::set_number(double &field, double value, double low, double high) {
    if (!std::isfinite(value) || value < low || value > high) return ERR_INVALID_PARAMETER;
    field = value;
    emit_changed();
    return OK;
}
Error CubismLipSyncProfile::set_gain(double value) { return set_number(gain, value, 0, std::numeric_limits<float>::max()); }
Error CubismLipSyncProfile::set_noise_gate(double value) { return set_number(noise_gate, value, 0, 1); }
Error CubismLipSyncProfile::set_attack(double value) { return set_number(attack, value, 0, std::numeric_limits<float>::max()); }
Error CubismLipSyncProfile::set_release(double value) { return set_number(release, value, 0, std::numeric_limits<float>::max()); }
Error CubismLipSyncProfile::set_minimum(double value) { return set_number(minimum, value, -std::numeric_limits<float>::max(), maximum); }
Error CubismLipSyncProfile::set_maximum(double value) { return set_number(maximum, value, minimum, std::numeric_limits<float>::max()); }
Error CubismLipSyncProfile::set_mouth_form_value(double value) { return set_number(mouth_form_value, value, -std::numeric_limits<float>::max(), std::numeric_limits<float>::max()); }

void CubismLipSyncProfile::_bind_methods() {
#define LIP_PROPERTY(type, name) \
    ClassDB::bind_method(D_METHOD("set_" #name, "value"), &CubismLipSyncProfile::set_##name); \
    ClassDB::bind_method(D_METHOD("get_" #name), &CubismLipSyncProfile::get_##name); \
    ADD_PROPERTY(PropertyInfo(type, #name), "set_" #name, "get_" #name);
    LIP_PROPERTY(Variant::FLOAT, gain)
    LIP_PROPERTY(Variant::FLOAT, noise_gate)
    LIP_PROPERTY(Variant::FLOAT, attack)
    LIP_PROPERTY(Variant::FLOAT, release)
    LIP_PROPERTY(Variant::FLOAT, minimum)
    LIP_PROPERTY(Variant::FLOAT, maximum)
    LIP_PROPERTY(Variant::PACKED_STRING_ARRAY, parameter_ids)
    LIP_PROPERTY(Variant::STRING_NAME, mouth_form_parameter)
    LIP_PROPERTY(Variant::FLOAT, mouth_form_value)
    LIP_PROPERTY(Variant::BOOL, blend_with_authored)
#undef LIP_PROPERTY
}

void CubismLipSync::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_target_model", "value"), &CubismLipSync::set_target_model);
    ClassDB::bind_method(D_METHOD("get_target_model"), &CubismLipSync::get_target_model);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "target_model", PROPERTY_HINT_NODE_TYPE, "CubismModel2D"), "set_target_model", "get_target_model");
    ClassDB::bind_method(D_METHOD("set_profile", "value"), &CubismLipSync::set_profile);
    ClassDB::bind_method(D_METHOD("get_profile"), &CubismLipSync::get_profile);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "profile", PROPERTY_HINT_RESOURCE_TYPE, "CubismLipSyncProfile"), "set_profile", "get_profile");
    ClassDB::bind_method(D_METHOD("set_input_mode", "value"), &CubismLipSync::set_input_mode);
    ClassDB::bind_method(D_METHOD("get_input_mode"), &CubismLipSync::get_input_mode);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "input_mode", PROPERTY_HINT_ENUM, "Manual Value,Audio Bus Peak"), "set_input_mode", "get_input_mode");
    ClassDB::bind_method(D_METHOD("set_audio_bus", "value"), &CubismLipSync::set_audio_bus);
    ClassDB::bind_method(D_METHOD("get_audio_bus"), &CubismLipSync::get_audio_bus);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "audio_bus"), "set_audio_bus", "get_audio_bus");
    ClassDB::bind_method(D_METHOD("set_enabled", "value"), &CubismLipSync::set_enabled);
    ClassDB::bind_method(D_METHOD("get_enabled"), &CubismLipSync::get_enabled);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "get_enabled");
    ClassDB::bind_method(D_METHOD("submit_sample", "value"), &CubismLipSync::submit_sample);
    ClassDB::bind_method(D_METHOD("submit_peak_db", "left_db", "right_db"), &CubismLipSync::submit_peak_db);
    ClassDB::bind_method(D_METHOD("get_envelope"), &CubismLipSync::get_envelope);
    ClassDB::bind_method(D_METHOD("get_output_value"), &CubismLipSync::get_output_value);
    ClassDB::bind_method(D_METHOD("get_last_error"), &CubismLipSync::get_last_error);
    ClassDB::bind_method(D_METHOD("reset"), &CubismLipSync::reset);
    BIND_ENUM_CONSTANT(MANUAL_VALUE);
    BIND_ENUM_CONSTANT(AUDIO_BUS_PEAK);
}

CubismLipSync::CubismLipSync() { defaults.instantiate(); }

CubismModel2D *CubismLipSync::get_target_model() const {
    return Object::cast_to<CubismModel2D>(ObjectDB::get_instance(target_id));
}

Error CubismLipSync::set_target_model(CubismModel2D *value) {
    if (value) {
        const Error error = value->attach_lip_sync(get_instance_id());
        if (error != OK) { last_error = error; return error; }
    }
    CubismModel2D *previous = get_target_model();
    const uint64_t next_id = value ? uint64_t(value->get_instance_id()) : 0;
    if (target_id != next_id) {
        if (previous) previous->detach_lip_sync(get_instance_id());
        target_id = next_id;
        reset();
    }
    last_error = OK;
    return OK;
}

void CubismLipSync::_notification(int what) {
    if (what == NOTIFICATION_ENTER_TREE) {
        if (auto *target = get_target_model()) last_error = target->attach_lip_sync(get_instance_id());
    } else if (what == NOTIFICATION_EXIT_TREE || what == NOTIFICATION_PREDELETE) {
        if (auto *target = get_target_model()) target->detach_lip_sync(get_instance_id());
        reset();
    }
}

void CubismLipSync::set_profile(const Ref<CubismLipSyncProfile> &value) {
    profile = value;
    reset();
}

void CubismLipSync::set_input_mode(InputMode value) {
    if (value < MANUAL_VALUE || value > AUDIO_BUS_PEAK) return;
    input_mode = value;
    reset();
}

Error CubismLipSync::submit_sample(double value) {
    if (!std::isfinite(value) || value < 0) { last_error = ERR_INVALID_PARAMETER; return last_error; }
    sample = std::min(value, 1.0);
    last_error = OK;
    return OK;
}

bool CubismLipSync::db_amplitude(double db, double &value) {
    if (db == -std::numeric_limits<double>::infinity()) { value = 0; return true; }
    if (!std::isfinite(db)) return false;
    value = db >= 0 ? 1.0 : std::pow(10.0, db / 20.0);
    return true;
}

Error CubismLipSync::submit_peak_db(double left_db, double right_db) {
    double left, right;
    if (!db_amplitude(left_db, left) || !db_amplitude(right_db, right)) {
        last_error = ERR_INVALID_PARAMETER;
        return last_error;
    }
    return submit_sample(std::max(left, right));
}

void CubismLipSync::reset() { sample = 0; envelope = 0; last_error = OK; }

double CubismLipSync::get_output_value() const {
    const Ref<CubismLipSyncProfile> settings = profile.is_valid() ? profile : defaults;
    return settings->get_minimum() + (settings->get_maximum() - settings->get_minimum()) * envelope;
}

void CubismLipSync::apply(InternalCubismUserModel &runtime, double delta) {
    if (!enabled || !is_inside_tree() || !can_process() || is_queued_for_deletion()) return;
    const Ref<CubismLipSyncProfile> settings = profile.is_valid() ? profile : defaults;
    double amplitude = sample;
    last_error = OK;
    if (input_mode == AUDIO_BUS_PEAK) {
        amplitude = 0;
        AudioServer *server = AudioServer::get_singleton();
        const int bus = server->get_bus_index(audio_bus);
        if (bus < 0) last_error = ERR_DOES_NOT_EXIST;
        else for (int channel = 0; channel < server->get_bus_channels(bus); ++channel) {
            double left, right;
            if (!db_amplitude(server->get_bus_peak_volume_left_db(bus, channel), left)
                || !db_amplitude(server->get_bus_peak_volume_right_db(bus, channel), right)) {
                last_error = ERR_INVALID_DATA;
                continue;
            }
            amplitude = std::max(amplitude, std::max(left, right));
        }
    }
    const double desired = amplitude < settings->get_noise_gate() ? 0.0 : std::min(1.0, amplitude * settings->get_gain());
    const double seconds = desired > envelope ? settings->get_attack() : settings->get_release();
    const double weight = seconds == 0 ? 1.0 : -std::expm1(-delta / seconds);
    envelope += (desired - envelope) * weight;
    PackedStringArray ids = settings->get_parameter_ids();
    if (ids.is_empty()) ids = runtime.get_lip_sync_ids();
    const StringName form = settings->get_mouth_form_parameter();
    if (form != StringName() && !ids.has(String(form))) ids.push_back(form);
    PackedStringArray applied;
    auto *model = runtime.GetModel();
    for (const String &id : ids) {
        if (applied.has(id)) continue;
        applied.push_back(id);
        if (!settings->get_blend_with_authored() && runtime.has_authored_parameter(id)) continue;
        int index = -1;
        for (int i = 0; i < model->GetParameterCount(); ++i) {
            if (String::utf8(model->GetParameterId(i)->GetString().GetRawString()) == id) { index = i; break; }
        }
        if (index < 0) { last_error = ERR_DOES_NOT_EXIST; continue; }
        if (StringName(id) == form) model->SetParameterValue(index, float(settings->get_mouth_form_value()));
        else model->AddParameterValue(index, float(get_output_value()));
    }
}
