// SPDX-License-Identifier: MIT
#ifndef CUBISM_EXPORT_VALIDATOR_HPP
#define CUBISM_EXPORT_VALIDATOR_HPP
#include "cubism_model_resource.hpp"
#include <godot_cpp/classes/ref_counted.hpp>

// Shared precondition for checked export and raw dependency injection.
class CubismExportValidator : public godot::RefCounted {
    GDCLASS(CubismExportValidator, godot::RefCounted);
protected:
    static void _bind_methods();
public:
    static godot::Dictionary validate_file(const godot::String &path);
    static godot::Dictionary validate_model(const godot::Ref<CubismModelResource> &model);
};
#endif
