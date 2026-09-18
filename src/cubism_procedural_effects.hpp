// SPDX-License-Identifier: MIT
#ifndef CUBISM_PROCEDURAL_EFFECTS_HPP
#define CUBISM_PROCEDURAL_EFFECTS_HPP
#include <Effect/CubismBreath.hpp>
#include <ICubismModelSetting.hpp>
#include <Math/CubismTargetPoint.hpp>
#include <array>
#include <cstdint>
#include <vector>

// Preferred-node effect state. No process-global random state or model ownership.
class CubismProceduralEffects {
    enum Phase { WAIT, CLOSE, HOLD, OPEN };
    Phase phase = WAIT;
    bool first_step = true;
    float phase_time = 0.0f;
    float wait_time = 0.0f;
    uint64_t random_state = 1;
    int64_t seed = 0;
    std::vector<int> eye_indices;
    Csm::CubismBreath *breath = nullptr;
    Csm::CubismTargetPoint look;
    std::array<int, 6> look_indices;
    bool look_active = false;
    float look_weight = 1.0f;
    void reset_blink();
    float next_interval();
    float advance_blink(float delta);
public:
    bool enable_eye_blink = false;
    bool enable_breath = false;
    bool enable_look_target = true;
    bool enable_lip_sync = true;
    uint64_t lip_sync_id = 0;
    ~CubismProceduralEffects() { clear(); }
    void clear();
    void configure(Csm::ICubismModelSetting *setting, Csm::CubismModel *model);
    void set_seed(int64_t value) { seed = value; reset_blink(); }
    int64_t get_seed() const { return seed; }
    void set_look_target(float x, float y, float weight) { look.Set(x, y); look_weight = weight; look_active = true; }
    void clear_look_target() { look = Csm::CubismTargetPoint(); look_active = false; }
    void update(Csm::CubismModel *model, float delta, bool motion_updated);
};
#endif
