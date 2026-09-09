// SPDX-License-Identifier: MIT
#include "cubism_descriptors.hpp"

void CubismMotionEvent::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_time_seconds", "value"), &CubismMotionEvent::set_time_seconds);
    ClassDB::bind_method(D_METHOD("get_time_seconds"), &CubismMotionEvent::get_time_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_seconds"), "set_time_seconds", "get_time_seconds");
    ClassDB::bind_method(D_METHOD("set_value", "value"), &CubismMotionEvent::set_value);
    ClassDB::bind_method(D_METHOD("get_value"), &CubismMotionEvent::get_value);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "value"), "set_value", "get_value");
}

void CubismExpressionParameter::_bind_methods() {
    BIND_ENUM_CONSTANT(ADD);
    BIND_ENUM_CONSTANT(MULTIPLY);
    BIND_ENUM_CONSTANT(OVERWRITE);
    ClassDB::bind_method(D_METHOD("set_id", "value"), &CubismExpressionParameter::set_id);
    ClassDB::bind_method(D_METHOD("get_id"), &CubismExpressionParameter::get_id);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
    ClassDB::bind_method(D_METHOD("set_value", "value"), &CubismExpressionParameter::set_value);
    ClassDB::bind_method(D_METHOD("get_value"), &CubismExpressionParameter::get_value);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "value"), "set_value", "get_value");
    ClassDB::bind_method(D_METHOD("set_operation", "value"), &CubismExpressionParameter::set_operation);
    ClassDB::bind_method(D_METHOD("get_operation"), &CubismExpressionParameter::get_operation);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "operation", PROPERTY_HINT_ENUM, "Add,Multiply,Overwrite"), "set_operation", "get_operation");
}

void CubismMotionDescriptor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_id", "value"), &CubismMotionDescriptor::set_id);
    ClassDB::bind_method(D_METHOD("get_id"), &CubismMotionDescriptor::get_id);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
    ClassDB::bind_method(D_METHOD("set_group", "value"), &CubismMotionDescriptor::set_group);
    ClassDB::bind_method(D_METHOD("get_group"), &CubismMotionDescriptor::get_group);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "group"), "set_group", "get_group");
    ClassDB::bind_method(D_METHOD("set_index", "value"), &CubismMotionDescriptor::set_index);
    ClassDB::bind_method(D_METHOD("get_index"), &CubismMotionDescriptor::get_index);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "index"), "set_index", "get_index");
    ClassDB::bind_method(D_METHOD("set_source_path", "value"), &CubismMotionDescriptor::set_source_path);
    ClassDB::bind_method(D_METHOD("get_source_path"), &CubismMotionDescriptor::get_source_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_path"), "set_source_path", "get_source_path");
    ClassDB::bind_method(D_METHOD("set_sound_path", "value"), &CubismMotionDescriptor::set_sound_path);
    ClassDB::bind_method(D_METHOD("get_sound_path"), &CubismMotionDescriptor::get_sound_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "sound_path"), "set_sound_path", "get_sound_path");
    ClassDB::bind_method(D_METHOD("set_sound", "value"), &CubismMotionDescriptor::set_sound);
    ClassDB::bind_method(D_METHOD("get_sound"), &CubismMotionDescriptor::get_sound);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "sound", PROPERTY_HINT_RESOURCE_TYPE, "AudioStream"), "set_sound", "get_sound");
    ClassDB::bind_method(D_METHOD("set_fade_in_seconds", "value"), &CubismMotionDescriptor::set_fade_in_seconds);
    ClassDB::bind_method(D_METHOD("get_fade_in_seconds"), &CubismMotionDescriptor::get_fade_in_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fade_in_seconds"), "set_fade_in_seconds", "get_fade_in_seconds");
    ClassDB::bind_method(D_METHOD("set_fade_out_seconds", "value"), &CubismMotionDescriptor::set_fade_out_seconds);
    ClassDB::bind_method(D_METHOD("get_fade_out_seconds"), &CubismMotionDescriptor::get_fade_out_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fade_out_seconds"), "set_fade_out_seconds", "get_fade_out_seconds");
    ClassDB::bind_method(D_METHOD("set_duration_seconds", "value"), &CubismMotionDescriptor::set_duration_seconds);
    ClassDB::bind_method(D_METHOD("get_duration_seconds"), &CubismMotionDescriptor::get_duration_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "duration_seconds"), "set_duration_seconds", "get_duration_seconds");
    ClassDB::bind_method(D_METHOD("set_loop", "value"), &CubismMotionDescriptor::set_loop);
    ClassDB::bind_method(D_METHOD("get_loop"), &CubismMotionDescriptor::get_loop);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "loop"), "set_loop", "get_loop");
    ClassDB::bind_method(D_METHOD("set_animation", "value"), &CubismMotionDescriptor::set_animation);
    ClassDB::bind_method(D_METHOD("get_animation"), &CubismMotionDescriptor::get_animation);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "animation", PROPERTY_HINT_RESOURCE_TYPE, "Animation"), "set_animation", "get_animation");
    ClassDB::bind_method(D_METHOD("set_events", "value"), &CubismMotionDescriptor::set_events);
    ClassDB::bind_method(D_METHOD("get_events"), &CubismMotionDescriptor::get_events);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "events", PROPERTY_HINT_ARRAY_TYPE, "CubismMotionEvent"), "set_events", "get_events");
    ClassDB::bind_method(D_METHOD("set_metadata", "value"), &CubismMotionDescriptor::set_metadata);
    ClassDB::bind_method(D_METHOD("get_metadata"), &CubismMotionDescriptor::get_metadata);
    ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "metadata"), "set_metadata", "get_metadata");
}

void CubismExpressionDescriptor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_id", "value"), &CubismExpressionDescriptor::set_id);
    ClassDB::bind_method(D_METHOD("get_id"), &CubismExpressionDescriptor::get_id);
    ADD_PROPERTY(PropertyInfo(Variant::STRING_NAME, "id"), "set_id", "get_id");
    ClassDB::bind_method(D_METHOD("set_source_path", "value"), &CubismExpressionDescriptor::set_source_path);
    ClassDB::bind_method(D_METHOD("get_source_path"), &CubismExpressionDescriptor::get_source_path);
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_path"), "set_source_path", "get_source_path");
    ClassDB::bind_method(D_METHOD("set_fade_in_seconds", "value"), &CubismExpressionDescriptor::set_fade_in_seconds);
    ClassDB::bind_method(D_METHOD("get_fade_in_seconds"), &CubismExpressionDescriptor::get_fade_in_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fade_in_seconds"), "set_fade_in_seconds", "get_fade_in_seconds");
    ClassDB::bind_method(D_METHOD("set_fade_out_seconds", "value"), &CubismExpressionDescriptor::set_fade_out_seconds);
    ClassDB::bind_method(D_METHOD("get_fade_out_seconds"), &CubismExpressionDescriptor::get_fade_out_seconds);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "fade_out_seconds"), "set_fade_out_seconds", "get_fade_out_seconds");
    ClassDB::bind_method(D_METHOD("set_parameters", "value"), &CubismExpressionDescriptor::set_parameters);
    ClassDB::bind_method(D_METHOD("get_parameters"), &CubismExpressionDescriptor::get_parameters);
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "parameters", PROPERTY_HINT_ARRAY_TYPE, "CubismExpressionParameter"), "set_parameters", "get_parameters");
}
