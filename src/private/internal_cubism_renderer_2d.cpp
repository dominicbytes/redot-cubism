// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
// ----------------------------------------------------------------- include(s)
#include <gd_cubism.hpp>
#ifdef GD_CUBISM_USE_RENDERER_2D
#include <gd_cubism_user_model.hpp>

#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <CubismFramework.hpp>
#include <Model/CubismModel.hpp>
#include <Rendering/CubismRenderer.hpp>

#include <private/internal_cubism_renderer_2d.hpp>
#include <private/internal_cubism_renderer_resource.hpp>
#include <private/internal_cubism_user_model.hpp>
#include "cubism_mask_size.hpp"
#include <algorithm>
#include <vector>

// ------------------------------------------------------------------ define(s)
// --------------------------------------------------------------- namespace(s)
using namespace Live2D::Cubism::Core;
using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::Rendering;
using namespace godot;

// -------------------------------------------------------------------- enum(s)
// ------------------------------------------------------------------- const(s)
// ------------------------------------------------------------------ static(s)
PackedInt32Array make_Indices(const csmUint16 *ptr, const int32_t &size);
PackedVector2Array make_UVs(const Live2D::Cubism::Core::csmVector2 *ptr, const int32_t &size);
PackedVector2Array make_Vertices(const Live2D::Cubism::Core::csmVector2 *ptr, const int32_t &size, const Csm::csmFloat32 &ppunit, const Transform2D &layout);
const Vector4 make_vector4(const Live2D::Cubism::Core::csmVector4 &src_vec4);

// ----------------------------------------------------------- class:forward(s)
// ------------------------------------------------------------------- class(s)
InternalCubismRenderer2D::InternalCubismRenderer2D(Csm::csmUint32 width, Csm::csmUint32 height)
    : CubismRenderer(width, height)
{
}

InternalCubismRenderer2D::~InternalCubismRenderer2D()
{
}

void InternalCubismRenderer2D::update_material(const Csm::CubismModel *model, const Csm::csmInt32 index, const Ref<ShaderMaterial> mat) const
{
    const CubismTextureColor color_base = this->GetModelColorWithOpacity(model->GetDrawableOpacity(index));

    mat->set_shader_parameter("color_base", Vector4(color_base.R, color_base.G, color_base.B, color_base.A));
    mat->set_shader_parameter("premultiplied_alpha", IsPremultipliedAlpha());
    mat->set_shader_parameter("color_screen", make_vector4(model->GetDrawableScreenColor(index)));
    mat->set_shader_parameter("color_multiply", make_vector4(model->GetDrawableMultiplyColor(index)));
}

void InternalCubismRenderer2D::make_ArrayMesh_prepare(
    const Csm::CubismModel *model,
    InternalCubismRendererResource &res)
{
    const Vector2 vct_size = this->get_size(model);
    const Vector2 vct_origin = this->get_origin(model);
    const float ppunit = this->get_ppunit(model);

    res.vct_canvas_size = vct_size;
    res.CALCULATED_ORIGIN_C = vct_origin;
    res.CALCULATED_PPUNIT_C = ppunit;
}

void InternalCubismRenderer2D::update_mesh(
    const Csm::CubismModel *model,
    const Csm::csmInt32 index,
    const InternalCubismRendererResource &res,
    const Ref<ArrayMesh> ary_mesh
) const
{
    auto pp_unit = res.CALCULATED_PPUNIT_C;

    if (ary_mesh->get_surface_count() > 0) {
        const int size = model->GetDrawableVertexCount(index);
        const auto ptr = model->GetDrawableVertexPositions(index);
        RenderingServer *server = RenderingServer::get_singleton();
        const uint64_t format = ary_mesh->surface_get_format(0);
        const uint32_t stride = server->mesh_surface_get_format_vertex_stride(format, size);
        const uint32_t offset = server->mesh_surface_get_format_offset(format, size, RenderingServer::ARRAY_VERTEX);

        PackedByteArray ary;
        ary.resize(size * stride);

        const Vector2 first = res.layout_transform.xform(Vector2(ptr[0].X, -ptr[0].Y) * pp_unit);
        Vector3 vct_min(first.x, first.y, 0.0);
        Vector3 vct_max = vct_min;

        for (int i = 0; i < size; i++)
        {
            const Vector2 vertex = res.layout_transform.xform(Vector2(ptr[i].X, -ptr[i].Y) * pp_unit);
            float x = vertex.x;
            float y = vertex.y;
            vct_min.x = Math::min(vct_min.x, x); // left
            vct_min.y = Math::min(vct_min.y, y); // top
            vct_max.x = Math::max(vct_max.x, x); // right
            vct_max.y = Math::max(vct_max.y, y); // bottom
            
            ary.encode_float(offset + i * stride, x);
            ary.encode_float(offset + i * stride + sizeof(float), y);
        }

        ary_mesh->surface_update_vertex_region(0, 0, ary);

        // aabb does not get automatically updated when directly updating the vertex region
        AABB aabb(vct_min, vct_max - vct_min);
        ary_mesh->set_custom_aabb(aabb);

        return;
    }

    Array ary;

    ary.resize(Mesh::ARRAY_MAX);

    ary[Mesh::ARRAY_VERTEX] = make_Vertices(
        model->GetDrawableVertexPositions(index),
        model->GetDrawableVertexCount(index),
        pp_unit, res.layout_transform);

    ary[Mesh::ARRAY_TEX_UV] = make_UVs(
        model->GetDrawableVertexUvs(index),
        model->GetDrawableVertexCount(index));

    ary[Mesh::ARRAY_INDEX] = make_Indices(
        model->GetDrawableVertexIndices(index),
        model->GetDrawableVertexIndexCount(index));

    ary_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, ary);
    ary_mesh->set_custom_aabb(ary_mesh->get_aabb());
}

