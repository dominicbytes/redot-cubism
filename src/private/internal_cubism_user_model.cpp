// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
// ----------------------------------------------------------------- include(s)
#include <gd_cubism.hpp>

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <cubism_manifest_parser.hpp>
#include <private/redot_cubism_model_setting.hpp>
#include <cmath>
#include <algorithm>

#ifdef GD_CUBISM_USE_RENDERER_2D
    #include <private/internal_cubism_renderer_2d.hpp>
#else
    #include <private/internal_cubism_renderer_3d.hpp>
#endif // GD_CUBISM_USE_RENDERER_2D
#include <private/internal_cubism_user_model.hpp>
#include <cubism_animator.hpp>
#include <cubism_procedural_effects.hpp>


// ------------------------------------------------------------------ define(s)
// --------------------------------------------------------------- namespace(s)
using namespace Live2D::Cubism::Framework;


// -------------------------------------------------------------------- enum(s)
// ------------------------------------------------------------------- const(s)
// ------------------------------------------------------------------ static(s)
// ----------------------------------------------------------- class:forward(s)
// ------------------------------------------------------------------- class(s)
InternalCubismUserModel::InternalCubismUserModel(GDCubismUserModel *owner_viewport)
    : CubismUserModel()
    , _moc3_file_format_version(GDCubismUserModel::moc3FileFormatVersion::CSM_MOC_VERSION_UNKNOWN)
    , _renderer_resource(owner_viewport)
    , _owner_viewport(owner_viewport)
    , _model_pathname("")
    , _model_setting(nullptr) {

    _debugMode = false;
}


InternalCubismUserModel::~InternalCubismUserModel() {
    this->clear();
}

bool InternalCubismUserModel::fail_load(const String &path, const String &message, Error code) {
    load_error["code"] = code;
    load_error["path"] = path;
    load_error["message"] = message;
    return false;
}

bool InternalCubismUserModel::read_buffer(const String &path, PackedByteArray &buffer, bool json) {
    Ref<FileAccess> file = FileAccess::open(path, FileAccess::READ);
    if (file.is_null()) return fail_load(path, "Cannot open the declared Cubism file.", ERR_FILE_CANT_OPEN);
    const uint64_t length = file->get_length();
    if (resource_mode && (length > uint64_t(json ? 4 : 64) * 1024 * 1024 || processed_bytes + length > 512ULL * 1024 * 1024)) {
        return fail_load(path, "Imported Cubism source exceeds the runtime input limit.");
    }
    buffer = file->get_buffer(length);
    if (buffer.size() != int64_t(length) || file->get_length() != length) return fail_load(path, "Cubism file changed while reading.");
    if (buffer.is_empty()) return fail_load(path, "The declared Cubism file is empty.", ERR_FILE_CORRUPT);
    if (resource_mode) {
        processed_bytes += length;
        Ref<HashingContext> hash;
        hash.instantiate();
        hash->start(HashingContext::HASH_SHA256);
        hash->update(buffer);
        if (source_fingerprints.get(path, String()) != Variant(hash->finish().hex_encode())) {
            return fail_load(path, "Imported Cubism source is stale or untracked. Reimport the model.");
        }
    }
    if (json) {
        String text;
        if (text.parse_utf8(reinterpret_cast<const char *>(buffer.ptr()), buffer.size()) != OK) return fail_load(path, "Invalid UTF-8 in Cubism JSON.", ERR_PARSE_ERROR);
        if (resource_mode) {
            const Dictionary validation = path.ends_with(".motion3.json") ? CubismManifestParser::parse_motion(text, "runtime", 0, path)
                : path.ends_with(".exp3.json") ? CubismManifestParser::parse_expression(text, "runtime", path)
                : path.ends_with(".physics3.json") ? CubismManifestParser::parse_physics(text)
                : path.ends_with(".pose3.json") ? CubismManifestParser::parse_pose(text)
                : path.ends_with(".userdata3.json") ? CubismManifestParser::parse_user_data(text) : Dictionary();
            if (!bool(validation.get("ok", false))) return fail_load(path, "Imported Cubism JSON no longer passes schema validation.", ERR_PARSE_ERROR);
        }
        Ref<JSON> parser;
        parser.instantiate();
        if (parser->parse(text) != OK || parser->get_data().get_type() != Variant::DICTIONARY) {
            return fail_load(path, "Expected a JSON object: " + parser->get_error_message(), ERR_PARSE_ERROR);
        }
        // R5's numeric parser requires a newline/comma terminator and cannot read
        // Unicode escapes. Redot emits decoded UTF-8 strings and formatted numbers.
        buffer = JSON::stringify(parser->get_data(), "\t", false, true).to_utf8_buffer();
        auto *sdk_json = Utils::CubismJson::Create(buffer.ptr(), buffer.size());
        if (sdk_json == nullptr) return fail_load(path, "JSON is unsupported by the pinned Cubism parser.", ERR_PARSE_ERROR);
        Utils::CubismJson::Delete(sdk_json);
    }
    return true;
}

