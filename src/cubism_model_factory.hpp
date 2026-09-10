// SPDX-License-Identifier: MIT
#ifndef CUBISM_MODEL_FACTORY_HPP
#define CUBISM_MODEL_FACTORY_HPP
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
class CubismModelFactory : public godot::RefCounted {
    GDCLASS(CubismModelFactory, godot::RefCounted);
protected:
    static void _bind_methods();
public:
    static godot::Dictionary build(const godot::String &source_path, bool strict_optional_files = false);
};
#endif
