// SPDX-License-Identifier: MIT
#include "cubism_model_2d.hpp"
#include "cubism_effect.hpp"
#include <algorithm>
#include <cmath>

void CubismModel2D::begin_custom_effects() {
    custom_effects.clear();
    custom_effect_generation = generation;
    const Array children = get_children();
    for (int index = 0; index < children.size(); ++index) {
        auto *effect = Object::cast_to<CubismEffect>(children[index]);
        if (!effect || !effect->get_enabled() || !effect->can_process() || effect->is_queued_for_deletion()) continue;
        custom_effects.push_back({effect->get_instance_id(), effect->membership_revision, effect->get_effect_priority(), effect->get_name()});
    }
    std::sort(custom_effects.begin(), custom_effects.end(), [](const CustomEffect &a, const CustomEffect &b) {
        return a.priority != b.priority ? a.priority < b.priority : a.name < b.name;
    });
}

void CubismModel2D::apply_custom_effects(double delta) {
    for (const auto &entry : custom_effects) {
        if (generation != custom_effect_generation || is_queued_for_deletion() || !is_inside_tree()) break;
        auto *effect = Object::cast_to<CubismEffect>(ObjectDB::get_instance(entry.id));
        if (!effect || effect->membership_revision != entry.revision || effect->get_parent() != this || effect->is_queued_for_deletion() || !effect->can_process()) continue;
        active_custom_effect = entry.id;
        active_custom_effect_revision = entry.revision;
        effect->emit_signal("effect_process", this, delta);
        active_custom_effect = 0;
        active_custom_effect_revision = 0;
    }
}

Error CubismModel2D::write_custom_effect(uint64_t effect, uint64_t revision, const StringName &id, double value, double weight, int operation) {
    if (!effect || effect != active_custom_effect || revision != active_custom_effect_revision || generation != custom_effect_generation ||
            !is_ready() || !is_inside_tree() || is_queued_for_deletion()) return ERR_UNAVAILABLE;
    if (!std::isfinite(value) || !std::isfinite(weight) || weight < 0.0 || weight > 1.0) return ERR_INVALID_PARAMETER;
    const int index = parameter_index(id);
    if (index < 0) return ERR_DOES_NOT_EXIST;
    runtime->apply_parameter_write({index, value, weight, operation});
    return OK;
}