String InternalCubismUserModel::resolve_file(const char *filename) const {
    const String path = String::utf8(filename);
    return resource_mode ? path : _model_pathname.get_base_dir().path_join(path);
}

bool InternalCubismUserModel::model_load(
    const String &model_pathname, const Ref<CubismModelResource> &resource
) {

    this->_model_pathname = model_pathname;
    this->_updating = true;
    this->_initialized = false;
    this->clear();
    load_error.clear();
    resource_mode = resource.is_valid();
    processed_bytes = 0;
    PackedByteArray buffer;
    if (resource_mode) {
        String error;
        this->_model_setting = CSM_NEW RedotCubismModelSetting(resource, error);
        if (!error.is_empty()) return fail_load(model_pathname, error);
        const Dictionary fingerprints = resource->get_dependency_fingerprints().duplicate();
        source_fingerprints = fingerprints;
        imported_textures = resource->get_textures().duplicate();
    } else {
        if (!read_buffer(model_pathname, buffer)) return false;
        this->_model_setting = CSM_NEW CubismModelSettingJson(buffer.ptr(), buffer.size());
    }

    // setup Live2D model
    if (strcmp(this->_model_setting->GetModelFileName(), "") == 0) {
        return fail_load(model_pathname, "FileReferences.Moc must name a MOC3 file.");
    } else {
        const String moc3_pathname = resolve_file(this->_model_setting->GetModelFileName());

        if (!read_buffer(moc3_pathname, buffer, false)) return false;
        if (buffer.size() < 64) return fail_load(moc3_pathname, "MOC3 header is truncated.", ERR_FILE_CORRUPT);
        const auto version = CubismMoc::GetMocVersionFromBuffer(buffer.ptr(), buffer.size());
        if (version == Live2D::Cubism::Core::csmMocVersion_Unknown || version > Live2D::Cubism::Core::csmGetLatestMocVersion()) {
            return fail_load(moc3_pathname, "MOC3 version is invalid or newer than this Cubism Core.", ERR_FILE_UNRECOGNIZED);
        }
        if (!CubismMoc::HasMocConsistencyFromUnrevivedMoc(buffer.ptr(), buffer.size())) {
            return fail_load(moc3_pathname, "MOC3 consistency check failed.", ERR_FILE_CORRUPT);
        }
        // Framework copies MOC bytes into Core-aligned owned storage.
        this->LoadModel(buffer.ptr(), buffer.size(), true);
        this->_moc3_file_format_version = static_cast<GDCubismUserModel::moc3FileFormatVersion>(version);
    }

    if (this->_model == nullptr) {
        return fail_load(model_pathname, "Cubism model could not be loaded.");
    }
    if (this->_model->GetOffscreenCount() != 0) {
        return fail_load(model_pathname, "This Cubism model requires offscreen compositing, which the Redot canvas renderer does not support.", ERR_UNAVAILABLE);
    }
    for (Csm::csmInt32 i = 0; i < this->_model->GetDrawableCount(); ++i) {
        const auto blend = this->_model->GetDrawableBlendModeType(i);
        const auto color = blend.GetColorBlendType();
        const bool compatible = color == Live2D::Cubism::Core::csmColorBlendType_AddCompatible
            || color == Live2D::Cubism::Core::csmColorBlendType_MultiplyCompatible
            || (color == Live2D::Cubism::Core::csmColorBlendType_Normal
                && blend.GetAlphaBlendType() == Live2D::Cubism::Core::csmAlphaBlendType_Over);
        if (!compatible) {
            return fail_load(model_pathname, "This Cubism model uses a blend mode unsupported by the Redot canvas renderer.", ERR_UNAVAILABLE);
        }
        if (resource_mode && (blend.GetAlphaBlendType() != Live2D::Cubism::Core::csmAlphaBlendType_Over
            || _model->GetDrawableTextureIndex(i) < 0 || _model->GetDrawableTextureIndex(i) >= _model_setting->GetTextureCount())) {
            return fail_load(model_pathname, "Imported texture indices or alpha blend mode are unsupported.");
        }
    }

    // Expression
    if(this->_owner_viewport->enable_load_expressions == true) {
        if (!this->expression_load()) return false;
    }

    // Physics
    if (!this->physics_load()) return false;
    // Pose
    if (!this->pose_load()) return false;
    //UserData
    if (!this->userdata_load()) return false;

    // EyeBlink(Parameters)
    {
        Csm::csmInt32 param_count = this->_model_setting->GetEyeBlinkParameterCount();
        for(Csm::csmInt32 i = 0; i < param_count; ++i)
        {
            this->_list_eye_blink.PushBack(this->_model_setting->GetEyeBlinkParameterId(i));
        }
    }

    // LipSync(Parameters)
    {
        Csm::csmInt32 param_count = this->_model_setting->GetLipSyncParameterCount();
        for(Csm::csmInt32 i = 0; i < param_count; ++i)
        {
            this->_list_lipsync.PushBack(this->_model_setting->GetLipSyncParameterId(i));
        }
    }

    if(this->_model_setting == nullptr || this->_modelMatrix == nullptr) {
        return fail_load(model_pathname, "Cubism did not create model settings and its model matrix.");
    }

    if (resource_mode) {
        Csm::csmMap<Csm::csmString, float> layout;
        if (_model_setting->GetLayoutMap(layout)) {
            const float base_x = _modelMatrix->GetScaleX();
            const float base_y = _modelMatrix->GetScaleY();
            _modelMatrix->SetupFromLayout(layout);
            // Undo the SDK's default normalization so an empty layout keeps the
            // existing pixel-sized model. Layout coordinates use SDK normalized units.
            const float scale_x = _modelMatrix->GetScaleX() / base_x;
            const float scale_y = _modelMatrix->GetScaleY() / base_y;
            const float x = _modelMatrix->GetTranslateX() / base_x * _model->GetPixelsPerUnit();
            const float y = -_modelMatrix->GetTranslateY() / base_y * _model->GetPixelsPerUnit();
            if (!std::isfinite(scale_x) || !std::isfinite(scale_y) || !std::isfinite(x) || !std::isfinite(y)
                || scale_x == 0 || scale_y == 0) return fail_load(model_pathname, "Cubism layout produces a non-finite or singular transform.");
            _renderer_resource.layout_transform = Transform2D(Vector2(scale_x, 0), Vector2(0, scale_y), Vector2(x, y));
        }
    }

    this->_model->SaveParameters();

    // Motion
    if(this->_owner_viewport->enable_load_motions == true) {
        if (!this->motion_load()) return false;
    }

    this->CreateRenderer(
        static_cast<Csm::csmUint32>(this->_model->GetCanvasWidthPixel()),
        static_cast<Csm::csmUint32>(this->_model->GetCanvasHeightPixel()));

    // Resource(Texture)
    if (!this->model_load_resource()) return false;

    this->stop();

    this->_updating = false;
    this->_initialized = true;

    // ------------------------------------------------------------------------
    // The process to make the mesh available immediately after initialization.
    // The process is almost the same as the InternalCubismUserModel::update_node() function.
    {
        #ifdef GD_CUBISM_USE_RENDERER_2D
        InternalCubismRenderer2D* renderer = this->GetRenderer<InternalCubismRenderer2D>();
        #else
        #endif // GD_CUBISM_USE_RENDERER_2D

        renderer->IsPremultipliedAlpha(false);
        renderer->DrawModel();
        renderer->build_model(this->_renderer_resource, this->_owner_viewport);
    }
    // ------------------------------------------------------------------------

    return true;
}


