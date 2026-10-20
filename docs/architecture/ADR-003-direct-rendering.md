# ADR-003: Direct rendering with explicit composition fallbacks

Status: Direct rendering retained. Public fallback passes Linux debug/release
native and selected-export checks; remaining platform/reference gates are open.

## Decision

Keep the existing per-drawable direct renderer as the default. Its corrected
sibling ordering passes the current normal-blend multi-character oracle.
Do not allocate a full-model render target automatically or silently switch
modes when a rendering problem occurs.

The native test harness exposes two explicit experiments through repeatable
`--fallback-mode` settings:

- `canvas_group`: place the model beneath a CanvasGroup.
- `subviewport`: render the model into a transparent, fixed-size SubViewport and
  display its texture using a premultiplied-alpha CanvasItemMaterial.

These remain comparison experiments. The public `CubismModel2D.rendering_mode`
offers `DIRECT` (default) and `SUBVIEWPORT_FALLBACK`, using the ordered compositor
described below rather than the flattened experimental wrapper.

## Public fallback

A single transparent model texture cannot preserve destination-dependent
multiply blending or saturation in an additive-then-multiply sequence. For
example, adding `(1, .9, .8)` to background `(.2, .4, .8)` then multiplying by
`(.2, .4, .6)` gives `(.2, .4, .6)` directly; flattening first gives
`(.4, .7608, 1)` on the pinned SDR backend.

Instead, renderer-owned atlas cells render each drawable independently. Multiply
cells start white; normal/additive cells start transparent. Cloned instances
share the existing meshes/materials, including their mask textures. The original
runtime, geometry, animation and mask ownership remain intact. A backdrop copy
and one output mesh replay the cells in Cubism order, preserving RGBA8 rounding
and saturation after each drawable. All generated items remain at relative z=0.

Cells cover the model's projected bounds intersected with its parent target.
Their clips prevent partially visible meshes spilling into adjacent cells. The
output maps those pixels back through the owner's transform. A frame-pre-draw
refresh handles camera/model movement, modulation and visibility even with
paused/manual playback, without advancing animation. The output retains its
mesh RID because replacing it at that point would invalidate a queued draw
command. Clone/output draw commands and cell clipping/transforms are submitted
immediately: waiting for deferred MeshInstance2D/Control redraws caused a blank
first frame or spill between cells. Returning to Direct or unloading frees the
fallback resources; none
are serialized as scene children.

The fallback currently requires GL Compatibility, SDR, a target larger than 40
pixels on both axes, at most 512 drawable meshes, and an atlas bounded to 4096
pixels per axis and 8,388,608 texels. The target-size restriction follows the
pinned GLES3 backend's backbuffer allocation condition. Unsupported settings
retain the requested mode, draw no character, expose `rendering_error`, and emit
one `runtime_warning` per changed error. Resizing or selecting Direct recovers.
It does not silently change modes or downsample to hide an allocation overflow.

## Regression coverage

The native graphics tests compare direct rendering against the experimental
wrappers at model opacity 1.0 and 0.65, with RGB modulation. These checks cover
normal-blend, single-model composition. Use a premultiplied-alpha material for a
ViewportTexture: ordinary straight-alpha composition darkens its edges.

The SDK-free compositor regression can be run with:

```sh
REDOT_BIN=/path/to/pinned/redot python3 tools/run_composition_tests.py --output /persistent/results --size 64
```

It uses the production compositor shader and MeshInstance2D fixtures to compare
normal/add/multiply blending, patterned textures, regular/inverted masks, both
alpha encodings, modulation, long drawable chains and backdrop alpha values.
Nonempty-reference assertions guard against vacuous texture tests; a flattened
composition provides a negative control.

`tools/run_model2d_tests.py --graphics --motion --examples` checks the public
fallback in native and selected-export runs. Coverage includes rotation,
mirroring, partial clipping, canvas zoom, viewport stretch, tiny models,
inherited modulation, overlapping straight/PMA models, reordered character
layers and paused movement. It compares the first fallback frame and immediate
movement of an already-paused character. Mode changes must preserve geometry,
pose and motion time. The suite also checks bounded allocation, recovery from
unsupported targets or oversized atlases, unload and scene save/reopen.

## Qualification limits

Wrapper comparisons cover only normal-blend, single-model composition.
The public fallback tests add shader-level destination-dependent blend coverage
and native multi-character composition, but do not establish a performance advantage,
Windows behavior, other backends/HDR, arbitrary canvas effects, or full-model
Mao/Mark/Rice parity with the SDK reference. These remain explicit release gates.

Mask SubViewports remain part of direct rendering. The full-model fallback must
not replace the direct path's existing mask, ordering and lifetime tests.
