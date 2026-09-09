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

Dynamic arm-driven ordering and normal-blend overlapping-model image checks
now pass as described below. Full-model blend/effect and regular/inverted-mask parity, extreme transforms, zero-area geometry,
offscreen policy, fallback rendering experiments and debug visualization still
need qualification. Dynamic-flag optimization follows visual parity.

The private SDK comparison identified missing texture mipmaps as a major source
of speckling. Enabling mipmaps reduced foreground mean RGB error from 6.099 to
0.377 and the 95th-percentile channel error from 34 to 1 on a 0–255 scale. This
is one fixed-state comparison, not a full parity pass. The plan now requires a
deterministic texture-import policy that preserves unrelated texture consumers.

Windows and actual window minimization remain unverified. These renderer edits
have not been sanitizer-qualified or validated as clean committed binaries.

## Cross-atlas and blend follow-up

Mask meshes selected the clipped drawable's atlas instead of the source's atlas.
None of the eight bundled SDK models contained cross-atlas mask references.
A private Haru copy moves only `D_PSD_35` from texture 0 to texture 1; an
independent Core inspection confirms four resulting cross-atlas references.
The resource-binding regression fails before the one-line selection fix and
passes afterward. The mask test now compares each source's drawable and mask
texture resources.

Unmasked multiply also used the normal blend shader. A synthetic pixel oracle
based on the SDK's compatible OpenGL blend factors reproduced four failures.
It tests all nine normal/add/multiply and regular/inverted-mask variants, source
alpha 0/0.5/1, and destination alpha 0.5/1, with a fixed 3/255 channel tolerance.
The corrected multiply shader uses `blend_mul`, adds the neutral contribution
for uncovered alpha, and preserves destination alpha. All 54 cases now pass.

The expanded debug and release suites each pass 27 checks, including all 54
blend cases again in the exported game. Debug uses original Haru; release uses
the cross-atlas fixture. Working-tree addon identities based on `6eeae9f`:

- Debug: `802f724f42f524b6aee6e2861b0d1ddcb6ac51016b97cf18544ef116c4a5e131`.
- Release: `5b0ed02c6f9b08ea0fd8eaf2d0646416f14d595415bb7bc9cac0a04110fea57c`.

The shader files are separate runtime inputs; the latest debug report records
their hashes, and the release report fingerprints the exported PCK. Reports and
logs remain private under `renderer-blend-debug` and
`renderer-cross-atlas-blend-release` in `.local-build/evidence`.

An independent SDK capture of the cross-atlas fixture and matching Redot state
has foreground mean RGB error 0.377, 95th-percentile channel error 1, and maximum
channel error 10 on a 0–255 scale. The private SDK hook permits a fixture-directory
override; the original fixture's reference image remains byte-identical after
that hook. The side-by-side image was inspected. Against the saved pre-fix
library, only 12 pixels change and mean error is essentially unchanged (0.376826
before, 0.376884 after). This pose is therefore a weak oracle for the visible
benefit of atlas selection; the resource-binding regression is the decisive
evidence for that fix. Stronger mask-image cases and full renderer parity remain
open.

## Dynamic ordering and overlap qualification

An independent Core scan supplies all default parameter values, drawable order,
and expected orders for Haru's `ParamArmLA=1` and `ParamArmRA=1`. Native/exported
tests check both transitions, continued model-layer isolation, and restoration
to the default order. The test harness fingerprints this private oracle and
requires its case-completion marker; unchanged or empty cases cannot pass.

Core also confirms that Haru contains only normal-blend drawables. The overlap
oracle captures three differently tinted/translucent characters separately,
then compares four two/three-character layer orders with premultiplied-alpha
composition of those captures. The fixed 3/255 channel tolerance accommodates
framebuffer quantization. The saved pre-fix PR 3 library fails its first order
with 1,900 mismatched pixels and maximum error 0.594. The current renderer passes
all four orders. The focused comparison uses the private mipmapped fixture;
the integrated suite also passes with the standard fixture import settings.