bool InternalCubismUserModel::model_load_resource()
{
    if (resource_mode) {
        this->_renderer_resource.ary_texture = imported_textures.duplicate();
        return true;
    }
    ResourceLoader *res_loader = ResourceLoader::get_singleton();

    this->_renderer_resource.ary_texture.clear();

    for (csmInt32 index = 0; index < this->_model_setting->GetTextureCount(); index++)
    {
        if (strcmp(this->_model_setting->GetTextureFileName(index), "") == 0) continue;

        String gd_filename; gd_filename.parse_utf8(this->_model_setting->GetTextureFileName(index));
        String texture_pathname = this->_model_pathname.get_base_dir().path_join(gd_filename);
        const String extension = texture_pathname.get_extension().to_lower();
        if (extension != "png" && extension != "jpg" && extension != "jpeg" && extension != "webp") {
            return fail_load(texture_pathname, "Cubism textures must be PNG, JPEG or WebP images.", ERR_FILE_UNRECOGNIZED);
        }
        if (texture_pathname.begins_with("res://") ? !res_loader->exists(texture_pathname, "Texture2D") : !FileAccess::file_exists(texture_pathname)) {
            return fail_load(texture_pathname, "The declared Cubism texture is missing.", ERR_FILE_NOT_FOUND);
        }

        Ref<Texture2D> tex;
        // allow dynamically loading image textures for models provided from disk or user data
        if (!res_loader->exists(texture_pathname)) {
            Ref<Image> img = Image::load_from_file(texture_pathname);
            if (img.is_null() || img->is_empty()) return fail_load(texture_pathname, "Cubism texture could not be decoded.");
            tex = ImageTexture::create_from_image(img);
            tex->take_over_path(texture_pathname);
        } else {
            tex = res_loader->load(texture_pathname);
        }
        if (tex.is_null()) return fail_load(texture_pathname, "Cubism texture did not load as Texture2D.");

        this->_renderer_resource.ary_texture.append(tex);
    }
    for (csmInt32 index = 0; index < _model->GetDrawableCount(); ++index) {
        const int texture = _model->GetDrawableTextureIndex(index);
        if (texture < 0 || texture >= _renderer_resource.ary_texture.size()) {
            return fail_load(_model_pathname, "A drawable references a missing texture index.");
        }
    }
    return true;
}


