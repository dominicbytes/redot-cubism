// SPDX-License-Identifier: MIT
#include "cubism_animator.hpp"
#include "cubism_descriptors.hpp"
#include "gd_cubism_user_model.hpp"
#include "private/internal_cubism_user_model.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

void CubismAnimator::configure(const Ref<CubismModelResource> &resource) {
    catalog.clear();
    if (resource.is_null()) return;
    const Dictionary groups = resource->get_motion_groups();
    const Array values = groups.values();
    for (int i = 0; i < values.size(); ++i) {
        const Array descriptors = values[i];
        for (int j = 0; j < descriptors.size(); ++j) {
            const Ref<CubismMotionDescriptor> descriptor = descriptors[j];
            Motion motion{descriptor->get_id(), descriptor->get_group(), descriptor->get_index(), {}};
            motion.default_loop = descriptor->get_loop();
            if (motion.id == StringName()) motion.valid = false;
            for (auto &existing : catalog) {
                if (existing.id == motion.id) { existing.valid = false; motion.valid = false; }
            }
            for (const Ref<CubismMotionEvent> event : descriptor->get_events()) {
                if (event.is_null() || !std::isfinite(event->get_time_seconds()) || event->get_time_seconds() < 0.0) { motion.valid = false; break; }
                motion.events.push_back({event->get_time_seconds(), event->get_value()});
            }
            std::stable_sort(motion.events.begin(), motion.events.end(), [](const Event &a, const Event &b) { return a.time < b.time; });
            catalog.push_back(motion);
        }
    }
}

void CubismAnimator::clear(CubismMotionHandle::FinishReason reason) {
    for (const auto &playback : playbacks) playback->handle->finish(reason);
    playbacks.clear();
    catalog.clear();
}

PackedStringArray CubismAnimator::get_motion_ids() const {
    PackedStringArray ids;
    for (const auto &motion : catalog) ids.push_back(motion.id);
    return ids;
}

StringName CubismAnimator::find_motion(const StringName &group, int index) const {
    for (const auto &motion : catalog) if (motion.group == group && motion.index == index) return motion.id;
    return StringName();
}

bool CubismAnimator::get_default_loop(const StringName &id) const {
    for (const auto &motion : catalog) if (motion.id == id) return motion.default_loop;
    return false;
}

void CubismAnimator::fade(Playback &playback, double seconds, CubismMotionHandle::FinishReason reason) {
    // A new play leaves already interrupted fades alone, but an explicit stop
    // must also stop their remaining influence without changing terminal reasons.
    if (playback.handle->is_finished() && reason == CubismMotionHandle::INTERRUPTED) return;
    const double duration = seconds < 0 ? std::max(0.0, double(playback.motion->GetFadeOutTime())) : seconds * playback.speed;
    playback.motion->SetFadeOutTime(float(duration));
    playback.entry.StartFadeout(float(duration), float(playback.time));
    playback.fade_end = playback.entry.GetEndTime();
    if (duration == 0.0) playback.entry.IsFinished(true);
    playback.handle->finish(reason);
}

Ref<CubismMotionHandle> CubismAnimator::play(InternalCubismUserModel &model, const StringName &id, int priority, bool loop, double speed) {
    if (!std::isfinite(speed) || speed <= 0 || speed > 256 || priority < 0 || priority > 3) return CubismMotionHandle::rejected(id, ERR_INVALID_PARAMETER);
    const Motion *selected = nullptr;
    for (const auto &motion : catalog) if (motion.id == id) { selected = &motion; break; }
    if (!selected) return CubismMotionHandle::rejected(id, ERR_DOES_NOT_EXIST);
    if (!selected->valid) return CubismMotionHandle::rejected(id, ERR_INVALID_DATA);
    int current_priority = 0;
    for (const auto &playback : playbacks) if (!playback->handle->is_finished()) current_priority = playback->priority;
    if (priority != CubismMotionPriority::FORCE && priority <= current_priority) return CubismMotionHandle::rejected(id, ERR_BUSY);
    if (playbacks.size() >= 256) return CubismMotionHandle::rejected(id, ERR_BUSY);
    auto playback = std::make_unique<Playback>();
    playback->motion = model.create_motion(String(selected->group), selected->index, loop, playback->period);
    if (!playback->motion || (loop && (!std::isfinite(playback->period) || playback->period <= 0))) return CubismMotionHandle::rejected(id, ERR_INVALID_DATA);
    for (const auto &event : selected->events) {
        if (event.time > playback->motion->GetLoopDuration()) return CubismMotionHandle::rejected(id, ERR_INVALID_DATA);
    }
    playback->handle = CubismMotionHandle::rejected(id, OK);
    playback->handle->state = CubismMotionHandle::PLAYING;
    playback->handle->reason = CubismMotionHandle::NONE;
    playback->speed = speed;
    playback->priority = priority;
    playback->events = selected->events;
    playback->motion->SetupMotionQueueEntry(&playback->entry, 0.0f);
    for (const auto &old : playbacks) fade(*old, -1.0, CubismMotionHandle::INTERRUPTED);
    const Ref<CubismMotionHandle> handle = playback->handle;
    playbacks.push_back(std::move(playback));
    return handle;
}

void CubismAnimator::stop(double seconds) {
    for (const auto &playback : playbacks) fade(*playback, seconds, CubismMotionHandle::STOPPED);
}

bool CubismAnimator::update(Csm::CubismModel *model, double delta) {
    bool updated = false;
    for (auto it = playbacks.begin(); it != playbacks.end();) {
        Playback &p = **it;
        const double previous = p.time;
        p.time += delta * p.speed;
        const bool loop = p.motion->GetLoop();
        const double first = loop ? std::floor(previous / p.period) : 0;
        const double last = loop ? std::floor(p.time / p.period) : 0;
        // Bound adversarial tiny loops/event bursts before invoking SDK looping.
        if (!std::isfinite(float(p.time)) || last >= double(std::numeric_limits<int64_t>::max()) || last - first > 10000 || (last - first + 1) * p.events.size() > 100000) {
            p.handle->finish(CubismMotionHandle::FAILED);
            it = playbacks.erase(it);
            continue;
        }
        const int64_t first_cycle = int64_t(first);
        const int64_t last_cycle = int64_t(last);
        if (!p.entry.IsFinished()) {
            p.motion->UpdateParameters(model, &p.entry, float(p.time));
            updated = true;
        }
        if (p.fade_end >= 0.0) {
            // R5 may reset the loop end on its first evaluation. Retain a stop
            // requested before that evaluation without mutating shared motions.
            p.entry.SetEndTime(float(p.fade_end));
            if (p.time >= p.fade_end) p.entry.IsFinished(true);
        }
        if (!p.handle->is_finished()) {
            p.handle->elapsed_seconds = loop ? p.time : std::min(p.time, double(p.motion->GetDuration()));
            for (int64_t cycle = first_cycle; cycle <= last_cycle; ++cycle) {
                for (const auto &event : p.events) {
                    const double at = event.time + (loop ? cycle * p.period : 0.0);
                    if ((at > previous || (p.first_step && at == 0.0)) && at <= p.time) p.handle->queue_event("event", event.value);
                }
                if (loop && cycle < last_cycle) {
                    p.handle->loop_count = cycle + 1;
                    p.handle->queue_event("looped", cycle + 1);
                }
            }
            if (loop) p.handle->loop_count = last_cycle;
        }
        p.first_step = false;
        if (p.entry.IsFinished()) {
            p.handle->finish(CubismMotionHandle::COMPLETED);
            it = playbacks.erase(it);
        } else ++it;
    }
    return updated;
}
