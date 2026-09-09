# Private native smoke tests

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