Debug and release each pass the expanded 29-check suite, including these tests
in the exported game. The integrated overlap case contains 6,333 overlapping
pixels and maximum channel error 0.006383. Captures were inspected; known
missing-mipmap speckling remains visible and is outside this ordering oracle.
No native implementation change was needed for these qualification tests.
The library identities remain those in the cross-atlas/blend follow-up above.

Private reports, logs and actual/reference images are retained in
`.local-build/evidence/renderer-order-overlap-debug` and
`renderer-order-overlap-release`; the failing baseline is retained in
`renderer-overlap-before`. This oracle does not qualify overlapping characters
with destination-dependent additive/multiply effects or other graphics backends.

## Offscreen mask suspension

The baseline shrank offscreen mask viewports to 2x2 but left them rendering.
The regression reproduces that behavior. Mask updates now stop when culled or
hidden, preserve their allocated resources, and resume with current bounds when
visible. Model animation continues while mask rendering is suspended.

Debug and release each pass 31 native/export checks. The five-cycle test checks
offscreen suspension, continued motion, inherited hiding, recovery and stable
node counts. The release suite additionally includes camera-follow recovery at
distant world coordinates with camera zoom/rotation and a flipped, nonuniformly
scaled model; the same extended case passes in a focused debug run. This is a
bounded camera/culling regression, not exhaustive transform image parity.

Working-tree libraries based on `89e39b4`:

- Debug: `df7467790dc77da9cbb40b3a57fdee4e7d9857ddb553d118ff9f43d7c1b0cd12`.
- Release: `f65bae0afe7aa225bf1ce98ac4f1f68e7da9ac27fe5a9a56336433d3a61eed46`.

Evidence is retained under `.local-build/evidence/renderer-offscreen-debug`,
`renderer-offscreen-release`, and `renderer-offscreen-camera-debug.log`.

## Singular and extreme transforms

A corrected regression assigns transform matrices directly: Redot's scale
setter clamps zero to epsilon, so its initial scale-property failure was not
evidence of a truly singular transform. The explicit-matrix test fails against
the saved offscreen checkpoint and passes with the new determinant guard.
Only exactly singular viewport transforms suspend masks; reflections and small
nonzero transforms remain valid.

Six cases cover complete/one-axis collapse, reflection with nonuniform scale,
and scale factors from 0.000001 to 10000 under a rotated ancestor. Mask sizes
remain within the configured 128-pixel cap, node counts stay stable, and returning
to the original transform restores identical image bytes. This does not test
empty/malformed MOC geometry or establish image parity at every extreme scale.

Debug and release each pass all 33 native/export checks. Working-tree libraries
based on `1fad223`:

- Debug: `373f68583ef2406d81ce8bc3deb66d71b569f21055da74738ad3637e66bd9dd6`.
- Release: `93890ee6e5a7e03a4a6dc2b2ac2ea82a2ad24ad325a970a758fa2a087b825434`.

Evidence is retained in `.local-build/evidence/renderer-transform-debug-final`
and `renderer-transform-release-final`. The corrected before/after probes are
`renderer-singular-baseline.log` and `renderer-singular-fixed.log`. The earlier
failed scale-property experiment remains recorded but is not qualifying evidence.

## Optional debug overlay

The [overlay guide](../debug-overlay.md) describes the opt-in tool script for
drawable bounds, mask coverage and draw-order labels. An exact drawable-ID
filter makes dense models inspectable. It adds no automatic model children and
does not change the generated meshes or mask resources.

Debug and release each pass all 35 checks, including all overlay flags, ID
filtering, disabling with exact pixel restoration, model unload and exported
execution. The selected-ID capture was inspected and is readable. The all-labels
view can be crowded, so order labels are disabled by default and the guide
explains filtering. Native binaries are unchanged from the transform checkpoint.
The tested overlay script SHA-256 is
`055b69fa5927777287c1e68c65975212e06c5873c02ec9e849d7b8546824ad40`.
Both retained test projects contain that exact script; exported PCK identities
are recorded in their reports. Private evidence is retained under
`.local-build/evidence/renderer-overlay-debug` and `renderer-overlay-release`.