void InternalCubismUserModel::pro_update(const double delta) {
    if(this->IsInitialized() == false) return;
    if(this->_model_setting == nullptr) return;
    if(this->_model == nullptr) return;

    this->effect_batch(delta, EFFECT_CALL_PROLOGUE);

    primary_motion_updated = false;

    if(this->_owner_viewport->parameter_mode == GDCubismUserModel::ParameterMode::FULL_PARAMETER) {
        this->_model->LoadParameters();
        if (_owner_viewport->get_animator()) primary_motion_updated = _owner_viewport->get_animator()->update(this->_model, delta);
        else this->_motionManager->UpdateMotion(this->_model, delta);
        this->_model->SaveParameters();
    }

    if(this->_expressionManager != nullptr) {
        std::vector<float> primary;
        if (blending_expression) {
            primary.reserve(_model->GetParameterCount());
            for (int i = 0; i < _model->GetParameterCount(); ++i) primary.push_back(_model->GetParameterValue(i));
        }
        this->_expressionManager->UpdateMotion(this->_model, delta);
        if (blending_expression) {
            if (!expression_blend_first_step) expression_blend_elapsed += delta;
            expression_blend_first_step = false;
            const double progress = std::min(1.0, expression_blend_elapsed / expression_blend_duration);
            const double eased = 0.5 - 0.5 * std::cos(progress * 3.14159265358979323846);
            expression_blend_weight = expression_blend_start + ((clearing_expression ? 0.0 : 1.0) - expression_blend_start) * eased;
            for (int i = 0; i < _model->GetParameterCount(); ++i) {
                _model->SetParameterValue(i, float(primary[i] + (_model->GetParameterValue(i) - primary[i]) * expression_blend_weight));
            }
            if (progress >= 1.0) {
                blending_expression = false;
                if (clearing_expression) reset_expression_manager();
            }
        }
    }

    this->_model->GetModelOpacity();
}


