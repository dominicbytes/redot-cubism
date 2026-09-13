// SPDX-License-Identifier: MIT
#include "redot_cubism_model_setting.hpp"
#include <cubism_descriptors.hpp>
#include <Id/CubismIdManager.hpp>
#include <cmath>
#include <limits>

namespace {
bool text_valid(const String &value, bool empty = false) {
    if ((!empty && value.is_empty()) || value.length() > 4096) return false;
    for (int i = 0; i < value.length(); ++i) if (value[i] < 32 || value[i] == 127) return false;
    return true;
}
std::string utf8(const String &value) { return std::string(value.utf8().get_data()); }
bool path_valid(const String &value, const String &suffix, bool optional = false) {
    if (value.is_empty()) return optional;
    if (!text_valid(value) || !value.begins_with("res://") || value.substr(6).contains(":")
        || value.contains("\\") || !value.ends_with(suffix)) return false;
    const PackedStringArray parts = value.substr(6).split("/", true);
    for (int i = 0; i < parts.size(); ++i) if (parts[i].is_empty() || parts[i] == "." || parts[i] == "..") return false;
    return true;
}
bool finite_float(double value) { return std::isfinite(value) && std::abs(value) <= std::numeric_limits<float>::max(); }
}

RedotCubismModelSetting::RedotCubismModelSetting(const Ref<CubismModelResource> &resource, String &error) {
    error = "Invalid imported Cubism resource. Reimport the source model.";
    if (resource.is_null() || resource->get_import_schema_version() != 1) return;
    if (resource->get_mask_quality() < 0) {
        error = "Invalid rendering/mask_quality in imported Cubism resource. Reimport the source model.";
        return;
    }
    if (resource->get_import_options().get("rendering/premultiplied_alpha", false).get_type() != Variant::BOOL) {
        error = "Invalid rendering/premultiplied_alpha in imported Cubism resource. Reimport the source model.";
        return;
    }
    if (!path_valid(resource->get_moc_path(), ".moc3")
        || !path_valid(resource->get_physics_path(), ".physics3.json", true)
        || !path_valid(resource->get_pose_path(), ".pose3.json", true)
        || !path_valid(resource->get_user_data_path(), ".userdata3.json", true)
        || !path_valid(resource->get_display_info_path(), ".cdi3.json", true)) return;
    moc = utf8(resource->get_moc_path());
    physics = utf8(resource->get_physics_path());
    pose = utf8(resource->get_pose_path());
    user_data = utf8(resource->get_user_data_path());
    display_info = utf8(resource->get_display_info_path());
    const PackedStringArray texture_paths = resource->get_texture_paths();
    const auto texture_resources = resource->get_textures();
    if (texture_paths.size() > 64 || texture_paths.size() != texture_resources.size()) return;
    for (int i = 0; i < texture_paths.size(); ++i) {
        const Ref<Texture2D> texture = texture_resources[i];
        if (!path_valid(texture_paths[i], ".png") || texture.is_null()) return;
        const Variant encoding = texture->get_meta("cubism_premultiplied_alpha", false);
        if (encoding.get_type() != Variant::BOOL || bool(encoding) != resource->get_premultiplied_alpha()) {
            error = "Cubism texture alpha encoding differs from the model import option. Import the source model before rendering.";
            return;
        }
        textures.push_back(utf8(texture_paths[i]));
    }
    if (!texture_paths.is_empty()) texture_directory = utf8(texture_paths[0].get_base_dir());
    const Array expression_resources = resource->get_expressions();
    if (expression_resources.size() > 512) return;
    for (int i = 0; i < expression_resources.size(); ++i) {
        const Ref<CubismExpressionDescriptor> descriptor = expression_resources[i];
        if (descriptor.is_null() || !text_valid(descriptor->get_id()) || !path_valid(descriptor->get_source_path(), ".exp3.json")) return;
        expressions.push_back({utf8(descriptor->get_id()), utf8(descriptor->get_source_path())});
    }
    const Dictionary motion_groups = resource->get_motion_groups();
    const Array names = motion_groups.keys();
    if (names.size() > 64) return;
    for (int i = 0; i < names.size(); ++i) {
        if ((names[i].get_type() != Variant::STRING && names[i].get_type() != Variant::STRING_NAME)
            || !text_valid(names[i]) || motion_groups[names[i]].get_type() != Variant::ARRAY) return;
        const String name = names[i];
        Group entry;
        entry.name = utf8(name);
        const Array motions = motion_groups[names[i]];
        if (motions.size() > 512) return;
        for (int j = 0; j < motions.size(); ++j) {
            const Ref<CubismMotionDescriptor> descriptor = motions[j];
            if (descriptor.is_null() || descriptor->get_group() != name || descriptor->get_index() != j
                || !path_valid(descriptor->get_source_path(), ".motion3.json")
                || !(path_valid(descriptor->get_sound_path(), ".wav", true) || path_valid(descriptor->get_sound_path(), ".ogg", true))
                || !finite_float(descriptor->get_fade_in_seconds()) || !finite_float(descriptor->get_fade_out_seconds())) return;
            entry.motions.push_back({utf8(descriptor->get_source_path()), utf8(descriptor->get_sound_path()),
                float(descriptor->get_fade_in_seconds()), float(descriptor->get_fade_out_seconds())});
        }
        groups.push_back(std::move(entry));
    }
    auto *ids = Csm::CubismFramework::GetIdManager();
    const auto areas = resource->get_hit_areas();
    if (areas.size() > 4096) return;
    for (int i = 0; i < areas.size(); ++i) {
        const Dictionary area = areas[i];
        if (area.get("Id", Variant()).get_type() != Variant::STRING || area.get("Name", Variant()).get_type() != Variant::STRING
            || !text_valid(area["Id"]) || !text_valid(area["Name"])) return;
        hit_areas.push_back({utf8(area["Name"]), ids->GetId(utf8(area["Id"]).c_str())});
    }
    for (int kind = 0; kind < 2; ++kind) {
        const PackedStringArray parameters = kind == 0 ? resource->get_eye_blink_parameter_ids() : resource->get_lip_sync_parameter_ids();
        if (parameters.size() > 4096) return;
        auto &target = kind == 0 ? eye_blink : lip_sync;
        for (int i = 0; i < parameters.size(); ++i) {
            if (!text_valid(parameters[i])) return;
            target.push_back(ids->GetId(utf8(parameters[i]).c_str()));
        }
    }
    const Dictionary values = resource->get_layout();
    const Array keys = values.keys();
    if (keys.size() > 4096) return;
    for (int i = 0; i < keys.size(); ++i) {
        const Variant value = values[keys[i]];
        if (keys[i].get_type() != Variant::STRING || !text_valid(keys[i])
            || (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) || !finite_float(value)) return;
        layout.push_back({utf8(keys[i]), float(double(value))});
    }
    error = String();
}