Vector2 InternalCubismRenderer2D::get_size(const Csm::CubismModel *model) const
{
    Live2D::Cubism::Core::csmVector2 vct_size;
    Live2D::Cubism::Core::csmVector2 vct_origin;
    Csm::csmFloat32 ppunit;

    Live2D::Cubism::Core::csmReadCanvasInfo(model->GetModel(), &vct_size, &vct_origin, &ppunit);

    return Vector2(vct_size.X, vct_size.Y);
}

Vector2 InternalCubismRenderer2D::get_origin(const Csm::CubismModel *model) const
{
    Live2D::Cubism::Core::csmVector2 vct_size;
    Live2D::Cubism::Core::csmVector2 vct_origin;
    Csm::csmFloat32 ppunit;

    Live2D::Cubism::Core::csmReadCanvasInfo(model->GetModel(), &vct_size, &vct_origin, &ppunit);

    return Vector2(vct_origin.X, vct_origin.Y);
}

float InternalCubismRenderer2D::get_ppunit(const Csm::CubismModel *model) const
{
    Live2D::Cubism::Core::csmVector2 vct_size;
    Live2D::Cubism::Core::csmVector2 vct_origin;
    Csm::csmFloat32 ppunit;

    Live2D::Cubism::Core::csmReadCanvasInfo(model->GetModel(), &vct_size, &vct_origin, &ppunit);

    return ppunit;
}