void InternalCubismUserModel::efx_update(const double delta) {
    if(this->IsInitialized() == false) return;
    if(this->_model_setting == nullptr) return;
    if(this->_model == nullptr) return;

    if(this->_owner_viewport->check_cubism_effect_dirty() == true) {
        this->effect_term();
        this->effect_init();
        this->_owner_viewport->cubism_effect_dirty_reset();
    }

    if (_owner_viewport->get_procedural_effects()) _owner_viewport->get_procedural_effects()->update(_model, float(delta), primary_motion_updated);
    this->effect_batch(delta, EFFECT_CALL_PROCESS);
}


void InternalCubismUserModel::epi_update(const double delta) {
    if(this->IsInitialized() == false) return;
    if(this->_model_setting == nullptr) return;
    if(this->_model == nullptr) return;

    if(this->_owner_viewport->physics_evaluate == true) {
        if(this->_physics != nullptr) { this->_physics->Evaluate(this->_model, delta); }
    }

    if(this->_owner_viewport->pose_update == true) {
        if(this->_pose != nullptr) { this->_pose->UpdateParameters(this->_model, delta); }
    }

    this->_owner_viewport->apply_post_effect_writes();
    this->_model->Update();
    this->effect_batch(delta, EFFECT_CALL_EPILOGUE);
}


void InternalCubismUserModel::update_node() {
    if(this->IsInitialized() == false) return;

    #ifdef GD_CUBISM_USE_RENDERER_2D
    InternalCubismRenderer2D* renderer = this->GetRenderer<InternalCubismRenderer2D>();
    #else
    #endif // GD_CUBISM_USE_RENDERER_2D

    renderer->IsPremultipliedAlpha(false);
    renderer->DrawModel();
    renderer->update(this->_renderer_resource, this->_owner_viewport->mask_viewport_size);
}


void InternalCubismUserModel::clear() {

    this->_initialized = false;
    this->_updating = false;

    this->DeleteRenderer();

    this->_renderer_resource.clear();

    {
        this->expression_stop();
        for(csmMap<csmString,CubismExpressionMotion*>::const_iterator i = this->_map_expression.Begin(); i != this->_map_expression.End(); i++) {
            ACubismMotion::Delete(i->Second);
        }
        this->_map_expression.Clear();
        expression_buffers.Clear();
        expression_ids.clear();
        clearing_expression = false;
        blending_expression = false;
    }

    {
        this->motion_stop();
        for(csmMap<csmString,CubismMotion*>::const_iterator i = this->_map_motion.Begin(); i != this->_map_motion.End(); i++) {
            ACubismMotion::Delete(i->Second);
        }
        this->_map_motion.Clear();
        motion_buffers.Clear();
        motion_fps.Clear();
    }

    this->effect_term();

    this->_list_eye_blink.Clear();
    this->_list_lipsync.Clear();

    if(this->_model_setting != nullptr) {
        this->_initialized = false;

        CSM_DELETE(this->_model_setting);
        this->_model_setting = nullptr;
    }
}


void InternalCubismUserModel::stop() {
    this->expression_stop();
    this->motion_stop();
}


void InternalCubismUserModel::expression_set(const char* expression_id) {
    csmString id = expression_id;

    ACubismMotion* motion = this->_map_expression[csmString(expression_id)];

    if(motion != nullptr) {
        this->_expressionManager->StartMotion(
            motion,
            false
        );
    }
}


void InternalCubismUserModel::expression_stop() {
    if(this->_expressionManager == nullptr) return;
    this->_expressionManager->StopAllMotions();
}

Vector2 InternalCubismUserModel::look_direction(const Vector2 &local_point) const {
    // Renderer layout is axis-aligned and validated with nonzero finite scales.
    // Divide axes separately in double precision, avoiding determinant underflow
    // for small but valid imported layout scales.
    const Transform2D &layout = _renderer_resource.layout_transform;
    const double x = (double(local_point.x) - layout[2].x) / layout[0].x;
    const double y = (double(local_point.y) - layout[2].y) / layout[1].y;
    return Vector2(CLAMP(2.0 * x / _model->GetCanvasWidthPixel(), -1.0, 1.0),
        CLAMP(-2.0 * y / _model->GetCanvasHeightPixel(), -1.0, 1.0));
}

