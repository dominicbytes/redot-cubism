// SPDX-License-Identifier: MIT
#include "cubism_effect.hpp"
#include "cubism_model_2d.hpp"

using namespace godot;

void CubismEffect::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_enabled", "value"), &CubismEffect::set_enabled);
    ClassDB::bind_method(D_METHOD("get_enabled"), &CubismEffect::get_enabled);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "get_enabled");
    ClassDB::bind_method(D_METHOD("set_effect_priority", "value"), &CubismEffect::set_effect_priority);
    ClassDB::bind_method(D_METHOD("get_effect_priority"), &CubismEffect::get_effect_priority);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "effect_priority"), "set_effect_priority", "get_effect_priority");
    ClassDB::bind_method(D_METHOD("set_parameter_value", "id", "value", "weight"), &CubismEffect::set_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("add_parameter_value", "id", "value", "weight"), &CubismEffect::add_parameter_value, DEFVAL(1.0));
    ClassDB::bind_method(D_METHOD("multiply_parameter_value", "id", "value", "weight"), &CubismEffect::multiply_parameter_value, DEFVAL(1.0));
    ADD_SIGNAL(MethodInfo("effect_process", PropertyInfo(Variant::OBJECT, "model", PROPERTY_HINT_RESOURCE_TYPE, "CubismModel2D"), PropertyInfo(Variant::FLOAT, "delta")));
}

Error CubismEffect::write(const StringName &id, double value, double weight, int operation) {
    if (is_queued_for_deletion()) return ERR_UNAVAILABLE;
    auto *model = Object::cast_to<CubismModel2D>(get_parent());
    return model ? model->write_custom_effect(get_instance_id(), membership_revision, id, value, weight, operation) : ERR_UNAVAILABLE;
}

void CubismEffect::_notification(int what) {
    if (what == NOTIFICATION_ENTER_TREE || what == NOTIFICATION_EXIT_TREE) {
        ++membership_revision;
        return;
    }
    if (what != NOTIFICATION_PREDELETE) return;
    auto *model = Object::cast_to<CubismModel2D>(get_parent());
    if (model && model->runtime->is_native_busy()) {
        cancel_free();
        queue_free();
    }
}
