# Legacy renderer debug overlay

This page documents the legacy overlay for `GDCubismUserModel`. Add a `Node2D`
directly beneath that node and attach
`res://addons/gd_cubism/res/debug_overlay.gd`. It runs in the editor and game.
No overlay is created automatically by the model.

Use the **Overlays** flags in the inspector:

- **Drawable bounds:** cyan rectangles from the current mesh bounds.
- **Mask bounds:** pink rectangles showing each mask viewport's covered area.
- **Draw order:** yellow labels containing the current drawable ordinal and ID.

Bounds are enabled by default. Draw-order labels can overlap on dense models;
set **Drawable ID** to an exact Core drawable ID to inspect a single drawable.
An empty ID shows all drawables. This filter affects drawable bounds and labels;
mask bounds remain visible when their flag is enabled.

Set **Overlays** to zero, hide the overlay, or remove it to stop drawing. The
model's generated meshes and masks remain untouched. Suspended mask rectangles
show their last allocated coverage until the next visible model advancement.
The overlay tolerates model unload and skips singular overlay transforms.

This is a diagnostic view, not a renderer-quality comparison. It shows draw order
as the current sorted sibling ordinal; it does not expose raw Core order values.
It adds per-frame drawing work only when attached and enabled, and should normally
be omitted from shipping scenes.

## Preferred model diagnostics

For new scenes, add a `CubismModel2D` node and use its saved
`debug_draw_bounds` and `debug_draw_hit_areas` properties instead of adding the
legacy overlay. The first draws a cyan rectangle around current drawable geometry;
the second draws magenta rectangles around declared hit drawables. These flags are
available in the editor and in debug/release builds, do not advance simulation, and
do not add a script or sample dependency to exported scenes. See the
[preferred runtime guide](preferred-runtime.md) and
[CubismModel2D class reference](../doc_classes/CubismModel2D.xml).