bool InternalCubismUserModel::hit_test(const StringName &name, const Vector2 &local_point) {
    // IsHit inverts the SDK ModelMatrix, including imported layout. The renderer
    // uses pixels relative to the SDK's initial uniform height-two matrix.
    const double scale = 2.0 / _model->GetCanvasHeightPixel();
    const float x = float(double(local_point.x) * scale);
    const float y = float(-double(local_point.y) * scale);
    if (!std::isfinite(x) || !std::isfinite(y)) return false;
    for (int i = 0; i < _model_setting->GetHitAreasCount(); ++i) {
        if (String::utf8(_model_setting->GetHitAreaName(i)) != String(name)) continue;
        const auto id = _model_setting->GetHitAreaId(i);
        const int drawable = _model->GetDrawableIndex(id);
        // R5 IsHit reads the first vertex without checking the vertex count.
        if (drawable >= 0 && _model->GetDrawableVertexCount(drawable) > 0 && IsHit(id, x, y)) return true;
    }
    return false;
}

void InternalCubismUserModel::reset_expression_manager() {
    // R5 keeps a private fade-weight array across StopAllMotions. Recreate only
    // this manager when clearing, so a later play cannot inherit stale weights.
    CSM_DELETE(_expressionManager);
    _expressionManager = CSM_NEW CubismExpressionMotionManager();
    clearing_expression = false;
    blending_expression = false;
    expression_blend_weight = 1.0;
}

Error InternalCubismUserModel::preferred_expression_set(const StringName &id, double fade_seconds) {
    const csmString key = String(id).utf8().ptr();
    if (!expression_buffers.IsExist(key)) return ERR_DOES_NOT_EXIST;
    if (_expressionManager->GetCubismMotionQueueEntries()->GetSize() >= 256) return ERR_BUSY;
    const PackedByteArray buffer = expression_buffers[key];
    auto *motion = static_cast<CubismExpressionMotion *>(LoadExpression(buffer.ptr(), buffer.size(), key.GetRawString()));
    if (!motion) return ERR_INVALID_DATA;
    if (fade_seconds >= 0.0) {
        motion->SetFadeInTime(float(fade_seconds));
        motion->SetFadeOutTime(float(fade_seconds));
    }
    // The SDK queue owns this new instance. Cached legacy expressions are never
    // changed and repeated expression plays cannot share mutable fade settings.
    _expressionManager->StartMotion(motion, true);
    if (blending_expression) {
        // Interrupting a clear restores influence over the incoming fade, rather
        // than jumping the partially cleared expression back to full strength.
        expression_blend_start = expression_blend_weight;
        expression_blend_duration = motion->GetFadeInTime();
        expression_blend_elapsed = 0.0;
        expression_blend_first_step = true;
        if (expression_blend_duration <= 0.0) { blending_expression = false; expression_blend_weight = 1.0; }
    }
    clearing_expression = false;
    return OK;
}

void InternalCubismUserModel::preferred_expression_clear(double fade_seconds) {
    auto *entries = _expressionManager->GetCubismMotionQueueEntries();
    if (entries->GetSize() == 0 || fade_seconds == 0.0) { reset_expression_manager(); return; }
    if (fade_seconds < 0.0) fade_seconds = std::max(0.0f, entries->At(entries->GetSize() - 1)->GetCubismMotion()->GetFadeOutTime());
    if (fade_seconds == 0.0) { reset_expression_manager(); return; }
    // R5's empty-expression blend immediately discards overwrite values. Fade
    // the evaluated expression result against the current primary pose instead.
    clearing_expression = true;
    expression_blend_start = blending_expression ? expression_blend_weight : 1.0;
    blending_expression = true;
    expression_blend_duration = fade_seconds;
    expression_blend_elapsed = 0.0;
    expression_blend_first_step = true;
}


CubismMotionQueueEntryHandle InternalCubismUserModel::motion_start(const char* group, const int32_t no, const int32_t priority, const bool loop, const bool loop_fade_in) {

    csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, no);
    CubismMotion* motion = this->_map_motion[name];
    if (motion == nullptr || priority < GDCubismUserModel::PRIORITY_NONE || priority > GDCubismUserModel::PRIORITY_FORCE) {
        return InvalidMotionQueueEntryHandleValue;
    }

    if (priority == GDCubismUserModel::Priority::PRIORITY_FORCE) {
        this->_motionManager->SetReservePriority(priority);
    } else if (!this->_motionManager->ReserveMotion(priority)) {
        return InvalidMotionQueueEntryHandleValue;
    }

    motion->SetLoop(loop);
    motion->SetLoopFadeIn(loop_fade_in);
    // The owner observes queue completion after SDK iteration. Cached motions
    // never retain a callback pointer to a Redot object or a later playback.

    return this->_motionManager->StartMotionPriority(motion, false, priority);
}


