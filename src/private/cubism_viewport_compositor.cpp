// SPDX-License-Identifier: MIT
#include "cubism_viewport_compositor.hpp"
#include "cubism_model_2d.hpp"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <algorithm>
#include <cmath>

using namespace godot;

void CubismViewportCompositor::clear() {
    for (Node *node : {static_cast<Node *>(output), static_cast<Node *>(copy), static_cast<Node *>(atlas)}) {
        if (!node) continue;
        if (node->get_parent()) node->get_parent()->remove_child(node);
        memdelete(node);
    }
    output = nullptr;
    copy = nullptr;
    atlas = nullptr;
    cells.clear();
    material.unref();
    error = String();
}

void CubismViewportCompositor::set_visible(bool visible) {
    if (atlas) atlas->set_update_mode(visible ? SubViewport::UPDATE_ALWAYS : SubViewport::UPDATE_DISABLED);
    if (output) output->set_visible(visible);
    if (copy) copy->set_visible(visible);
}

void CubismViewportCompositor::set_error(Node2D *owner, const String &message) {
    set_visible(false);
    if (message == error) return;
    error = message;
    CubismModel2D *model = Object::cast_to<CubismModel2D>(owner->get_parent());
    if (model) model->call_deferred("emit_signal", "runtime_warning", ERR_UNAVAILABLE, message);
}

