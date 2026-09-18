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

// Largest stretch of the 2D basis, including shear. Normalize first to avoid
// overflowing intermediate squares for extreme (but finite) transforms.
inline bool cubism_mask_density(double a, double b, double c, double d, double &density) {
    if (!std::isfinite(a) || !std::isfinite(b) || !std::isfinite(c) || !std::isfinite(d)) return false;
    const double magnitude = std::max({std::abs(a), std::abs(b), std::abs(c), std::abs(d)});
    if (magnitude == 0) return false;
    a /= magnitude; b /= magnitude; c /= magnitude; d /= magnitude;
    density = magnitude * (0.5 * std::hypot(a + d, b - c) + 0.5 * std::hypot(a - d, b + c));
    return std::isfinite(density) && density > 0;
}

// A zero legacy limit uses the safety cap at the requested pixel density.
// Round outward and keep a uniform canvas scale: extra pixels are transparent
// padding, not independent X/Y stretching of the mask geometry.
inline bool cubism_mask_size(double width, double height, int limit, CubismMaskSize &result, double density = 1) {
    if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0
            || !std::isfinite(density) || density <= 0) return false;
    const int cap = limit <= 0 ? 4096 : std::clamp(limit, 2, 4096);
    result.scale = std::min(density, cap / std::max(width, height));
    result.width = std::clamp(static_cast<int>(std::ceil(width * result.scale)), 2, cap);
    result.height = std::clamp(static_cast<int>(std::ceil(height * result.scale)), 2, cap);
    return true;
}

#endif
