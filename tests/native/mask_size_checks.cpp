// SPDX-License-Identifier: MIT
#include "cubism_mask_size.hpp"
#include "cubism_mask_policy.hpp"
#include <iostream>
#include <limits>

int main() {
    int checks = 0, failures = 0;
    auto expect = [&](bool condition, const char *label) {
        ++checks;
        if (!condition) { ++failures; std::cerr << label << '\n'; }
    };
    CubismMaskSize size;
    expect(cubism_mask_size(300, 100, 128, size) && size.width == 128 && size.height == 43
        && std::abs(size.scale - 128.0 / 300) < 1e-12, "landscape scaled uniformly and rounded outward");
    expect(cubism_mask_size(100, 300, 128, size) && size.width == 43 && size.height == 128,
        "portrait preserves orientation");
    expect(cubism_mask_size(10.25, 20.75, 128, size) && size.width == 11 && size.height == 21
        && size.scale == 1, "native resolution does not upscale to the cap");
    expect(cubism_mask_size(1e20, 8, 128, size) && size.width == 128 && size.height == 2,
        "very thin mask retains a renderable short edge");
    expect(cubism_mask_size(8192, 4096, 0, size) && size.width == 4096 && size.height == 2048
        && size.scale == 0.5, "legacy zero is bounded");
    expect(cubism_mask_size(100, 50, 1, size) && size.width == 2 && size.height == 2
        && size.scale == 0.02, "one pixel limit retains uniform geometry within a two pixel target");
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    for (double invalid : {0.0, -1.0, nan, inf, -inf}) {
        expect(!cubism_mask_size(invalid, 20, 512, size), "invalid width rejected before integer conversion");
        expect(!cubism_mask_size(20, invalid, 512, size), "invalid height rejected before integer conversion");
    }
    for (int limit : {-1, 0, 1, 2, 127, 512, 1024, 2048, 4096, 8192, std::numeric_limits<int>::max()}) {
        for (double width : {1e-30, 0.5, 10.25, 1024.0, 10000.0, 1e30, std::numeric_limits<double>::max()}) {
            for (double height : {1e-30, 0.5, 100.75, 2048.0, 1e30}) {
                const int cap = limit <= 0 || limit > 4096 ? 4096 : (limit < 2 ? 2 : limit);
                expect(cubism_mask_size(width, height, limit, size) && std::isfinite(size.scale)
                    && size.scale > 0 && size.scale <= 1 && size.width >= 2 && size.height >= 2
                    && size.width <= cap && size.height <= cap, "all accepted targets are bounded and renderable");
                expect(width * size.scale <= size.width + 1e-9 && height * size.scale <= size.height + 1e-9,
                    "uniformly scaled geometry fits the integer target");
            }
        }
    }
    double density = 0;
    expect(cubism_mask_density(1, 0, 0, 1, density) && density == 1, "identity density");
    expect(cubism_mask_density(0, -2, 2, 0, density) && density == 2, "rotated zoom density");
    expect(cubism_mask_density(-0.5, 0, 0, 0.25, density) && density == 0.5, "mirrored nonuniform density");
    expect(cubism_mask_density(1, 1, 0, 1, density) && std::abs(density - (1 + std::sqrt(5.0)) / 2) < 1e-12,
        "shear uses maximum stretch rather than column lengths");
    expect(cubism_mask_density(1e30, 0, 0, 1e-30, density) && density == 1e30, "extreme anisotropy remains finite");
    expect(!cubism_mask_density(0, 0, 0, 0, density), "zero basis rejected");
    for (double invalid : {nan, inf, -inf}) {
        expect(!cubism_mask_density(invalid, 0, 0, 1, density), "nonfinite basis rejected");
        expect(!cubism_mask_size(100, 200, 512, size, invalid), "nonfinite density rejected");
    }
    expect(!cubism_mask_size(100, 200, 512, size, 0), "zero density rejected");
    expect(!cubism_mask_size(100, 200, 512, size, -1), "negative density rejected");
    expect(cubism_mask_size(300, 100, 1024, size, 0.5) && size.width == 150 && size.height == 50 && size.scale == 0.5,
        "half-scale targets half the local pixels");
    expect(cubism_mask_size(300, 100, 1024, size, 2) && size.width == 600 && size.height == 200 && size.scale == 2,
        "zoomed model increases effective quality below the cap");
    expect(cubism_mask_size(300, 100, 128, size, 1e30) && size.width == 128 && size.height == 43,
        "extreme zoom remains bounded");
    CubismMaskCadence cadence;
    expect(cadence.due(0), "first offscreen pulse includes clock origin");
    expect(!cadence.due(0) && !cadence.due(99999), "repeated manual steps do not trigger early pulses");
    expect(cadence.due(100000) && !cadence.due(100001), "100 ms pulse boundary");
    expect(cadence.due(9999999), "long stalls request only one current redraw");
    expect(!cadence.due(10000000) && cadence.due(10099999), "cadence resumes from actual request time");
    std::cout << "CUBISM_MASK_SIZE checks=" << checks << " failures=" << failures << '\n';
    return failures ? 1 : 0;
}