void InternalCubismRenderer2D::update(InternalCubismRendererResource &res, int32_t mask_viewport_size)
{
    const CubismModel *model = this->GetModel();
    const Csm::csmInt32 *renderOrder = model->GetRenderOrders();
    const Csm::csmInt32 *maskCount = model->GetDrawableMaskCounts();

    this->make_ArrayMesh_prepare(
        model,
        res);

    // get the model's global transform to preform optimizations against
    auto mesh_0 = Object::cast_to<MeshInstance2D>(res.dict_mesh.values()[0]);

    const Transform2D viewport_transform = mesh_0->get_global_transform_with_canvas();
    const Rect2 viewport_bounds = mesh_0->get_viewport_rect();
    // Unlike the logical canvas transform, this includes viewport stretch and
    // global canvas scaling, so density is measured in actual target pixels.
    const Transform2D pixel_transform = mesh_0->is_inside_tree()
        ? mesh_0->get_viewport_transform() * mesh_0->get_global_transform() : viewport_transform;
    const Rect2 pixel_bounds = mesh_0->is_inside_tree()
        ? Rect2(Vector2(), mesh_0->get_viewport()->get_texture()->get_size()) : viewport_bounds;
    double mask_density = 1;
    const bool valid_density = pixel_transform[2].is_finite()
        && cubism_mask_density(pixel_transform[0].x, pixel_transform[1].x,
        pixel_transform[0].y, pixel_transform[1].y, mask_density);
    const CubismMaskOffscreenPolicy offscreen_policy = res._owner_viewport->mask_offscreen_policy;
    const bool reduced_due = offscreen_policy == CubismMaskOffscreenPolicy::REDUCED
        && mask_cadence.due(Time::get_singleton()->get_ticks_usec());

    struct OrderedDrawable {
        Csm::csmInt32 order;
        MeshInstance2D *node;
        int blend;
    };
    std::vector<OrderedDrawable> drawables;
    drawables.reserve(model->GetDrawableCount());

    // update meshes
    for (Csm::csmInt32 index = 0; index < model->GetDrawableCount(); index++)
    {
        if (model->GetDrawableVertexCount(index) == 0)
            continue;
        if (model->GetDrawableVertexIndexCount(index) == 0)
            continue;
        
        CubismIdHandle handle = model->GetDrawableId(index);
        String node_name = String::utf8(handle->GetString().GetRawString());
        MeshInstance2D *node = Object::cast_to<MeshInstance2D>(res.dict_mesh[node_name]);
        if (node == nullptr) {
            continue;
        }
        const bool visible = model->GetDrawableDynamicFlagIsVisible(index) && model->GetDrawableOpacity(index) > 0.0f;
        node->set_visible(visible);
        Ref<ShaderMaterial> mat = node->get_material();
        Ref<ArrayMesh> ary_mesh = node->get_mesh();

        this->update_mesh(model, index, res, ary_mesh);
        this->update_material(model, index, mat);
        // Drawable order is local to this character, not a canvas-wide layer.
        node->set_z_index(0);
        const auto blend = model->GetDrawableBlendModeType(index).GetColorBlendType();
        drawables.push_back({renderOrder[index], node,
            blend == csmColorBlendType_AddCompatible ? 1 : (blend == csmColorBlendType_MultiplyCompatible ? 2 : 0)});
        
        // adjust real bounds to prevent the mesh being culled
        AABB bounds = ary_mesh->get_custom_aabb();
        Rect2 canvas_bounds = Rect2(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y);
        RenderingServer::get_singleton()->canvas_item_set_custom_rect(
            node->get_canvas_item(), true,
            canvas_bounds
        );
    }

    // Preserve drawable-index order for equal Cubism render orders.
    std::stable_sort(drawables.begin(), drawables.end(),
        [](const OrderedDrawable &a, const OrderedDrawable &b) { return a.order < b.order; });
    for (size_t i = 0; i < drawables.size(); ++i) {
        MeshInstance2D *node = drawables[i].node;
        if (node->get_index() != static_cast<int>(i)) {
            node->get_parent()->move_child(node, static_cast<int>(i));
        }
    }

    // update masks
    Array masks = res.dict_mask.keys();
    for (int i = 0; i < masks.size(); i++) {
        String mask_name = masks[i];
        SubViewport *mask = Object::cast_to<SubViewport>(res.dict_mask[mask_name]);

        // build bounding box of all the meshes in the viewport
        AABB aabb;
        {
            Ref<ArrayMesh> mesh = Object::cast_to<MeshInstance2D>(mask->get_child(0))->get_mesh();
            aabb = mesh->get_custom_aabb();

            for (int n = 1; n < mask->get_child_count(); n++) {
                Ref<ArrayMesh> mesh = Object::cast_to<MeshInstance2D>(mask->get_child(n))->get_mesh();
                aabb = aabb.merge(mesh->get_custom_aabb());
            }
        }
        aabb = aabb.grow(4.0);  // adds padding around the mask for safety
        Rect2 bounds(aabb.position.x, aabb.position.y, aabb.size.x, aabb.size.y);

        CubismMaskSize mask_size;
        if (!valid_density || !bounds.position.is_finite()
                || !cubism_mask_size(bounds.size.x, bounds.size.y, mask_viewport_size, mask_size, mask_density)) {
            mask->set_update_mode(SubViewport::UPDATE_DISABLED);
            mask->set_size(Vector2i(2, 2));
            continue;
        }
        // Apply the allocation limit even when this composition is offscreen.
        mask->set_size(Vector2i(mask_size.width, mask_size.height));

        // detect if the canvas item is going to be culled
        // only cull viewports when not looking at the model in the editor
        Rect2 bounds_in_viewport = pixel_transform.xform(bounds);
        const bool is_culled = 
            !Engine::get_singleton()->is_editor_hint() &&
            !(
                pixel_bounds.intersects(bounds_in_viewport)
                || pixel_bounds.encloses(bounds_in_viewport)
            );

        const bool render_mask = pixel_transform.determinant() != 0.0
            && res._owner_viewport->is_visible_in_tree()
            && !(is_culled && offscreen_policy == CubismMaskOffscreenPolicy::PAUSED);
        if (!render_mask) {
            mask->set_update_mode(SubViewport::UPDATE_DISABLED);
            continue;
        }
        if (is_culled && offscreen_policy == CubismMaskOffscreenPolicy::REDUCED) {
            if (reduced_due) mask->set_update_mode(SubViewport::UPDATE_ONCE);
            else if (mask->get_update_mode() != SubViewport::UPDATE_ONCE) mask->set_update_mode(SubViewport::UPDATE_DISABLED);
            // Do not re-submit UPDATE_ONCE before the next pulse. The node's
            // getter retains ONCE after the server has consumed it. Leaving it
            // alone also preserves pending draws across repeated manual steps.
        } else {
            mask->set_update_mode(SubViewport::UPDATE_ALWAYS);
        }

        const double scalar = mask_size.scale;
        Vector2 viewport_offset = bounds.position;
        Transform2D transform = Transform2D(0, -viewport_offset);
        transform.scale(Vector2(scalar, scalar));
        mask->set_canvas_transform(transform);

        Array meshes = res.dict_mask_meshes[mask_name];
        for (int n = 0; n < meshes.size(); n++) {
            MeshInstance2D *mesh = Object::cast_to<MeshInstance2D>(meshes[n]);
            Ref<ShaderMaterial> mat = mesh->get_material();
            mat->set_shader_parameter("tex_mask", mask->get_texture());
            mat->set_shader_parameter("mask_scale", scalar);
            mat->set_shader_parameter("mesh_offset", viewport_offset);
        }
    }
    if (res._owner_viewport->use_subviewport_fallback) {
        std::vector<CubismCompositionDrawable> composition;
        composition.reserve(drawables.size());
        for (const auto &drawable : drawables) composition.push_back({drawable.node, drawable.blend});
        res.compositor.update(res._owner_viewport, composition);
    } else {
        res.compositor.clear();
    }
}

