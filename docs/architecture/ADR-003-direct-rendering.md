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

## Evidence

The focused GL compatibility experiment compares direct rendering against each
wrapper at model opacity 1.0 and 0.65, with RGB modulation, using the same Haru
fixture and a 256x256 target. The fixed channel tolerance is 3/255. CanvasGroup
has maximum error 1/255; the premultiplied SubViewport path matches exactly.
Captures and logs remain private under `.local-build/evidence`.

The SDK-free regression can be run with:

```sh
REDOT_BIN=/path/to/pinned/redot python3 tools/run_composition_tests.py --output /persistent/results --size 64
```

Its 75 cases use the production compositor shader and MeshInstance2D fixtures:
normal/add/multiply, patterned textures, regular/inverted masks, both alpha
encodings, modulation, 84-drawable chains and three backdrop alpha values. All
pixels match direct output exactly on the tested Linux GL backend; the flat
negative control fails 20 cases. Nonempty-reference assertions guard against
vacuous texture tests. The mesh-based algorithm also passed at target size 41.

The expanded native Haru regression passes 84 assertions and twelve full-model
comparisons at 256x256: rotation, mirroring, partial clipping, canvas zoom,
viewport stretch, tiny models, inherited modulation, overlapping straight/PMA
models, reordered character z values and paused movement. It compares the first
fallback frame and immediate movement of an already-paused fallback character.
Mode changes preserve geometry, pose and motion time; bounded allocation,
unsupported target/oversized atlas recovery, unload and scene save/reopen are
checked. Linux debug/release each pass all 41 runtime/export stages through
`tools/run_model2d_tests.py --graphics --motion --examples`, including all 84
fallback assertions in native and selected-export runs. The maximum channel
difference across the twelve images is 2/255 (tolerance 3/255). Earlier
settled-frame checks alone did not detect the first-frame defects above.

A negative control using the default Sprite2D material fails with 2,119 pixels
outside tolerance and maximum error 0.1843. A ViewportTexture already contains
premultiplied output; using ordinary straight-alpha composition darkens edges.

## Qualification limits

The older wrapper results establish only normal-blend, single-model equivalence.
The new tests add shader-level destination-dependent blend coverage and native
multi-character composition, but do not establish a performance advantage,
Windows behavior, other backends/HDR, arbitrary canvas effects, or full-model
Mao/Mark/Rice parity with the SDK reference. These remain explicit release gates.

Mask SubViewports remain part of direct rendering. The full-model fallback must
not replace the direct path's existing mask, ordering and lifetime tests.