void CubismViewportCompositor::update(Node2D *owner, const std::vector<CubismCompositionDrawable> &drawables) {
    // Read visibility before hiding the direct meshes. Native evaluation resets
    // it from Cubism on every update; the native/mask resources stay in place.
    std::vector<bool> visible;
    Rect2 bounds;
    bool has_bounds = false;
    const Transform2D transform = owner->get_viewport_transform() * owner->get_global_transform();
    for (const auto &drawable : drawables) {
        visible.push_back(drawable.mesh->is_visible());
        if (drawable.mesh->is_visible()) {
            const AABB box = drawable.mesh->get_mesh()->get_aabb();
            const Rect2 projected = transform.xform(Rect2(box.position.x, box.position.y, box.size.x, box.size.y));
            bounds = has_bounds ? bounds.merge(projected) : projected;
            has_bounds = true;
        }
        drawable.mesh->hide();
    }
    if (!owner->is_visible_in_tree() || !has_bounds || transform.determinant() == 0) {
        set_visible(false);
        return;
    }
    const Vector2 viewport_size = owner->get_viewport()->get_texture()->get_size();
    if (RenderingServer::get_singleton()->get_current_rendering_method() != "gl_compatibility"
            || DisplayServer::get_singleton()->get_name() == "headless"
            || owner->get_viewport()->is_using_hdr_2d() || viewport_size.x <= 40 || viewport_size.y <= 40) {
        set_error(owner, "Cubism SubViewport fallback requires GL Compatibility, SDR, and a target larger than 40 pixels on both axes.");
        return;
    }
    if (drawables.size() > 512) {
        set_error(owner, "Cubism SubViewport fallback supports at most 512 drawable meshes.");
        return;
    }
    if (!bounds.position.is_finite() || !bounds.size.is_finite()) {
        set_error(owner, "Cubism SubViewport fallback cannot render non-finite bounds.");
        return;
    }
    bounds = bounds.intersection(Rect2(Vector2(), viewport_size));
    if (!bounds.has_area()) {
        set_visible(false);
        return;
    }
    const Vector2 origin = bounds.position.floor();
    const Vector2 extent = bounds.get_end().ceil() - origin;
    // Redot skips render targets with an axis below two pixels. Padding a
    // one-pixel cell keeps even a single-drawable atlas renderable.
    const Vector2i size(std::max(2, int(extent.x)), std::max(2, int(extent.y)));
    const int count = static_cast<int>(drawables.size());
    const int columns = std::clamp(static_cast<int>(std::ceil(std::sqrt(double(count) * size.y / size.x))), 1, count);
    const int rows = (count + columns - 1) / columns;
    const int64_t width = int64_t(size.x) * columns;
    const int64_t height = int64_t(size.y) * rows;
    if (width > 4096 || height > 4096 || width * height > 8388608) {
        set_error(owner, "Cubism SubViewport fallback atlas exceeds its 4096-axis or 8-million-texel allocation limit. Reduce the projected model size or select Direct rendering.");
        return;
    }
    RenderingServer *server = RenderingServer::get_singleton();
    if (!atlas) {
        atlas = memnew(SubViewport);
        atlas->set_name("CubismDrawableAtlas");
        atlas->set_transparent_background(true);
        owner->add_child(atlas);
        copy = memnew(Node2D);
        copy->set_name("CubismBackdropCopy");
        owner->add_child(copy);
        server->canvas_item_set_copy_to_backbuffer(copy->get_canvas_item(), true, Rect2());
        output = memnew(MeshInstance2D);
        output->set_name("CubismComposition");
        material.instantiate();
        material->set_shader(ResourceLoader::get_singleton()->load("res://addons/gd_cubism/res/shader/2d_cubism_compositor.gdshader"));
        material->set_shader_parameter("layers", atlas->get_texture());
        output->set_material(material);
        owner->add_child(output);
    }
    atlas->set_size(Vector2i(width, height));
    // Native meshes and compositor siblings share z=0, keeping the entire
    // character within its owner's canvas order.
    owner->move_child(copy, owner->get_child_count() - 1);
    owner->move_child(output, owner->get_child_count() - 1);
    while (cells.size() < drawables.size()) {
        Cell cell;
        cell.clip = memnew(Control);
        cell.clip->set_clip_contents(true);
        cell.clip->set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
        atlas->add_child(cell.clip);
        cell.white = memnew(Node2D);
        cell.clip->add_child(cell.white);
        cell.mesh = memnew(MeshInstance2D);
        cell.clip->add_child(cell.mesh);
        cells.push_back(cell);
    }
    Color modulate(1, 1, 1, 1);
    // A SubViewport starts a new canvas. Carry precisely the modulation that
    // the original drawable inherited; ancestor self_modulate is not inherited.
    for (CanvasItem *item = owner; item; item = Object::cast_to<CanvasItem>(item->get_parent())) {
        modulate *= item->get_modulate();
        if (item->is_set_as_top_level()) break;
    }
    PackedInt32Array modes;
    modes.resize(512);
    for (int i = 0; i < count; ++i) {
        Cell &cell = cells[i];
        cell.clip->set_position(Vector2(size.x * (i % columns), size.y * (i / columns)));
        cell.clip->set_size(size);
        server->canvas_item_set_transform(cell.clip->get_canvas_item(), Transform2D(0, cell.clip->get_position()));
        server->canvas_item_set_custom_rect(cell.clip->get_canvas_item(), true, Rect2(Vector2(), size));
        server->canvas_item_set_clip(cell.clip->get_canvas_item(), true);
        server->canvas_item_clear(cell.white->get_canvas_item());
        if (drawables[i].blend == 2) server->canvas_item_add_rect(cell.white->get_canvas_item(), Rect2(Vector2(), size), Color(1, 1, 1, 1));
        cell.mesh->set_mesh(drawables[i].mesh->get_mesh());
        cell.mesh->set_material(drawables[i].mesh->get_material());
        Transform2D tile_transform = transform;
        tile_transform[2] -= origin;
        cell.mesh->set_transform(tile_transform);
        server->canvas_item_set_transform(cell.mesh->get_canvas_item(), tile_transform);
        cell.mesh->set_modulate(modulate * drawables[i].mesh->get_modulate());
        cell.mesh->set_self_modulate(drawables[i].mesh->get_self_modulate());
        cell.mesh->set_visible(visible[i]);
        // The late refresh cannot wait for deferred MeshInstance2D redraws:
        // new cells and changed draw orders must render in this same frame.
        server->canvas_item_clear(cell.mesh->get_canvas_item());
        server->canvas_item_add_mesh(cell.mesh->get_canvas_item(), drawables[i].mesh->get_mesh()->get_rid(), Transform2D(), Color(1, 1, 1, 1));
        modes.set(i, drawables[i].blend);
    }
    material->set_shader_parameter("modes", modes);
    material->set_shader_parameter("count", count);
    material->set_shader_parameter("grid", Vector2(columns, rows));
    // The output is screen-aligned but remains a child of the model, retaining
    // canvas layer, clipping and visibility. Only its sampled atlas is offscreen.
    const Transform2D inverse = transform.affine_inverse();
    PackedVector2Array vertices;
    vertices.push_back(inverse.xform(origin));
    vertices.push_back(inverse.xform(origin + Vector2(size.x, 0)));
    vertices.push_back(inverse.xform(origin + Vector2(size)));
    vertices.push_back(inverse.xform(origin + Vector2(0, size.y)));
    PackedVector2Array uvs;
    uvs.push_back(Vector2(0, 0)); uvs.push_back(Vector2(1, 0));
    uvs.push_back(Vector2(1, 1)); uvs.push_back(Vector2(0, 1));
    PackedInt32Array indices;
    for (int index : {0, 1, 2, 0, 2, 3}) indices.push_back(index);
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    arrays[Mesh::ARRAY_TEX_UV] = uvs;
    arrays[Mesh::ARRAY_INDEX] = indices;
    Ref<ArrayMesh> quad = output->get_mesh();
    if (quad.is_null()) {
        quad.instantiate();
        quad->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
        output->set_mesh(quad);
        server->canvas_item_clear(output->get_canvas_item());
        server->canvas_item_add_mesh(output->get_canvas_item(), quad->get_rid(), Transform2D(), Color(1, 1, 1, 1));
    } else {
        // frame_pre_draw runs after deferred CanvasItem redraws. Retain the
        // mesh RID already referenced by its draw command instead of freeing
        // and replacing it before the next redraw can install the new RID.
        const uint64_t format = quad->surface_get_format(0);
        const uint32_t stride = server->mesh_surface_get_format_vertex_stride(format, 4);
        const uint32_t offset = server->mesh_surface_get_format_offset(format, 4, RenderingServer::ARRAY_VERTEX);
        PackedByteArray bytes;
        bytes.resize(4 * stride);
        for (int i = 0; i < 4; ++i) {
            bytes.encode_float(i * stride + offset, vertices[i].x);
            bytes.encode_float(i * stride + offset + sizeof(float), vertices[i].y);
        }
        quad->surface_update_vertex_region(0, 0, bytes);
    }
    Rect2 local_bounds(vertices[0], Vector2());
    for (int i = 1; i < 4; ++i) local_bounds.expand_to(vertices[i]);
    quad->set_custom_aabb(AABB(Vector3(local_bounds.position.x, local_bounds.position.y, 0), Vector3(local_bounds.size.x, local_bounds.size.y, 0)));
    server->canvas_item_set_custom_rect(output->get_canvas_item(), true, local_bounds);
    error = String();
    set_visible(true);
}
