// SPDX-License-Identifier: MIT
#include "cubism_mask_size.hpp"
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
    std::cout << "CUBISM_MASK_SIZE checks=" << checks << " failures=" << failures << '\n';
    return failures ? 1 : 0;
}