void InternalCubismUserModel::motion_stop() {
    if(this->_motionManager == nullptr) return;
    this->_motionManager->StopAllMotions();
}

CubismMotion *InternalCubismUserModel::create_motion(const String &group, int index, bool loop, double &period) {
    const csmString key = Utils::CubismString::GetFormatedString("%s_%d", group.utf8().ptr(), index);
    if (!motion_buffers.IsExist(key) || !_map_motion.IsExist(key)) return nullptr;
    const PackedByteArray buffer = motion_buffers[key];
    auto *motion = static_cast<CubismMotion *>(LoadMotion(buffer.ptr(), buffer.size(), key.GetRawString()));
    if (!motion) return nullptr;
    motion->SetFadeInTime(_map_motion[key]->GetFadeInTime());
    motion->SetFadeOutTime(_map_motion[key]->GetFadeOutTime());
    motion->SetEffectIds(_list_eye_blink, _list_lipsync);
    motion->SetLoop(loop);
    motion->SetLoopFadeIn(true);
    // R5 V2 includes one frame of endpoint correction in a loop cycle.
    const double fps = motion_fps[key];
    period = motion->GetLoopDuration() + (loop && fps > 0.0 ? 1.0 / fps : 0.0);
    if (loop && (!std::isfinite(fps) || fps <= 0.0)) { ACubismMotion::Delete(motion); return nullptr; }
    return motion;
}


void InternalCubismUserModel::MotionEventFired(const csmString& eventValue) {
    if(this->_owner_viewport != nullptr) {
        String value; value.parse_utf8(eventValue.GetRawString());
        this->_owner_viewport->queue_model_signal("motion_event", value, true);
    }
}


bool InternalCubismUserModel::expression_load() {
    if(this->_model_setting->GetExpressionCount() == 0) return true;

    for (csmInt32 i = 0; i < this->_model_setting->GetExpressionCount(); i++)
    {
        csmString name = this->_model_setting->GetExpressionName(i);

        const String expression_pathname = resolve_file(this->_model_setting->GetExpressionFileName(i));

        PackedByteArray buffer;
        if (!read_buffer(expression_pathname, buffer)) return false;
        CubismExpressionMotion* motion = static_cast<CubismExpressionMotion*>(this->LoadExpression(
            buffer.ptr(),
            buffer.size(),
            this->_model_setting->GetExpressionName(i)
        ));
        if (motion == nullptr) return fail_load(expression_pathname, "Cubism could not create the expression.");

        if(this->_map_expression[name] != nullptr) {
            ACubismMotion::Delete(this->_map_expression[name]);
            this->_map_expression[name] = nullptr;
        }

        this->_map_expression[name] = motion;
        if (_owner_viewport->get_animator()) {
            if (expression_buffers.IsExist(name)) return fail_load(expression_pathname, "Duplicate expression ID.");
            expression_buffers[name] = buffer;
            expression_ids.append(String::utf8(name.GetRawString()));
        }
    }
    return true;
}


bool InternalCubismUserModel::physics_load() {
    if(strcmp(this->_model_setting->GetPhysicsFileName(), "") == 0) return true;

    const String physics_pathname = resolve_file(this->_model_setting->GetPhysicsFileName());

    PackedByteArray buffer;
    if (!read_buffer(physics_pathname, buffer)) return false;
    this->LoadPhysics(buffer.ptr(), buffer.size());
    return _physics != nullptr || fail_load(physics_pathname, "Cubism could not create physics.");
}


bool InternalCubismUserModel::pose_load() {
    if(strcmp(this->_model_setting->GetPoseFileName(), "") == 0) return true;

    const String pose_pathname = resolve_file(this->_model_setting->GetPoseFileName());

    PackedByteArray buffer;
    if (!read_buffer(pose_pathname, buffer)) return false;
    this->LoadPose(buffer.ptr(), buffer.size());
    return _pose != nullptr || fail_load(pose_pathname, "Cubism could not create the pose.");
}


