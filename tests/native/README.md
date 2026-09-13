# Private native smoke tests

The public Python suite also compiles `audio_clock_checks.cpp` with a C++17
compiler (`CXX`, default `c++`). This small test needs neither Redot nor the SDK
and replays mixer-boundary, backward-jitter and stalled-driver samples against
the controller's clock estimator, including with assertions disabled. Compiler
scratch files use `.local-build` by default. If the checkout is on a filesystem
that cannot execute binaries, set `CUBISM_TEST_BUILD_DIR` to an executable local
build directory. Run with `python -m unittest discover -s tests/python -v`.

This harness loads the actual linked Cubism plugin with a locally provisioned
model. It checks editor registration, runtime classes and version metadata,
model/mesh creation, a real motion's parameter changes and completion signal,
expression parameter changes, model reload, and shutdown. Physics and pose are
disabled during the parameter checks to isolate native motion/expression behavior.
The lifecycle checks also cover invalid/partial loads, reentry, 20 simultaneous
models, callback removal during loading and playback, terminal handle reasons,
internal processing despite script overrides, pause and bounded delta handling.
The processing test also requires mask viewports to stop rendering beneath a
hidden model or ancestor, restore on visibility changes, retain node counts,
and leave hidden manual animation running.
Every behavior check is repeated in the private exported game. Editor restart
creates and saves a Node2D/model scene and checks that generated nodes are absent
from its serialized scene.
An empty SceneTree separately checks extension startup/shutdown without creating
any model. Debug Framework logs must show exactly one initialization and disposal;
the ordinary playback and 20-instance lifecycle runs cover one and many models.

```sh
export REDOT_BIN=/path/to/verified/Redot
python tools/run_tests.py --suite native-smoke \
  --model /private/SDK/Samples/Resources/Haru/Haru.model3.json \
  --expression F02 \
  --library demo/addons/gd_cubism/bin/libgd_cubism.linux.debug.x86_64.so \
  --template /private/templates/linux_debug.x86_64 \
  --output /private/results/native-debug
```

Use the release library, release template and `--export-mode release` for the
release variant. The supplied editor and template must match `DEPENDENCIES.json`.
Choose an expression that changes the initial pose: Haru F01 adds to a mouth
parameter already at its maximum, so F02 is the explicit smoke-test fixture.
Each engine process has a 60-second wall-clock limit and an explicit quit bound.
Unexpected warnings, errors, timeouts and missing success markers fail the run.
The deliberate negative-delta case allows exactly its documented debug warning.
The corrupt-MOC case also produces Core's expected corruption diagnostic.

Outputs contain SDK model assets and, when requested, an exported game with
statically linked Core. Keep the entire output directory private. Only source
tests and summarized evidence belong in the public repository. The fixture's
copyright notice is carried into the private project/export.

The test export uses an explicit fixture filter and launches with the source
project moved out of reach. This checks legacy export feasibility; it does not
replace the planned model-dependency validator and checked-export workflow.
Headless checks do not qualify graphics, audio timing, arbitrary model features,
or the full licensed desktop suite. Review platform results separately.

Add `--graphics gl_compatibility` (or `forward_plus`) to run and capture both the
editor binary's game mode and the real exported game. Linux graphics checks use
X11. Pose groups are restored for captures. The log records the actual backend,
adapter, display driver and viewport size; inspect the private PNGs for visible
defects. A captured model alone does not establish parity with the SDK renderer.
The harness rejects a silent fallback to a different rendering backend. It also
cycles model visibility and requests window minimization, checking owned node
counts. `minimize_observed=false` means the compositor did not minimize the test
window; that platform gate remains untested even when rendering smoke passes.
Graphics runs also check three model layers and model-level reordering. Every
visible drawable must stay at its owning model's depth. This test requires a
visible graphics window because the legacy renderer skips updates in headless
mode; a headless result cannot qualify drawable ordering. Internal draw-order
and image parity remain separate checks.

Add `--draw-order-oracle /private/order.json` to exercise parameter-driven
ordering against data obtained independently from Cubism Core. The JSON contains
`defaults` (parameter ID to value), `default_order` (drawable IDs sorted by Core
render order and index), and `cases` (objects with `parameter`, `value`, and
expected `order`). Haru's `ParamArmLA=1` and `ParamArmRA=1` change order. The test
checks both changes, layer isolation, and restoration to the default order.
An empty or unchanged case cannot pass; the harness requires the dynamic-case
completion marker and records the oracle hash.

Add `--normal-blend-overlap` only for a fixture independently confirmed to have
normal-blend drawables throughout (the pinned Haru fixture qualifies). It renders
three tinted, partly transparent characters separately, then compares overlapping
two- and three-character renders in four layer orders with alpha-composited
single-character captures. It requires at least 50 overlapping pixels and uses
a fixed 3/255 channel tolerance. Actual/reference captures are retained for the
last tested order, or the first failure. The pre-fix renderer fails this oracle;
the current renderer passes it. This oracle does not qualify overlapping
additive/multiply characters, which can depend on the destination behind them.
The bounds check compares custom AABBs with actual mesh vertex buffers and
requires the fixture to exercise all-negative coordinates. It runs in both
native and exported graphics modes. Zero-area and extreme-transform coverage
remain additional renderer gates.