const RedotCubismModelSetting::Group *RedotCubismModelSetting::group(const char *name) const {
    if (name) for (const auto &entry : groups) if (entry.name == name) return &entry;
    return nullptr;
}
const RedotCubismModelSetting::Motion *RedotCubismModelSetting::motion(const char *name, int index) const {
    const Group *entry = group(name);
    return entry && index >= 0 && size_t(index) < entry->motions.size() ? &entry->motions[index] : nullptr;
}
const char *RedotCubismModelSetting::GetTextureFileName(int index) { return index >= 0 && size_t(index) < textures.size() ? textures[index].c_str() : ""; }
Csm::CubismIdHandle RedotCubismModelSetting::GetHitAreaId(int index) { return index >= 0 && size_t(index) < hit_areas.size() ? hit_areas[index].id : nullptr; }
const char *RedotCubismModelSetting::GetHitAreaName(int index) { return index >= 0 && size_t(index) < hit_areas.size() ? hit_areas[index].name.c_str() : ""; }
const char *RedotCubismModelSetting::GetExpressionName(int index) { return index >= 0 && size_t(index) < expressions.size() ? expressions[index].name.c_str() : ""; }
const char *RedotCubismModelSetting::GetExpressionFileName(int index) { return index >= 0 && size_t(index) < expressions.size() ? expressions[index].file.c_str() : ""; }
const char *RedotCubismModelSetting::GetMotionGroupName(int index) { return index >= 0 && size_t(index) < groups.size() ? groups[index].name.c_str() : ""; }
int RedotCubismModelSetting::GetMotionCount(const char *name) { const Group *entry = group(name); return entry ? entry->motions.size() : 0; }
const char *RedotCubismModelSetting::GetMotionFileName(const char *name, int index) { const Motion *entry = motion(name, index); return entry ? entry->file.c_str() : ""; }
const char *RedotCubismModelSetting::GetMotionSoundFileName(const char *name, int index) { const Motion *entry = motion(name, index); return entry ? entry->sound.c_str() : ""; }
float RedotCubismModelSetting::GetMotionFadeInTimeValue(const char *name, int index) { const Motion *entry = motion(name, index); return entry ? entry->fade_in : -1.0f; }
float RedotCubismModelSetting::GetMotionFadeOutTimeValue(const char *name, int index) { const Motion *entry = motion(name, index); return entry ? entry->fade_out : -1.0f; }
bool RedotCubismModelSetting::GetLayoutMap(Csm::csmMap<Csm::csmString, float> &out) {
    for (const auto &entry : layout) out[entry.first.c_str()] = entry.second;
    return !layout.empty();
}
Csm::CubismIdHandle RedotCubismModelSetting::GetEyeBlinkParameterId(int index) { return index >= 0 && size_t(index) < eye_blink.size() ? eye_blink[index] : nullptr; }
Csm::CubismIdHandle RedotCubismModelSetting::GetLipSyncParameterId(int index) { return index >= 0 && size_t(index) < lip_sync.size() ? lip_sync[index] : nullptr; }
