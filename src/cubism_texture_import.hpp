// SPDX-License-Identifier: MIT
#ifndef CUBISM_TEXTURE_IMPORT_HPP
#define CUBISM_TEXTURE_IMPORT_HPP
#include "cubism_model_resource.hpp"

inline constexpr const char *CUBISM_TEXTURE_POLICY = "lossless_source_rgba_mipmaps_alpha_v3";
godot::String cubism_texture_policy(bool premultiplied);

// Provision immutable, lossless texture Resources without changing shared PNG imports.
godot::Error provision_cubism_textures(const godot::Ref<CubismModelResource> &model);
#endif
