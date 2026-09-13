// SPDX-License-Identifier: MIT
#ifndef CUBISM_EFFECT_HPP
#define CUBISM_EFFECT_HPP
#include <godot_cpp/classes/node.hpp>

class CubismEffect : public godot::Node {
    GDCLASS(CubismEffect, godot::Node)
    friend class CubismModel2D;
    bool enabled = true;
    int64_t priority = 0;
    uint64_t membership_revision = 0;
    godot::Error write(const godot::StringName &id, double value, double weight, int operation);

protected:
    static void _bind_methods();
    void _notification(int what);

public:
    void set_enabled(bool value) { enabled = value; }
    bool get_enabled() const { return enabled; }
    void set_effect_priority(int64_t value) { priority = value; }
    int64_t get_effect_priority() const { return priority; }
    godot::Error set_parameter_value(const godot::StringName &id, double value, double weight = 1.0) { return write(id, value, weight, 0); }
    godot::Error add_parameter_value(const godot::StringName &id, double value, double weight = 1.0) { return write(id, value, weight, 1); }
    godot::Error multiply_parameter_value(const godot::StringName &id, double value, double weight = 1.0) { return write(id, value, weight, 2); }
};
#endif
