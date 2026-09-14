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

### Mask-resolution control

A second private SDK sample hook changes only the drawable mask buffer size.
At 256 pixels it reproduces the original Mao, Mark and Rice reference images
byte-for-byte. At 2048 pixels it retains identical logged parameters, parts and
MVP matrices. Against the unchanged Redot captures with alpha-border fixing
disabled, pixels above 3/255 drop from 57 to 3 for Mao, 36 to 11 for Mark and
12 to 4 for Rice. Maximum errors become 6, 15 and 6 respectively.

This isolates SDK mask resolution as a contributor, without claiming that all
remaining errors share that cause. The SDK packs masks using clipped drawable
bounds with proportional padding; the current renderer uses separate mask
viewports sized from mask-source bounds with fixed padding. The two pipelines
therefore sample masks differently. Independently capping Redot's Mao mask
viewports at 256 changes 172 image pixels and reduces its original-reference
count above 3 from 57 to 43, but does not eliminate the difference.

No production mask setting was changed or tolerance relaxed. Private control
captures and exact executable identity are retained in each affected model's
`sdk-mask-control` evidence directory; the sample patch is
`.local-build/evidence/reference-mask-size-hook.patch`. Residual edge errors,
animated comparisons and the final parity gate remain open.


### Current importer and preferred-runtime comparison

The four-model neutral comparison was rerun on the fallback implementation
checkpoint with Cubism-owned straight-alpha textures produced by the native
importer. No engine-owned import metadata was edited. The private import driver
uses the editor plugin lifecycle; the capture driver advances one fixed 1/60 s
step with effects disabled and rejects empty images. Every parameter and part
opacity matches the SDK within 0.00001, with the same recorded MVP matrix.

At 512 by 512, on the same Linux virtualized GL backend, the SDK's 256-pixel
mask atlas gives these RGB-on-black results against the current preferred node:

| Model | Foreground mean error | Maximum error | Pixels above 3/255 |
| --- | ---: | ---: | ---: |
| Haru | 0.3702 | 33 | 27 |
| Mao | 0.4319 | 30 | 102 |
| Mark | 0.1804 | 40 | 123 |
| Rice | 0.2006 | 50 | 83 |

The preferred node follows projected screen density, unlike the older comparison
above. A private control multiplied only its mask resolution and sampling scale
by four. Against the same SDK references, maximum errors became 3, 25, 13 and 11;
counts above 3 became 0, 52, 30 and 15 respectively. This identifies mask sampling
as a contributor; it does not establish that every residual has that cause.
No production sampling policy or acceptance threshold was changed. Separate
2048-pixel SDK mask references and all state checks are retained as controls.

The measured addon SHA-256 is
`0510d010dcdacc7d508eed6d5210c3d14e38f75c137f8fa2e5a08034aae49a3f`;
the reference executable is
`b6a3fce7873636a06fc6fc1f92f5daa7047b437529a33658590accdcbd98c4fc`.
Private evidence and its checksum manifest are saved in
`.local-build/sdk-current-checkpoint`. These static RGB measurements do not
qualify animated, alpha, Windows or final whole-model visual acceptance.


### Coverage outside a mask buffer

A deterministic closed-eye expression exposed colored patches above Mao's eyes
that were absent in the same-SDK reference. Parameters, part opacities and the
model-view-projection matrix matched. Thin mask buffers had nonzero edge texels;
clamped texture sampling extended that coverage beyond the mask buffer.

All six masked normal/add/multiply shaders now treat samples outside the mask UV
rectangle as zero coverage. Inverted masks then correctly yield full coverage
outside the rectangle. An expanded regression checks all four exterior edges,
source and destination alpha variants, and each blend/mask combination. Original
shaders fail 96 cases; corrected shaders pass all 198 cases with the existing
3/255 channel tolerance.

The private reference matrix covers Haru and Mao in neutral, motion, expression,
180-step physics and rotated/scaled states, with both straight and premultiplied
textures. The SDK reference explicitly selects and reports the matching texture
encoding. SDK states are transferred into Redot to isolate rendering; these
captures do not establish native expression/physics evaluator parity.

For Mao's closed-eye expression, foreground RGB RMS on a 0–255 scale improves
from 2.825 to 0.783 for straight textures and from 2.799 to 0.819 for premultiplied
textures. Alpha RMS remains 0.175. All 20 fixed-shader captures have matching
model states. The visible patches disappear; residual edge differences remain.
These measurements do not replace approved whole-model or Windows acceptance
criteria, and no comparison tolerance was relaxed.

The unchanged native debug library SHA-256 is
`d9e934116136e5b7664522e0c483abbcace04280d652efb50eff43d23a67d0b7`.
Shader identities, original failures, mask-buffer diagnostics, SDK reference
identity and captures are retained privately in `.local-build` recovery records.

Linux native and exported debug/release suites each pass all 59 checks, including
198 blend/mask-edge cases in both source and exported execution. The 53 public
tests and restricted-file audit pass. Shader changes do not require rebuilding
the unchanged native libraries; final release revision qualification remains open.

### Independent two-model order and visible additive effects

The repository visual runner now has measured Linux GL coverage against an
independent SDK reference drawing Haru and Mao into the same transparent
framebuffer. Each model keeps its own parameters, part opacities and transform
when order is reversed. The SDK reversal changes 13,847–15,680 pixels across
neutral and 180-step motion states and both texture encodings. All 16 Redot
captures match the recorded model states. Debug and release images are
byte-identical for each fixture. Forward/reverse images were visually inspected
against their SDK references; the expected overlap changes are present.

The paired foreground RGB RMS ranges from 0.775 to 0.882 on a 0–255 scale;
alpha RMS ranges from 0.172 to 0.180. Maximum RGB differences are 29–36 and
maximum alpha differences are 6–7. These are measurements, not new tolerances.

Drawable declarations alone do not establish visible blend coverage. Mao's
`exp_04` and the sampled `special_01` motion leave all additive meshes hidden;
those fixture attempts were rejected. `TapBody` index 5 (`special_03`) after
240 fixed 1/60-second steps exposes nine additive meshes. The recorded visible
set contains normal, additive and multiply blends, 20 regular masked drawables
and six inverted masked drawables. The unmodified authored motion supplies the
state; no drawable opacity or blend mode is forced by the test.

Four additional captures cover that effect in debug/release with straight and
premultiplied textures. All parameter/part checks pass, and each debug/release
pair is byte-identical. RGB RMS is 0.410/0.422, maximum RGB error 19/20, alpha
RMS 0.153 and maximum alpha error 6. SDK and Redot effect images were inspected.
The private harness adds motion-index selection and per-model diagnostics only;
a single-Haru control remains byte-identical to the earlier SDK capture.

Reference executable SHA-256 values are
`17e4a82cf135ae2bd227427523fcee07d57e5f6eecb4577e85aaa4f95fc4f654`
for paired captures and
`cc83c1a61320b96c32446478ebc469622f34a0b29afa49d1d6ef2e278056fa61`
for additive captures. Framework and Core pins are unchanged. Reports, source
snapshots, raw logs and images remain private in the local recovery archive.
These transferred-state checks do not prove native effect evaluation, Windows
rendering, or complete release qualification. Reviewed whole-model acceptance
limits and the remaining planned fixtures are still required.