Fallback experiments, stronger mask/model parity, deterministic texture sampling,
platform qualification and later product stages remain unfinished.

## Explicit fallback experiments

[ADR-003](../architecture/ADR-003-direct-rendering.md) retains direct rendering
and records opt-in CanvasGroup/SubViewport experiments. Each compares a tinted
Haru at opacity 1.0 and 0.65 against direct rendering, within a fixed 3/255
tolerance. CanvasGroup differs by at most 1/255; the correctly premultiplied
SubViewport output matches exactly. A default Sprite2D material fails the
negative control with 2,119 mismatched pixels and maximum error 0.1843.

Debug and release each pass all 39 checks, including both fallback comparisons
in exported games. Captures were inspected; these wrappers preserve the current
image, including known missing-mipmap speckling. Native binaries are unchanged.
Private evidence is retained under `.local-build/evidence/renderer-fallback-*`.

These are explicit test-harness settings. Public `CubismModel2D.rendering_mode`
integration, multi-character/destination-dependent fallback composition,
visibility/resource policy and broader platform qualification remain pending.

## Seven-model matched-state comparison

The pinned SDK OpenGL sample and Redot captured Haru, Hiyori, Mao, Mark,
Natori, Rice and Wanko at 512 by 512 on a black background. The private sample
hook records its complete model-view-projection matrix; Redot uses the matching
affine transform and verifies every parameter and part opacity within 0.00001.
Motion, physics and pose evaluation are bypassed for this static comparison.
Ren is excluded because its advanced blend/offscreen features are outside the
current supported renderer; this experiment does not test its rejection path.

With mipmaps enabled, a controlled reimport changed only
`process/fix_alpha_border` from true to false, captured each model, verified
identical runtime state and restored the original import settings. Source
premultiplication remains disabled, matching this SDK sample build. Results
below use absolute RGB channel errors on the union of nonblack foreground
pixels; maximum error includes the whole image, and counts are pixels with any
channel error greater than 3 on the 0–255 scale.

| Model | Mean, border fix on | Mean, border fix off | Maximum, off | Pixels above 3, off |
| --- | ---: | ---: | ---: | ---: |
| Haru | 0.3769 | 0.3589 | 3 | 0 |
| Hiyori | 0.5997 | 0.5442 | 3 | 0 |
| Mao | 0.6069 | 0.4262 | 28 | 57 |
| Mark | 0.2218 | 0.1535 | 15 | 36 |
| Natori | 0.4205 | 0.3849 | 3 | 0 |
| Rice | 0.2054 | 0.1774 | 10 | 12 |
| Wanko | 0.1810 | 0.1553 | 2 | 0 |

The 95th percentile channel error is 1 for every border-fix-disabled capture.
Haru's reference hash remains identical to the earlier reference, validating
that the matrix logging hook preserved that capture. Mao's amplified difference
image and side-by-side crop were inspected; residual errors remain localized,
including the mouth outline. Their cause is not yet established. The 3/255
count is a diagnostic, not a newly approved whole-model acceptance threshold.
These static Linux captures do not establish animated or cross-platform parity.

The importer contract now requires Cubism-owned textures to retain straight
source texels with mipmaps, without silently changing shared texture consumers.
Production provisioning remains PR5 work. Stronger mask comparisons and the
three remaining localized discrepancies remain open.

Private scripts, captures, state logs and hashes are retained in
`.local-build/evidence/sdk-model-matrix`, with capture scripts in `.local-build`.
The reference executable SHA-256 is
`7365b430927f6ccc48a8652c60a77ffdf97e97f4f9a69a0a832403c9b057a775`.
The native debug library is unchanged from the transform checkpoint above.
No SDK files, model assets or reference images are part of this source report.
