// SPDX-License-Identifier: MIT
#pragma once
#include <algorithm>
#include <cmath>

// AudioServer exposes separate clock reads. Bracket the playback position and
// next-mix reads with mix ages; an age reset means this sample crossed a mix.
inline bool cubism_audio_clock_estimate(double position, double age_before, double age_after,
        double next_mix, double latency, double length, double previous, double &estimate) {
    if (!std::isfinite(position) || !std::isfinite(age_before) || !std::isfinite(age_after) ||
            !std::isfinite(next_mix) || !std::isfinite(latency) || position < 0 ||
            age_before < 0 || age_after < 0 || latency < 0) return false;
    if (age_after < age_before) {
        // The mix ages cannot safely interpolate this playback sample, but its
        // position still supplies a conservative clock. Holding only previous
        // would lose several buffers of progress after a main-thread stall.
        estimate = std::max(previous, std::clamp(position - latency, 0.0, length));
        return true;
    }
    const double interval = age_after + next_mix;
    if (!std::isfinite(interval) || interval <= 0) return false;
    // Do not predict indefinitely when the audio thread stalls. Playback reads
    // also have buffer granularity, so allow one mix interval of backward jitter.
    const double audible = std::clamp(position + std::min(age_after, interval) - latency, 0.0, length);
    if (audible < previous - std::max(0.05, interval + 0.005)) return false;
    estimate = std::max(previous, audible);
    return true;
}
