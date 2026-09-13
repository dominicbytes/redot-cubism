// SPDX-License-Identifier: MIT
#include "cubism_procedural_effects.hpp"
#include <Id/CubismIdManager.hpp>
#include <algorithm>

void CubismProceduralEffects::clear() {
    if (breath) Csm::CubismBreath::Delete(breath);
    breath = nullptr;
    eye_indices.clear();
    reset_blink();
}

void CubismProceduralEffects::reset_blink() {
    random_state = uint64_t(seed) ^ UINT64_C(0x9e3779b97f4a7c15);
    if (random_state == 0) random_state = 1;
    phase = WAIT;
    phase_time = 0.0f;
    wait_time = 0.0f;
    first_step = true;
}

float CubismProceduralEffects::next_interval() {
    // xorshift64*: fixed integer operations give each instance a stable stream.
    random_state ^= random_state >> 12;
    random_state ^= random_state << 25;
    random_state ^= random_state >> 27;
    const uint64_t value = random_state * UINT64_C(2685821657736338717);
    return float(value >> 40) * (7.0f / 16777216.0f);
}

float CubismProceduralEffects::advance_blink(float delta) {
    // R5 defaults: 0.1 seconds closing, 0.05 closed, 0.15 opening, then a
    // uniform wait in [0,7). Like R5, transition overshoot is not carried forward.
    if (first_step) { first_step = false; wait_time = next_interval(); return 1.0f; }
    phase_time += delta;
    switch (phase) {
        case WAIT:
            if (phase_time > wait_time) { phase = CLOSE; phase_time = 0.0f; }
            return 1.0f;
        case CLOSE: {
            const float value = std::max(0.0f, 1.0f - phase_time / 0.1f);
            if (phase_time >= 0.1f) { phase = HOLD; phase_time = 0.0f; }
            return value;
        }
        case HOLD:
            if (phase_time >= 0.05f) { phase = OPEN; phase_time = 0.0f; }
            return 0.0f;
        case OPEN: {
            const float value = std::min(1.0f, phase_time / 0.15f);
            if (phase_time >= 0.15f) { phase = WAIT; phase_time = 0.0f; wait_time = next_interval(); }
            return value;
        }
    }
    return 1.0f;
}

void CubismProceduralEffects::configure(Csm::ICubismModelSetting *setting, Csm::CubismModel *model) {
    clear();
    for (int i = 0; i < setting->GetEyeBlinkParameterCount(); ++i) {
        for (int j = 0; j < model->GetParameterCount(); ++j) {
            if (model->GetParameterId(j) == setting->GetEyeBlinkParameterId(i)) eye_indices.push_back(j);
        }
    }
    struct Profile { const char *id; float offset; float peak; float cycle; float weight; };
    const Profile profiles[] = {
        {"ParamAngleX", 0, 15, 6.5345f, 0.5f}, {"ParamAngleY", 0, 8, 3.5345f, 0.5f},
        {"ParamAngleZ", 0, 10, 5.5345f, 0.5f}, {"ParamBodyAngleX", 0, 4, 15.5345f, 0.5f},
        {"ParamBreath", 0.5f, 0.5f, 3.2345f, 0.5f}
    };
    Csm::csmVector<Csm::CubismBreath::BreathParameterData> parameters;
    for (const Profile &profile : profiles) {
        const auto id = Csm::CubismFramework::GetIdManager()->GetId(profile.id);
        for (int i = 0; i < model->GetParameterCount(); ++i) {
            if (model->GetParameterId(i) == id) parameters.PushBack(Csm::CubismBreath::BreathParameterData(id, profile.offset, profile.peak, profile.cycle, profile.weight));
        }
    }
    breath = Csm::CubismBreath::Create();
    breath->SetParameters(parameters);
}

void CubismProceduralEffects::update(Csm::CubismModel *model, float delta, bool motion_updated) {
    if (enable_eye_blink && !motion_updated && !eye_indices.empty()) {
        const float value = advance_blink(delta);
        for (int index : eye_indices) model->SetParameterValue(index, value);
    }
    if (enable_breath && breath) breath->UpdateParameters(model, delta);
}
