// SPDX-License-Identifier: MIT
#ifndef CUBISM_MASK_SIZE_HPP
#define CUBISM_MASK_SIZE_HPP

#include <algorithm>
#include <cmath>

struct CubismMaskSize {
    int width = 2;
    int height = 2;
    double scale = 1;
};

// A zero legacy limit means native resolution, still subject to the safety cap.
// Round outward and keep a uniform canvas scale: extra pixels are transparent
// padding, not independent X/Y stretching of the mask geometry.
inline bool cubism_mask_size(double width, double height, int limit, CubismMaskSize &result) {
    if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0) return false;
    const int cap = limit <= 0 ? 4096 : std::clamp(limit, 2, 4096);
    result.scale = std::min(1.0, cap / std::max(width, height));
    result.width = std::clamp(static_cast<int>(std::ceil(width * result.scale)), 2, cap);
    result.height = std::clamp(static_cast<int>(std::ceil(height * result.scale)), 2, cap);
    return true;
}

#endif
