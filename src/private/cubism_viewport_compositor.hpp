// SPDX-License-Identifier: MIT
#ifndef CUBISM_VIEWPORT_COMPOSITOR_HPP
#define CUBISM_VIEWPORT_COMPOSITOR_HPP

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/mesh_instance2d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <vector>

struct CubismCompositionDrawable {
    godot::MeshInstance2D *mesh;
    int blend;
};

// Renderer-owned transient resources. Original meshes stay with the runtime;
// atlas instances share their geometry and materials, not native model state.
class CubismViewportCompositor {
    godot::SubViewport *atlas = nullptr;
    godot::Node2D *copy = nullptr;
    godot::MeshInstance2D *output = nullptr;
    struct Cell {
        godot::Control *clip;
        godot::Node2D *white;
        godot::MeshInstance2D *mesh;
    };
    std::vector<Cell> cells;
    godot::Ref<godot::ShaderMaterial> material;
    godot::String error;
    void set_error(godot::Node2D *owner, const godot::String &message);

public:
    ~CubismViewportCompositor() { clear(); }
    void clear();
    void set_visible(bool visible);
    const godot::String &get_error() const { return error; }
    void update(godot::Node2D *owner, const std::vector<CubismCompositionDrawable> &drawables);
};

#endif
