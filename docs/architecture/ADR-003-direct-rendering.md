# ADR-003: Direct rendering with explicit composition fallbacks

Status: Direct rendering retained; fallback experiments implemented. Public
`CubismModel2D.rendering_mode` integration remains pending.

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

These are comparison experiments, not yet an inspector-facing model mode. The
planned public model API must retain an explicit DIRECT/SUBVIEWPORT_FALLBACK
setting when that integration is implemented.

## Evidence

The focused GL compatibility experiment compares direct rendering against each
wrapper at model opacity 1.0 and 0.65, with RGB modulation, using the same Haru
fixture and a 256x256 target. The fixed channel tolerance is 3/255. CanvasGroup
has maximum error 1/255; the premultiplied SubViewport path matches exactly.
Captures and logs remain private under `.local-build/evidence`.

A negative control using the default Sprite2D material fails with 2,119 pixels
outside tolerance and maximum error 0.1843. A ViewportTexture already contains
premultiplied output; using ordinary straight-alpha composition darkens edges.

## Qualification limits

These results establish normal-blend, single-model composition equivalence for
this runtime. They do not establish a performance advantage, arbitrary target
resolution, destination-dependent additive/multiply composition, multi-character
fallback isolation, or Windows/other-backend behavior. Full-model targets also
need explicit resolution, visibility/update policy, transform mapping and
resource-lifetime integration before becoming a public rendering mode.

Mask SubViewports remain part of direct rendering. The full-model fallback must
not replace the direct path's existing mask, ordering and lifetime tests.