Add `--mask-compositions /private/masks.json` to compare generated mask viewports
with an independently obtained list of unique source-ID groups, in both native
and exported runs. For the pinned Haru fixture this is
`[["D_PSD_04"], ["D_PSD_35"], ["D_PSD_36"]]`.
The collision regression uses a private copy with the equal-length drawable IDs
`D_PSD_35` and `D_PSD_36` changed to `D_PSD_Ab` and `D_PSD_BA`. Those distinct
strings have the same Redot String hash. Supply the corresponding renamed groups
as the oracle; all three masks must still exist. Keep the modified MOC private.
This checks resource identity at load time and can run headlessly; it does not
establish mask image parity.
The same test compares each mask mesh's texture with its source drawable's
texture. A private cross-atlas fixture is required to reproduce selection of
the clipped drawable's texture: none of the eight bundled SDK models exercise
that distinction. The local Haru regression moves only `D_PSD_35` to texture 1;
Core independently confirms four cross-atlas mask references.

Graphics runs additionally render 54 synthetic cases using the actual nine
normal/add/multiply shader variants, including regular/inverted masks, source
alpha 0/0.5/1 and destination alpha 0.5/1. Pixel results are compared with the
SDK's compatible blend equations, with a fixed tolerance of 3/255 per channel
for texture/framebuffer quantization. A shader that writes the destination
directly isolates blend behavior from background composition. This reproduces
unmasked multiply incorrectly behaving like normal blending. Reports record
the copied shader hashes. These tests qualify the tested blend equations;
they do not cover all model effects, mask geometry, or full SDK image parity.

The offscreen graphics regression moves the character out of view five times,
requires mask SubViewports to stop updating, verifies that manual motion still
advances, and checks suspension under a hidden ancestor and recovery on return.
It also follows a distant character with a rotated/zoomed camera while the model
is flipped and nonuniformly scaled. The mask resources remain allocated while
suspended; returning to view updates their bounds before rendering resumes.
Culling is reevaluated during model advancement; these manual-mode tests advance
after each model or camera transform change.
This is a camera/culling smoke check, not exhaustive transform image parity.

The transform regression assigns explicit matrices for complete/one-axis
collapse, reflection with nonuniform scale, and scale factors from 0.000001 to
10000. Matrix assignment matters: Redot's `Node2D.set_scale` clamps zero to a
small nonzero value. Truly singular transforms must suspend masks. The test
caps mask dimensions at 128, requires stable node counts, and compares the
restored model image byte-for-byte with its original image. This checks
transform recovery, not malformed or empty MOC geometry.

The optional [debug overlay](../../docs/debug-overlay.md) is exercised with
drawable bounds, mask bounds, order labels, and combined flags. The graphics
test verifies visible changes, exact ID filtering, pixel restoration on disable,
and safe model unload. Native and exported captures are retained for inspection.

Fallback experiments are opt-in: add `--fallback-mode canvas_group` and/or
`--fallback-mode subviewport` alongside `--graphics`. Each compares its wrapper
with direct rendering at opacity 1.0 and 0.65, with color modulation and a fixed
3/255 tolerance. The SubViewport sprite uses premultiplied-alpha composition;
the default sprite material fails the negative control. These are normal-blend,
single-model experiments, not the public model's future rendering-mode setting.
See [ADR-003](../../docs/architecture/ADR-003-direct-rendering.md) for limitations.

## AddressSanitizer

Build the addon with the usual pinned inputs and `sanitize=address`, using a
separate `CUBISM_BUILD_DIR`. The instrumented library goes in that directory's
`bin` subfolder instead of overwriting the ordinary addon. The addon and public
Framework are instrumented; the binding archive and proprietary Core are not.

Use an ASan Redot built from the exact pinned engine source: the official editor's
`RTLD_DEEPBIND` loading is incompatible with ASan. A headless template build must
retain 3D APIs used by mask viewports, GDScript, 2D/3D physics, JPEG/WebP import
support and the fallback text server. This task uses `BUILD_NAME=cubism_asan`,
`use_asan=yes use_lsan=yes debug_symbols=no optimize=debug lto=none`, with graphics
drivers disabled and `disable_3d=no`. No engine source patch is required.

Add `--sanitizer-runtime /private/redot-asan` and
`--sanitizer-library /private/native-asan/bin/libgd_cubism.linux.debug.x86_64.so`
to the native harness. It imports with the normal editor/library, swaps in the
instrumented library for 250 lifecycle cycles, handle and loading-removal tests,
then restores the normal library for graphics/export. The sanitizer processes
use the dummy renderer, leak detection, a 300-second wall-clock bound and explicit
quit bounds. Reports fingerprint both sanitizer binaries. A sanitizer pass does
not establish GPU safety, Core-internal coverage or Windows behavior.