void InternalCubismRenderer2D::build_model(InternalCubismRendererResource &res, Node* target_node)
{
    const CubismModel *model = this->GetModel();
    const Csm::csmInt32 *renderOrder = model->GetRenderOrders();
    const Csm::csmInt32 *maskCount = model->GetDrawableMaskCounts();

    this->make_ArrayMesh_prepare(
        model,
        res);

    Array meshes;
    meshes.resize(model->GetDrawableCount());

    for (Csm::csmInt32 index = 0; index < model->GetDrawableCount(); index++)
    {
        if (model->GetDrawableVertexCount(index) == 0)
            continue;
        if (model->GetDrawableVertexIndexCount(index) == 0)
            continue;

        CubismIdHandle handle = model->GetDrawableId(index);
        String node_name = String::utf8(handle->GetString().GetRawString());

        MeshInstance2D* node = res.request_mesh_instance();
        // share drawable mesh between nodes and masks so we only have to update once
        if (meshes[index]) {
            node->set_mesh(meshes[index]);
        } else {
            meshes[index] = node->get_mesh();
            this->update_mesh(model, index, res, node->get_mesh());
        }
        
        ShaderMaterial* mat = res.request_shader_material(model, index);
        node->set_material(mat);        
        node->set_name(node_name);

        res.dict_mesh[node_name] = node;
        target_node->add_child(node);
        res.managed_nodes.append(node);

        // node has a mask
        if (model->GetDrawableMaskCounts()[index] <= 0)
            continue;
        
        // calculate name based on referenced art mesh names composing the mask
        Array mask_names;
        for (Csm::csmInt32 m_index = 0; m_index < model->GetDrawableMaskCounts()[index]; m_index++)
        {
            Csm::csmInt32 j = model->GetDrawableMasks()[index][m_index];
            
            if (model->GetDrawableVertexCount(j) == 0)
                continue;
            if (model->GetDrawableVertexIndexCount(j) == 0)
                continue;
    
            CubismIdHandle handle = model->GetDrawableId(j);
            String mask_name = String::utf8(handle->GetString().GetRawString());
            mask_names.append(mask_name);
        }

        if (mask_names.is_empty())
            continue;

        // Compare the full canonical composition; a short hash can alias masks.
        mask_names.sort();

        String mask_key = JSON::stringify(mask_names);

        // tag mesh node as dependent on a mask if one has already been created with the same composition
        Array vp_meshes = res.dict_mask_meshes.get(mask_key, Array());
        vp_meshes.append(node);

        // build a new mask
        if (!res.dict_mask.has(mask_key)) {
            SubViewport* viewport = memnew(SubViewport);

            res.dict_mask[mask_key] = viewport;
            
            viewport->set_name(String::num_int64(mask_key.hash()) + "__mask");

            viewport->set_disable_3d(SUBVIEWPORT_DISABLE_3D_FLAG);
            viewport->set_clear_mode(SubViewport::ClearMode::CLEAR_MODE_ALWAYS);
            // set_update_mode must be specified
            viewport->set_update_mode(SubViewport::UpdateMode::UPDATE_ALWAYS);
            viewport->set_disable_input(true);
            // Memory leak when set_use_own_world_3d is true
            // https://github.com/godotengine/godot/issues/81476
            viewport->set_use_own_world_3d(SUBVIEWPORT_USE_OWN_WORLD_3D_FLAG);
            // Memory leak when set_transparent_background is true(* every time & window minimize)
            // https://github.com/godotengine/godot/issues/89651
            viewport->set_transparent_background(true);

            for (Csm::csmInt32 m_index = 0; m_index < model->GetDrawableMaskCounts()[index]; m_index++)
            {
                Csm::csmInt32 j = model->GetDrawableMasks()[index][m_index];
                
                if (model->GetDrawableVertexCount(j) == 0)
                    continue;
                if (model->GetDrawableVertexIndexCount(j) == 0)
                    continue;
        
                CubismIdHandle handle = model->GetDrawableId(j);
                String mask_name = String::utf8(handle->GetString().GetRawString());

                MeshInstance2D* node = res.request_mesh_instance();
                if (meshes[j]) {
                    node->set_mesh(meshes[j]);
                } else {
                    meshes[j] = node->get_mesh();
                    this->update_mesh(model, j, res, node->get_mesh());
                }
                ShaderMaterial *mat = res.request_mask_material();

                node->set_name(mask_name);
                node->set_material(mat);
                mat->set_shader_parameter("channel", Vector4(0.0, 0.0, 0.0, 1.0));
                mat->set_shader_parameter("tex_main", res.ary_texture[model->GetDrawableTextureIndex(j)]);

                node->set_z_index(model->GetRenderOrders()[index]);
                node->set_visible(true);

                viewport->add_child(node);
                res.managed_nodes.append(node);
            }

            target_node->add_child(viewport);
            res.managed_nodes.append(viewport);

            node->set_meta("viewport", viewport);

            // canvas transform only available after the viewport canvas has been initialized
            // on load the mask will not be the right size or offset, but will be corrected immediately on first update
            Vector2i viewport_size = Vector2i(1,1);
            Vector2 viewport_offset = Vector2(0,0);
            viewport->set_size(viewport_size);

            mat->set_shader_parameter("tex_mask", viewport->get_texture());
            mat->set_shader_parameter("canvas_size", Vector2(res.vct_canvas_size));
            mat->set_shader_parameter("mesh_offset", viewport_offset);
        }

        res.dict_mask_meshes[mask_key] = vp_meshes;
    }
}

