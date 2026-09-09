# PR 4 renderer correctness — work in progress

Linux ordering, bounds and mask-identity regressions are fixed and tested.
This is a source checkpoint, not completion of the renderer or P0 release.

## Reproductions and changes

- Three models at layers 0/1/2 previously produced drawable depth ranges
  0–83/1–84/2–85. Drawable sibling ordering now keeps each character within its
  own layer. See [ADR-006](../architecture/ADR-006-draw-order-isolation.md).
- Bounds initialized their maximum with positive `DBL_MIN`, giving incorrect
  bounds for all-negative coordinates. Bounds now start from the first vertex.
  Vertex writes also query the actual surface-format stride and offset rather
  than assuming the CPU `Vector2` layout matches the GPU buffer.
- A private Haru copy renamed two mask-source IDs to `D_PSD_Ab` and `D_PSD_BA`,
  which share a Redot String hash. The original renderer created only two of
  three required masks. Dictionary keys now contain the full sorted JSON ID
  list; the short hash is used only for a cosmetic viewport name. The regression
  now preserves all three masks.

## Verification

Pinned Redot 26.2, SDK and binding inputs remain unchanged. Runs used Linux X11
and the virtualized GL compatibility renderer. Debug and release ordering/bounds
builds each passed 23 native/export checks. A fixed-state single-model image and
parameter/part state were byte-identical after the bounds/stride change.

With the mask fix, the debug build passed 25 checks on original Haru; the release
build passed the same 25 checks on the private colliding-ID fixture. Both include
expected mask compositions, actual mesh bounds, model layers, lifecycle,
playback, fresh import, editor restart, graphics and exported execution with the
source project moved out of reach. Original and renamed-fixture captures match.

Working-tree library SHA-256 identities, based on local `e414595`:

- Debug: `312713c601a21e031cc063c8d725e9bf0b259b930b1a297cca11c4171f1a2d04`.
- Release: `59df68af3d9878efe61350c045df1f96f5a74d879060f84dc3f2f1da90a67832`.
- Capture: `1d501356905615dc06493f581ea530dcf0e09a5c5cc1aacfaa39b9331a0e9232`.

Private evidence remains under `.local-build/evidence/renderer-bounds-*`,
`renderer-mask-debug`, `renderer-mask-collision-release`, and the before/after
collision logs. The 24 public source tests also pass. No SDK, modified model,
capture or native binary is included in this source checkpoint.

## Remaining gates

Dynamic Cubism draw-order changes and overlapping-model image oracles remain
open. Blend modes, regular/inverted masks, extreme transforms, zero-area geometry,
offscreen policy, fallback rendering experiments and debug visualization still
need qualification. Dynamic-flag optimization follows visual parity.

The private SDK comparison identified missing texture mipmaps as a major source
of speckling. Enabling mipmaps reduced foreground mean RGB error from 6.099 to
0.377 and the 95th-percentile channel error from 34 to 1 on a 0–255 scale. This
is one fixed-state comparison, not a full parity pass. The plan now requires a
deterministic texture-import policy that preserves unrelated texture consumers.

Windows and actual window minimization remain unverified. These renderer edits
have not been sanitizer-qualified or validated as clean committed binaries.
