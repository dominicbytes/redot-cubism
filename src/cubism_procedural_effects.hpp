// SPDX-License-Identifier: MIT
#ifndef CUBISM_PROCEDURAL_EFFECTS_HPP
#define CUBISM_PROCEDURAL_EFFECTS_HPP
#include <Effect/CubismBreath.hpp>
#include <ICubismModelSetting.hpp>
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
    void reset_blink();
    float next_interval();
    float advance_blink(float delta);
public:
    bool enable_eye_blink = false;
    bool enable_breath = false;
    ~CubismProceduralEffects() { clear(); }
    void clear();
    void configure(Csm::ICubismModelSetting *setting, Csm::CubismModel *model);
    void set_seed(int64_t value) { seed = value; reset_blink(); }
    int64_t get_seed() const { return seed; }
    void update(Csm::CubismModel *model, float delta, bool motion_updated);
};
#endif
