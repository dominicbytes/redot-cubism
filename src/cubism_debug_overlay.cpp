// SPDX-License-Identifier: MIT
#include "cubism_model_2d.hpp"
#include "private/internal_cubism_user_model.hpp"
#include <godot_cpp/variant/callable_method_pointer.hpp>

void CubismModel2D::set_debug_draw_bounds(bool value) {
    debug_draw_bounds = value;
    configure_debug_overlay();
}

void CubismModel2D::set_debug_draw_hit_areas(bool value) {
    debug_draw_hit_areas = value;
    configure_debug_overlay();
}

void CubismModel2D::configure_debug_overlay() {
    const bool enabled = debug_draw_bounds || debug_draw_hit_areas;
    if (enabled && !debug_overlay) {
        debug_overlay = memnew(Node2D);
        debug_overlay->set_name("CubismDebugOverlay");
        // No owner or script dependency: scene persistence stores only flags.
        // Drawing after the internal runtime keeps outlines above this model.
        add_child(debug_overlay, false, Node::INTERNAL_MODE_BACK);
        debug_overlay->connect("draw", callable_mp(this, &CubismModel2D::draw_debug_overlay));
    }
    if (debug_overlay) {
        debug_overlay->set_visible(enabled);
        debug_overlay->queue_redraw();
    }
}

void CubismModel2D::queue_debug_redraw() {
    if (debug_overlay && (debug_draw_bounds || debug_draw_hit_areas)) debug_overlay->queue_redraw();
}

void CubismModel2D::draw_debug_overlay() {
    if (!is_ready() || is_queued_for_deletion()) return;
    if (debug_draw_bounds) {
        for (const Rect2 rect : runtime->internal_model->get_debug_rectangles(false)) {
            debug_overlay->draw_rect(rect, Color(0, 1, 1, 0.8), false, -1);
        }
    }
    if (debug_draw_hit_areas) {
        for (const Rect2 rect : runtime->internal_model->get_debug_rectangles(true)) {
            debug_overlay->draw_rect(rect, Color(1, 0.2, 0.8, 0.9), false, -1);
        }
    }
}
