// SPDX-License-Identifier: MIT
#ifndef CUBISM_MASK_POLICY_HPP
#define CUBISM_MASK_POLICY_HPP

#include <cstdint>

enum class CubismMaskOffscreenPolicy { ALWAYS, REDUCED, PAUSED };

struct CubismMaskCadence {
    uint64_t last_update_usec = 0;
    bool started = false;

    bool due(uint64_t now_usec) {
        if (started && now_usec - last_update_usec < 100000) return false;
        started = true;
        last_update_usec = now_usec;
        return true;
    }
};

#endif
