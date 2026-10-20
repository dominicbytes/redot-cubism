# Licensed runtime benchmarks

`tools/run_benchmarks.py` runs the eight scenarios listed below on the
real GL Compatibility renderer. It requires a private, prepared Redot project
with imported `CubismModelResource` files and a matching **debug** addon library.
It copies that project into a new directory under the selected output folder
and installs the selected library and current repository shaders;
it does not reimport or modify the input project's assets. Supply your own
licensed models. No SDK models or binary fixtures are included in this repository.

```sh
REDOT_BIN=/path/to/redot python tools/run_benchmarks.py \
  --project /private/prepared-project \
  --library /private/libgd_cubism.linux.debug.x86_64.so \
  --resource res://character.res --mask-resource res://complex-character.res \
  --motion Idle/0 --expression Smile \
  --output /private/benchmark-results
```

The runner verifies the pinned Redot version and clears Cubism test/reference
environment overrides before measuring.

Windows uses the matching debug DLL and native window backend; Linux uses X11.
This runner does not establish Windows qualification until executed there.
The standard model must have the supplied motion/expression, physics data,
blink targets and lip-sync targets. The mask-stress resource must actually
produce at least eight mask composition viewports; a smaller fixture fails.

| Scenario | Models | Configuration |
|---|---:|---|
| Static | 1 | No motion or procedural effects; masks enabled |
| VN | 2 | Looping idle motion, deterministic blink/breath, synthetic amplitude through `CubismLipSync` |
| Party | 3 | Looping motion and expression |
| Crowd | 8 | Looping idle motion, blink, Low masks, no physics/pose/breath |
| Masks | 1 | High masks, at least eight mask compositions |
| Physics | 3 | Looping motion with physics enabled |
| Offscreen | 8 | Crowd settings, placed outside the viewport, mask updates paused offscreen |
| Hidden | 8 | Crowd settings, visibility false |

Each scenario starts a fresh engine process, uses a 1024×768 viewport, disables
VSync and the FPS limit, and advances simulation by exactly 1/60 second per
rendered frame. This measures throughput with reproducible simulation steps;
simulation time need not equal wall time. VN lip samples exercise envelope and
parameter work without audio playback. Recorded-audio synchronization remains
covered by the separate controller timing tests.

The default run warms up for 60 rendered frames and records 300 frames. Override
with `--warmup` and `--samples` (minimum two and 100 respectively). Per-scenario
JSON retains raw samples; `benchmark-report.json` contains average, median,
nearest-rank p95 and p99 for:

- wall time between rendered frames, including scheduling and harness overhead;
- CPU model and renderer update microseconds;
- submitted vertex-buffer bytes and distinct mask redraw requests;
- engine-tracked static memory and renderer-reported video memory in bytes.

See [diagnostic counter semantics](debug-statistics.md). Memory measurements
include engine/harness allocations and caches; they are not process RSS, a
complete count of proprietary Core allocations, or a GPU driver memory audit.
The report also stores live resource counts and verifies ownership returns to
zero after every scenario. A run fails on missing features, errors/warnings,
timeout, incomplete/invalid measurements, surviving ownership, or offscreen/
hidden mask requests. Each scenario has a 300-second wall-clock limit.

A successful first run has `qualification: MEASURED_ONLY`. It is **not** a
performance acceptance gate. For a reviewed baseline on dedicated hardware,
use a stable `--runner-id` both when recording and comparing, then supply the
baseline report and an explicitly reviewed fractional threshold:

```sh
# Add these arguments to the same command/configuration used for the baseline:
--runner-id dedicated-linux-gpu \
--baseline /private/baseline/benchmark-report.json --relative-threshold 0.10
```

Comparison requires matching runner identity, OS/machine, engine hash/version,
graphics device/driver, benchmark script hashes, settings and imported fixture
fingerprints. Addon and shader hashes are recorded but may differ, allowing comparisons
between revisions. Every metric's p95 is checked; a regression larger than the
threshold fails. A zero baseline permits only zero. No tolerance is selected
implicitly. Repeat measurements under controlled conditions before reviewing a
baseline; a VM measurement is useful evidence but does not replace the
dedicated-runner gate.

`tools/run_tests.py --suite benchmark` exposes measurement and baseline comparison
through `--benchmark-project`, `--library`, `--resource`, `--mask-resource`,
`--motion`, `--expression` and `--output`. It also accepts `--runner-id`, `--baseline`
and `--relative-threshold` with the same meanings as above. Baseline and threshold
must be supplied together, with a nonempty runner ID; no threshold is inferred.
Use `run_benchmarks.py` directly to override sample counts.

The aggregate creates a fresh directory below `--output` containing its
`benchmark.json` and the underlying `benchmark-report.json`. It checks the child
report as well as its exit status. The aggregate copies `qualification` into its
own report: `MEASURED_ONLY` is a completed measurement run, while
`BASELINE_COMPARISON_PASS` requires all eight scenarios to pass the reviewed
comparison. `release_qualified` remains false in both cases. Missing reports,
incomplete scenarios or mismatched library/engine identities fail the command.
Reports and copied projects can contain
licensed assets and private paths; keep them private unless separately reviewed.

## Compatibility and qualification

The runner accepts the supported Redot 26.2/26.3 runtime families. Use a matching
prepared project and debug library; engine acceptance alone does not qualify a
platform, renderer or performance baseline. See [current status](current-status.md)
for compatibility limits. Keep per-run measurements and machine evidence private.
