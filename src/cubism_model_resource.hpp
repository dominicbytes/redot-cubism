// SPDX-License-Identifier: MIT
#ifndef CUBISM_MODEL_RESOURCE_HPP
#define CUBISM_MODEL_RESOURCE_HPP

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/typed_array.hpp>

using namespace godot;

// Imported data only. Runtime instances must validate and consume this data
// without storing native handles here or mutating shared descriptor metadata.
class CubismModelResource : public Resource {
    GDCLASS(CubismModelResource, Resource);
protected:
    static void _bind_methods();
private:
    godot::Ref<godot::Resource> runtime_extension;
    String source_model_path;
    String source_hash;
    String import_fingerprint;
    String moc_path;
    int moc_version = 0;
    PackedStringArray texture_paths;
    Dictionary layout;
    Dictionary dependency_fingerprints;
    TypedArray<Texture2D> textures;
    Dictionary motion_groups;
    Array expressions;
    String physics_path;
    String pose_path;
    String user_data_path;
    String display_info_path;
    TypedArray<Dictionary> hit_areas;
    PackedStringArray eye_blink_parameter_ids;
    PackedStringArray lip_sync_parameter_ids;
    Vector2 canvas_size;
    Vector2 canvas_origin;
    double pixels_per_unit = 0.0;
    PackedStringArray dependency_paths;
    PackedStringArray import_warnings;
    int import_schema_version = 1;
    Dictionary sdk_compatibility;
    Dictionary import_options;
    Dictionary metadata;
public:
    void set_runtime_extension(const godot::Ref<godot::Resource> &value) { runtime_extension = value; emit_changed(); }
    godot::Ref<godot::Resource> get_runtime_extension() const { return runtime_extension; }
    void set_source_model_path(const String &value) { source_model_path = value; emit_changed(); }
    String get_source_model_path() const { return source_model_path; }
    void set_source_hash(const String &value) { source_hash = value; emit_changed(); }
    String get_source_hash() const { return source_hash; }
    void set_import_fingerprint(const String &value) { import_fingerprint = value; emit_changed(); }
    String get_import_fingerprint() const { return import_fingerprint; }
    void set_moc_path(const String &value) { moc_path = value; emit_changed(); }
    String get_moc_path() const { return moc_path; }
    void set_moc_version(int value) { moc_version = value; emit_changed(); }
    int get_moc_version() const { return moc_version; }
    void set_texture_paths(const PackedStringArray &value) { texture_paths = value; emit_changed(); }
    PackedStringArray get_texture_paths() const { return texture_paths; }
    void set_layout(const Dictionary &value) { layout = value; emit_changed(); }
    Dictionary get_layout() const { return layout; }
    void set_dependency_fingerprints(const Dictionary &value) { dependency_fingerprints = value; emit_changed(); }
    Dictionary get_dependency_fingerprints() const { return dependency_fingerprints; }
    void set_textures(const TypedArray<Texture2D> &value) { textures = value; emit_changed(); }
    TypedArray<Texture2D> get_textures() const { return textures; }
    void set_motion_groups(const Dictionary &value) { motion_groups = value; emit_changed(); }
    Dictionary get_motion_groups() const { return motion_groups; }
    void set_expressions(const Array &value) { expressions = value; emit_changed(); }
    Array get_expressions() const { return expressions; }
    void set_physics_path(const String &value) { physics_path = value; emit_changed(); }
    String get_physics_path() const { return physics_path; }
    void set_pose_path(const String &value) { pose_path = value; emit_changed(); }
    String get_pose_path() const { return pose_path; }
    void set_user_data_path(const String &value) { user_data_path = value; emit_changed(); }
    String get_user_data_path() const { return user_data_path; }
    void set_display_info_path(const String &value) { display_info_path = value; emit_changed(); }
    String get_display_info_path() const { return display_info_path; }
    void set_hit_areas(const TypedArray<Dictionary> &value) { hit_areas = value; emit_changed(); }
    TypedArray<Dictionary> get_hit_areas() const { return hit_areas; }
    void set_eye_blink_parameter_ids(const PackedStringArray &value) { eye_blink_parameter_ids = value; emit_changed(); }
    PackedStringArray get_eye_blink_parameter_ids() const { return eye_blink_parameter_ids; }
    void set_lip_sync_parameter_ids(const PackedStringArray &value) { lip_sync_parameter_ids = value; emit_changed(); }
    PackedStringArray get_lip_sync_parameter_ids() const { return lip_sync_parameter_ids; }
    void set_canvas_size(const Vector2 &value) { canvas_size = value; emit_changed(); }
    Vector2 get_canvas_size() const { return canvas_size; }
    void set_canvas_origin(const Vector2 &value) { canvas_origin = value; emit_changed(); }
    Vector2 get_canvas_origin() const { return canvas_origin; }
    void set_pixels_per_unit(double value) { pixels_per_unit = value; emit_changed(); }
    double get_pixels_per_unit() const { return pixels_per_unit; }
    void set_dependency_paths(const PackedStringArray &value) { dependency_paths = value; emit_changed(); }
    PackedStringArray get_dependency_paths() const { return dependency_paths; }
    void set_import_warnings(const PackedStringArray &value) { import_warnings = value; emit_changed(); }
    PackedStringArray get_import_warnings() const { return import_warnings; }
    void set_import_schema_version(int value) { import_schema_version = value; emit_changed(); }
    int get_import_schema_version() const { return import_schema_version; }
    void set_sdk_compatibility(const Dictionary &value) { sdk_compatibility = value; emit_changed(); }
    Dictionary get_sdk_compatibility() const { return sdk_compatibility; }
    void set_import_options(const Dictionary &value) { import_options = value; emit_changed(); }
    Dictionary get_import_options() const { return import_options; }
    void set_metadata(const Dictionary &value) { metadata = value; emit_changed(); }
    Dictionary get_metadata() const { return metadata; }
};

#endif
