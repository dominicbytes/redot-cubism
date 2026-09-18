// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
#ifndef INTERNAL_CUBISM_USER_MODEL
#define INTERNAL_CUBISM_USER_MODEL


// ----------------------------------------------------------------- include(s)
#include <gd_cubism.hpp>

#include <Model/CubismUserModel.hpp>
#include <Motion/CubismMotion.hpp>
#include <Motion/CubismMotionQueueManager.hpp>
#include <Utils/CubismString.hpp>
#include <CubismFramework.hpp>
#include <CubismModelSettingJson.hpp>

#include <private/internal_cubism_renderer_resource.hpp>
#include <cubism_model_resource.hpp>


// ------------------------------------------------------------------ define(s)
// --------------------------------------------------------------- namespace(s)
// -------------------------------------------------------------------- enum(s)
// ------------------------------------------------------------------- const(s)
// ------------------------------------------------------------------ static(s)
// ----------------------------------------------------------- class:forward(s)
class GDCubismEffectBreath;
class GDCubismEffectCustom;
class GDCubismEffectEyeBlink;
class GDCubismEffectHitArea;


// ------------------------------------------------------------------- class(s)
class InternalCubismUserModel : public Csm::CubismUserModel {
    friend GDCubismUserModel;
    friend GDCubismEffectBreath;
    friend GDCubismEffectCustom;
    friend GDCubismEffectEyeBlink;
    friend GDCubismEffectHitArea;

    enum EFFECT_CALL {
        EFFECT_CALL_INIT,
        EFFECT_CALL_TERM,
        EFFECT_CALL_PROLOGUE,
        EFFECT_CALL_PROCESS,
        EFFECT_CALL_EPILOGUE
    };

public:
    InternalCubismUserModel(GDCubismUserModel *owner_viewport);
    virtual ~InternalCubismUserModel();

public:
    GDCubismUserModel *_owner_viewport = nullptr;

private:
    InternalCubismRendererResource _renderer_resource;
    GDCubismUserModel::moc3FileFormatVersion _moc3_file_format_version;
    String _model_pathname;
    Csm::ICubismModelSetting* _model_setting;
    Csm::csmVector<Csm::CubismIdHandle> _list_eye_blink;
    Csm::csmVector<Csm::CubismIdHandle> _list_lipsync;
    Csm::csmMap<Csm::csmString,Csm::CubismExpressionMotion*> _map_expression;
    Csm::csmMap<Csm::csmString,Csm::CubismMotion*> _map_motion;
    Csm::csmMap<Csm::csmString,PackedByteArray> motion_buffers;
    Csm::csmMap<Csm::csmString,double> motion_fps;
    Csm::csmMap<Csm::csmString,PackedStringArray> motion_parameters;
    Csm::csmMap<Csm::csmString,PackedByteArray> expression_buffers;
    PackedStringArray expression_ids;
    bool clearing_expression = false;
    bool blending_expression = false;
    double expression_blend_weight = 1.0;
    double expression_blend_start = 1.0;
    double expression_blend_duration = 0.0;
    double expression_blend_elapsed = 0.0;
    bool expression_blend_first_step = false;
    void reset_expression_manager();
    Dictionary load_error;
    bool resource_mode = false;
    bool resource_premultiplied_alpha = false;
    bool primary_motion_updated = false;
    uint64_t processed_bytes = 0;
    Dictionary source_fingerprints;
    TypedArray<Texture2D> imported_textures;
    String resolve_file(const char *filename) const;
    bool fail_load(const String &path, const String &message, Error code = ERR_INVALID_DATA);
    bool read_buffer(const String &path, PackedByteArray &buffer, bool json = true, bool optional_raw = false);

public:
    bool get_premultiplied_alpha() const { return resource_premultiplied_alpha; }
    bool model_load(const String &model_pathname, const Ref<CubismModelResource> &resource = Ref<CubismModelResource>());
    bool model_load_resource();
    Dictionary get_load_error() const { return load_error.duplicate(); }
    void pro_update(const double delta);
    void efx_update(const double delta);
    void epi_update(const double delta);
    void update_node();
    void clear();

    void stop();

    void expression_set(const char* expression_id);
    void expression_stop();
    Error preferred_expression_set(const StringName &id, double fade_seconds);
    void preferred_expression_clear(double fade_seconds);
    PackedStringArray get_expression_ids() const { return expression_ids; }
    Vector2 look_direction(const Vector2 &local_point) const;
    bool hit_test(const StringName &name, const Vector2 &local_point);
    Array get_debug_rectangles(bool hit_areas) const;
    PackedStringArray get_lip_sync_ids() const;
    PackedStringArray get_motion_parameter_ids(const StringName &group, int index) const;
    bool has_authored_parameter(const String &id) const;

    Csm::CubismMotionQueueEntryHandle motion_start(const char* group, const int32_t no, const int32_t priority, const bool loop, const bool loop_fade_in);
    void motion_stop();
    Csm::CubismMotion *create_motion(const String &group, int index, bool loop, double &period);

    virtual void MotionEventFired(const Csm::csmString& eventValue) override;

private:
    bool expression_load();
    bool physics_load();
    bool pose_load();
    bool userdata_load();
    bool motion_load();

    void effect_init();
    void effect_term();
    void effect_batch(const double delta, const EFFECT_CALL efx_call);
};


// ------------------------------------------------------------------ method(s)


#endif // INTERNAL_CUBISM_USER_MODEL
