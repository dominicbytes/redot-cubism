// SPDX-License-Identifier: MIT
#ifndef CUBISM_TEXTURE_IMPORT_HPP
#define CUBISM_TEXTURE_IMPORT_HPP
#include "cubism_model_resource.hpp"

// Provision immutable, lossless texture Resources without changing shared PNG imports.
godot::Error provision_cubism_textures(const godot::Ref<CubismModelResource> &model);
#endif
