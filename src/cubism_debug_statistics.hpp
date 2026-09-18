// SPDX-License-Identifier: MIT
#ifndef CUBISM_DEBUG_STATISTICS_HPP
#define CUBISM_DEBUG_STATISTICS_HPP

#ifdef DEBUG_ENABLED
#include <godot_cpp/variant/dictionary.hpp>
#include <cstdint>

enum class CubismDebugPhase { MODEL, RENDERER };

class CubismDebugTimer {
    CubismDebugPhase phase;
    uint64_t started;
    bool stopped = false;
public:
    explicit CubismDebugTimer(CubismDebugPhase phase);
    ~CubismDebugTimer() { stop(); }
    void stop();
};

void cubism_debug_vertex_upload(uint64_t bytes);
void cubism_debug_mask_redraw(uint64_t viewport_id);
godot::Dictionary cubism_debug_frame_statistics();
#endif
#endif
