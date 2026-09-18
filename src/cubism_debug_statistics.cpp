// SPDX-License-Identifier: MIT
#include "cubism_debug_statistics.hpp"

#ifdef DEBUG_ENABLED
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <set>

namespace {
struct FrameStatistics {
    uint64_t frame = UINT64_MAX;
    uint64_t model_usec = 0;
    uint64_t renderer_usec = 0;
    uint64_t vertex_bytes = 0;
    std::set<uint64_t> masks;
};

FrameStatistics &current_frame() {
    static FrameStatistics value;
    const uint64_t frame = godot::Engine::get_singleton()->get_process_frames();
    if (value.frame != frame) {
        value.frame = frame;
        value.model_usec = value.renderer_usec = value.vertex_bytes = 0;
        value.masks.clear();
    }
    return value;
}
}

CubismDebugTimer::CubismDebugTimer(CubismDebugPhase value)
    : phase(value), started(godot::Time::get_singleton()->get_ticks_usec()) {}

void CubismDebugTimer::stop() {
    if (stopped) return;
    stopped = true;
    const uint64_t elapsed = godot::Time::get_singleton()->get_ticks_usec() - started;
    auto &frame = current_frame();
    if (phase == CubismDebugPhase::MODEL) frame.model_usec += elapsed;
    else frame.renderer_usec += elapsed;
}

void cubism_debug_vertex_upload(uint64_t bytes) { current_frame().vertex_bytes += bytes; }
void cubism_debug_mask_redraw(uint64_t viewport_id) { current_frame().masks.insert(viewport_id); }

godot::Dictionary cubism_debug_frame_statistics() {
    const auto &frame = current_frame();
    godot::Dictionary result;
    result["enabled"] = true;
    result["frame_id"] = frame.frame;
    result["model_update_usec"] = frame.model_usec;
    result["renderer_update_usec"] = frame.renderer_usec;
    result["vertex_bytes_uploaded_last_frame"] = frame.vertex_bytes;
    result["mask_redraws_last_frame"] = static_cast<int64_t>(frame.masks.size());
    return result;
}
#endif
