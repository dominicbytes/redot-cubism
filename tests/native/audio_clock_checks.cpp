// SPDX-License-Identifier: MIT
#include "cubism_audio_clock.hpp"
#include <iostream>
#include <limits>

int main() {
    int failures = 0;
    int checks = 0;
    auto expect = [&](bool condition, const char *label) {
        ++checks;
        if (!condition) { ++failures; std::cerr << label << '\n'; }
    };
    double estimate = 0;
    expect(cubism_audio_clock_estimate(1, .01, .012, .08, .02, 3, .9, estimate) &&
            std::abs(estimate - .992) < 1e-9, "latency-adjusted sample");
    // Captured exported-cue failure: old playback position with a fresh mix age.
    expect(cubism_audio_clock_estimate(.56, .093195, .0001, .09277, 0, .7, .639304002, estimate) &&
            estimate == .639304002, "cross-mix sample holds the previous clock");
    expect(cubism_audio_clock_estimate(.56, .0001, .0002, .09267, 0, .7, .639304002, estimate) &&
            estimate == .639304002, "one backend buffer of jitter does not cancel a cue");
    expect(cubism_audio_clock_estimate(.64, .001, .002, .09087, 0, .7, .639304002, estimate) &&
            std::abs(estimate - .642) < 1e-9, "next mix resumes advancement");
    expect(!cubism_audio_clock_estimate(.2, .001, .002, .09087, 0, .7, .639304002, estimate),
            "larger backward discontinuity still fails");
    expect(cubism_audio_clock_estimate(1, 1.999, 2, -1.9, 0, 5, 1, estimate) &&
            std::abs(estimate - 1.1) < 1e-9, "stalled mixer predicts only one buffer");
    expect(cubism_audio_clock_estimate(.69, .08, .081, .012, 0, .7, .68, estimate) && estimate == .7,
            "estimate never exceeds stream duration");
    expect(cubism_audio_clock_estimate(0, .001, .002, .008, .1, 1, 0, estimate) && estimate == 0,
            "output latency cannot make the clock negative");
    expect(cubism_audio_clock_estimate(.96, .001, .002, .008, 0, 2, 1, estimate) && estimate == 1,
            "small-buffer jitter retains the 50 ms allowance");
    expect(!cubism_audio_clock_estimate(.9, .001, .002, .008, 0, 2, 1, estimate),
            "small-buffer clock rejects a 100 ms jump");
    const double nan = std::numeric_limits<double>::quiet_NaN();
    for (int field = 0; field < 5; ++field) {
        double values[] = {1, .01, .012, .08, .02};
        values[field] = nan;
        expect(!cubism_audio_clock_estimate(values[0], values[1], values[2], values[3], values[4],
                3, .9, estimate), "nonfinite backend sample rejected");
    }
    expect(!cubism_audio_clock_estimate(1, .01, .012, -.02, 0, 3, .9, estimate),
            "invalid mixer interval rejected");
    std::cout << "CUBISM_AUDIO_CLOCK checks=" << checks << " failures=" << failures << '\n';
    return failures ? 1 : 0;
}