bool InternalCubismUserModel::userdata_load() {
    if(strcmp(this->_model_setting->GetUserDataFile(), "") == 0) return true;

    const String userdata_pathname = resolve_file(this->_model_setting->GetUserDataFile());

    PackedByteArray buffer;
    if (!read_buffer(userdata_pathname, buffer)) return false;
    this->LoadUserData(buffer.ptr(), buffer.size());
    return _modelUserData != nullptr || fail_load(userdata_pathname, "Cubism could not create user data.");
}


bool InternalCubismUserModel::motion_load() {
    if(this->_model_setting->GetMotionGroupCount() == 0) return true;

    for (csmInt32 ig = 0; ig < this->_model_setting->GetMotionGroupCount(); ig++)
    {
        //PreloadMotionGroup(group);
        const csmChar* group = this->_model_setting->GetMotionGroupName(ig);
        const csmInt32 motion_count = this->_model_setting->GetMotionCount(group);

        if(motion_count == 0) continue;

        for (csmInt32 im = 0; im < motion_count; im++)
        {
            csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, im);

            const String motion_pathname = resolve_file(this->_model_setting->GetMotionFileName(group, im));

            PackedByteArray buffer;
            if (!read_buffer(motion_pathname, buffer)) return false;
            CubismMotion* motion = static_cast<CubismMotion*>(this->LoadMotion(
                buffer.ptr(),
                buffer.size(),
                name.GetRawString()
            ));
            if (motion == nullptr) return fail_load(motion_pathname, "Cubism could not create the motion.");

            csmFloat32 fade_time_sec = this->_model_setting->GetMotionFadeInTimeValue(group, im);
            if (fade_time_sec >= 0.0f) {
                motion->SetFadeInTime(fade_time_sec);
            }

            fade_time_sec = this->_model_setting->GetMotionFadeOutTimeValue(group, im);
            if (fade_time_sec >= 0.0f) {
                motion->SetFadeOutTime(fade_time_sec);
            }
            static_cast<CubismMotion*>(motion)->SetEffectIds(this->_list_eye_blink, this->_list_lipsync);

            if(this->_map_motion[name] != nullptr) {
                ACubismMotion::Delete(this->_map_motion[name]);
                this->_map_motion[name] = nullptr;
            }

            this->_map_motion[name] = motion;
            if (_owner_viewport->get_animator()) {
                motion_buffers[name] = buffer;
                const Dictionary json = JSON::parse_string(buffer.get_string_from_utf8());
                const Dictionary metadata = json.get("Meta", Dictionary());
                motion_fps[name] = metadata.get("Fps", 0.0);
            }
        }
    }
    return true;
}


void InternalCubismUserModel::effect_init() {
    effect_batch(0.0, EFFECT_CALL_INIT);
}


void InternalCubismUserModel::effect_term() {
    effect_batch(0.0, EFFECT_CALL_TERM);
}


void InternalCubismUserModel::effect_batch(const double delta, const EFFECT_CALL efx_call) {
    std::vector<uint64_t> effects;
    for (int i = 0; i < _owner_viewport->_list_cubism_effect.GetSize(); ++i) {
        effects.push_back(_owner_viewport->_list_cubism_effect[i]->get_instance_id());
    }
    for (uint64_t id : effects) {
        auto *effect = Object::cast_to<GDCubismEffect>(ObjectDB::get_instance(id));
        if (effect == nullptr || effect->get_parent() != _owner_viewport) continue;
        if (effect->is_queued_for_deletion() && efx_call != EFFECT_CALL_TERM) continue;
        switch(efx_call) {
            case EFFECT_CALL_INIT:      effect->_cubism_init(this);               break;
            case EFFECT_CALL_TERM:      effect->_cubism_term(this);               break;
            case EFFECT_CALL_PROLOGUE:  effect->_cubism_prologue(this, delta);    break;
            case EFFECT_CALL_PROCESS:   effect->_cubism_process(this, delta);     break;
            case EFFECT_CALL_EPILOGUE:  effect->_cubism_epilogue(this, delta);    break;
        }
    }
}


// ------------------------------------------------------------------ method(s)