void InternalCubismRenderer2D::Initialize(Csm::CubismModel *model, Csm::csmInt32 maskBufferCount)
{
    CubismRenderer::Initialize(model, maskBufferCount);
}

void InternalCubismRenderer2D::DoDrawModel() {}
void InternalCubismRenderer2D::SaveProfile() {}
void InternalCubismRenderer2D::RestoreProfile() {}

// Redot owns canvas draw submission; this renderer has no Cubism render target.
void InternalCubismRenderer2D::BeforeDrawModelRenderTarget() {}
void InternalCubismRenderer2D::AfterDrawModelRenderTarget() {}

// ------------------------------------------------------------------ method(s)
PackedInt32Array make_Indices(const csmUint16 *ptr, const int32_t &size)
{
    PackedInt32Array ary;
    ary.resize(size);
    for (int i = 0; i < size; i++)
    {
        ary.set(i, ptr[i]);
    }
    return ary;
}

PackedVector2Array make_UVs(const Live2D::Cubism::Core::csmVector2 *ptr, const int32_t &size)
{
    PackedVector2Array ary;
    ary.resize(size);
    for (int i = 0; i < size; i++)
    {
        ary.set(i, Vector2(ptr[i].X, 1.0 - ptr[i].Y));
    }
    return ary;
}

PackedVector2Array make_Vertices(const Live2D::Cubism::Core::csmVector2 *ptr, const int32_t &size, const Csm::csmFloat32 &ppunit, const Transform2D &layout)
{
    PackedVector2Array ary;
    ary.resize(size);
    for (int i = 0; i < size; i++)
    {
        ary.set(i, layout.xform(Vector2(ptr[i].X, ptr[i].Y * -1.0) * ppunit));
    }
    return ary;
}

const Vector4 make_vector4(const Live2D::Cubism::Core::csmVector4 &src_vec4)
{
    return Vector4(src_vec4.X, src_vec4.Y, src_vec4.Z, src_vec4.W);
}

#endif // GD_CUBISM_USE_RENDERER_2D
