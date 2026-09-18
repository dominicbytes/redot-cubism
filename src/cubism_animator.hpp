// SPDX-License-Identifier: MIT
#ifndef CUBISM_ANIMATOR_HPP
#define CUBISM_ANIMATOR_HPP
#include "cubism_motion_handle.hpp"
#include "cubism_model_resource.hpp"
#include <Motion/CubismMotion.hpp>
#include <Motion/CubismMotionQueueEntry.hpp>
#include <memory>
#include <vector>

class InternalCubismUserModel;

// Owns playback allocations, never model/renderer allocations. Each SDK motion
// has its own queue entry and clock, including while fading after interruption.
class CubismAnimator {
    struct Event { double time; String value; };
    struct Motion { StringName id; StringName group; int index; std::vector<Event> events; bool valid = true; bool default_loop = false; };
    struct Playback {
        Csm::CubismMotion *motion = nullptr;
        Csm::CubismMotionQueueEntry entry;
        Ref<CubismMotionHandle> handle;
        std::vector<Event> events;
        PackedStringArray parameters;
        double time = 0.0;
        double speed = 1.0;
        double period = 0.0;
        double fade_end = -1.0;
        int priority = 0;
        bool first_step = true;
        ~Playback() { if (motion) Csm::ACubismMotion::Delete(motion); }
    };
    std::vector<Motion> catalog;
    std::vector<std::unique_ptr<Playback>> playbacks;
    PackedStringArray authored_parameters;
    void fade(Playback &playback, double seconds, CubismMotionHandle::FinishReason reason);
public:
    ~CubismAnimator() { clear(CubismMotionHandle::MODEL_DISPOSED); }
    void configure(const Ref<CubismModelResource> &resource);
    void clear(CubismMotionHandle::FinishReason reason);
    PackedStringArray get_motion_ids() const;
    size_t get_owned_handle_count() const { return playbacks.size(); }
    bool get_default_loop(const StringName &id) const;
    StringName find_motion(const StringName &group, int index) const;
    Ref<CubismMotionHandle> play(InternalCubismUserModel &model, const StringName &id, int priority, bool loop, double speed);
    void stop(double fade_seconds);
    bool update(Csm::CubismModel *model, double delta);
    bool has_authored_parameter(const String &id) const { return authored_parameters.has(id); }
};
#endif
