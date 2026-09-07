# Private native smoke tests

This harness loads the actual linked Cubism plugin with a locally provisioned
model. It checks editor registration, runtime classes and version metadata,
model/mesh creation, a real motion's parameter changes and completion signal,
expression parameter changes, model reload, and shutdown. Physics and pose are
disabled during the parameter checks to isolate native motion/expression behavior.

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
