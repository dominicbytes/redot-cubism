// SPDX-License-Identifier: MIT
#ifndef REDOT_CUBISM_MODEL_SETTING_HPP
#define REDOT_CUBISM_MODEL_SETTING_HPP
#include <ICubismModelSetting.hpp>
#include <cubism_model_resource.hpp>
#include <string>
#include <vector>

// Runtime-owned snapshot. All returned UTF-8 buffers remain stable until destruction.
class RedotCubismModelSetting : public Csm::ICubismModelSetting {
    struct NamedFile { std::string name, file; };
    struct Motion { std::string file, sound; float fade_in, fade_out; };
    struct Group { std::string name; std::vector<Motion> motions; };
    struct HitArea { std::string name; Csm::CubismIdHandle id; };
    std::string moc, physics, pose, display_info, user_data, texture_directory;
    std::vector<std::string> textures;
    std::vector<NamedFile> expressions;
    std::vector<Group> groups;
    std::vector<HitArea> hit_areas;
    std::vector<Csm::CubismIdHandle> eye_blink, lip_sync;
    std::vector<std::pair<std::string, float>> layout;
    const Group *group(const char *name) const;
    const Motion *motion(const char *name, int index) const;
public:
    RedotCubismModelSetting(const Ref<CubismModelResource> &resource, String &error);
    const char *GetModelFileName() override { return moc.c_str(); }
    Csm::csmInt32 GetTextureCount() override { return textures.size(); }
    const char *GetTextureDirectory() override { return texture_directory.c_str(); }
    const char *GetTextureFileName(Csm::csmInt32 index) override;
    Csm::csmInt32 GetHitAreasCount() override { return hit_areas.size(); }
    Csm::CubismIdHandle GetHitAreaId(Csm::csmInt32 index) override;
    const char *GetHitAreaName(Csm::csmInt32 index) override;
    const char *GetPhysicsFileName() override { return physics.c_str(); }
    const char *GetPoseFileName() override { return pose.c_str(); }
    const char *GetDisplayInfoFileName() override { return display_info.c_str(); }
    Csm::csmInt32 GetExpressionCount() override { return expressions.size(); }
    const char *GetExpressionName(Csm::csmInt32 index) override;
    const char *GetExpressionFileName(Csm::csmInt32 index) override;
    Csm::csmInt32 GetMotionGroupCount() override { return groups.size(); }
    const char *GetMotionGroupName(Csm::csmInt32 index) override;
    Csm::csmInt32 GetMotionCount(const char *name) override;
    const char *GetMotionFileName(const char *name, Csm::csmInt32 index) override;
    const char *GetMotionSoundFileName(const char *name, Csm::csmInt32 index) override;
    float GetMotionFadeInTimeValue(const char *name, Csm::csmInt32 index) override;
    float GetMotionFadeOutTimeValue(const char *name, Csm::csmInt32 index) override;
    const char *GetUserDataFile() override { return user_data.c_str(); }
    bool GetLayoutMap(Csm::csmMap<Csm::csmString, float> &out) override;
    Csm::csmInt32 GetEyeBlinkParameterCount() override { return eye_blink.size(); }
    Csm::CubismIdHandle GetEyeBlinkParameterId(Csm::csmInt32 index) override;
    Csm::csmInt32 GetLipSyncParameterCount() override { return lip_sync.size(); }
    Csm::CubismIdHandle GetLipSyncParameterId(Csm::csmInt32 index) override;
};
#endif
