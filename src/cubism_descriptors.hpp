// SPDX-License-Identifier: MIT
#ifndef CUBISM_DESCRIPTORS_HPP
#define CUBISM_DESCRIPTORS_HPP

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>

using namespace godot;

class CubismMotionEvent : public Resource {
    GDCLASS(CubismMotionEvent, Resource);
protected:
    static void _bind_methods();
private:
    double time_seconds = 0.0;
    String value;
public:
    void set_time_seconds(double value) { time_seconds = value; emit_changed(); }
    double get_time_seconds() const { return time_seconds; }
    void set_value(const String &value) { this->value = value; emit_changed(); }
    String get_value() const { return value; }
};

class CubismExpressionParameter : public Resource {
    GDCLASS(CubismExpressionParameter, Resource);
public:
    enum Operation { ADD, MULTIPLY, OVERWRITE };
protected:
    static void _bind_methods();
private:
    StringName id;
    double value = 0.0;
    Operation operation = ADD;
public:
    void set_id(const StringName &value) { id = value; emit_changed(); }
    StringName get_id() const { return id; }
    void set_value(double value) { this->value = value; emit_changed(); }
    double get_value() const { return value; }
    void set_operation(Operation value) { operation = value; emit_changed(); }
    Operation get_operation() const { return operation; }
};

class CubismMotionDescriptor : public Resource {
    GDCLASS(CubismMotionDescriptor, Resource);
protected:
    static void _bind_methods();
private:
    StringName id;
    StringName group;
    int index = 0;
    String source_path;
    String sound_path;
    Ref<AudioStream> sound;
    double fade_in_seconds = -1.0;
    double fade_out_seconds = -1.0;
    double duration_seconds = 0.0;
    bool loop = false;
    Ref<Animation> animation;
    TypedArray<CubismMotionEvent> events;
    Dictionary metadata;
public:
    void set_id(const StringName &value) { id = value; emit_changed(); }
    StringName get_id() const { return id; }
    void set_group(const StringName &value) { group = value; emit_changed(); }
    StringName get_group() const { return group; }
    void set_index(int value) { index = value; emit_changed(); }
    int get_index() const { return index; }
    void set_source_path(const String &value) { source_path = value; emit_changed(); }
    String get_source_path() const { return source_path; }
    void set_sound_path(const String &value) { sound_path = value; emit_changed(); }
    String get_sound_path() const { return sound_path; }
    void set_sound(const Ref<AudioStream> &value) { sound = value; emit_changed(); }
    Ref<AudioStream> get_sound() const { return sound; }
    void set_fade_in_seconds(double value) { fade_in_seconds = value; emit_changed(); }
    double get_fade_in_seconds() const { return fade_in_seconds; }
    void set_fade_out_seconds(double value) { fade_out_seconds = value; emit_changed(); }
    double get_fade_out_seconds() const { return fade_out_seconds; }
    void set_duration_seconds(double value) { duration_seconds = value; emit_changed(); }
    double get_duration_seconds() const { return duration_seconds; }
    void set_loop(bool value) { loop = value; emit_changed(); }
    bool get_loop() const { return loop; }
    void set_animation(const Ref<Animation> &value) { animation = value; emit_changed(); }
    Ref<Animation> get_animation() const { return animation; }
    void set_events(const TypedArray<CubismMotionEvent> &value) { events = value; emit_changed(); }
    TypedArray<CubismMotionEvent> get_events() const { return events; }
    void set_metadata(const Dictionary &value) { metadata = value; emit_changed(); }
    Dictionary get_metadata() const { return metadata; }
};

class CubismExpressionDescriptor : public Resource {
    GDCLASS(CubismExpressionDescriptor, Resource);
protected:
    static void _bind_methods();
private:
    StringName id;
    String source_path;
    double fade_in_seconds = -1.0;
    double fade_out_seconds = -1.0;
    TypedArray<CubismExpressionParameter> parameters;
public:
    void set_id(const StringName &value) { id = value; emit_changed(); }
    StringName get_id() const { return id; }
    void set_source_path(const String &value) { source_path = value; emit_changed(); }
    String get_source_path() const { return source_path; }
    void set_fade_in_seconds(double value) { fade_in_seconds = value; emit_changed(); }
    double get_fade_in_seconds() const { return fade_in_seconds; }
    void set_fade_out_seconds(double value) { fade_out_seconds = value; emit_changed(); }
    double get_fade_out_seconds() const { return fade_out_seconds; }
    void set_parameters(const TypedArray<CubismExpressionParameter> &value) { parameters = value; emit_changed(); }
    TypedArray<CubismExpressionParameter> get_parameters() const { return parameters; }
};

VARIANT_ENUM_CAST(CubismExpressionParameter::Operation);

#endif
