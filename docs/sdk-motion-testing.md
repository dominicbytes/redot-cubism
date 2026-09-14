# SDK motion and effect-state comparison

`tools/run_sdk_motion_tests.py` builds a small numeric reference executable from
the locally installed, pinned Cubism Framework and Core. It compares that SDK
evaluation with `CubismModel2D` playback in a copy of a prepared Redot project.
It does not require changes to the SDK sample or link the addon into the
reference executable. SDK sources, libraries, models and generated references
remain private; none are supplied by this repository.

Prepare a project containing imported `CubismModelResource` files using the
supported model importer. Create a private JSON fixture list. Model paths are
absolute or relative to the JSON file; resource paths belong to the project:

```json
[
  {
    "model": "models/Character/Character.model3.json",
    "resource": "res://Character.res",
    "motions": [{"group": "Idle", "index": 0}]
  }
]
```

To compare native effects, add optional fields to each motion entry. Omitted
fields preserve the original motion-only test:

```json
{"group": "Idle", "index": 0, "expression": "Smile", "physics": true, "pose": true, "breath": true, "look": [700, -500]}
```

`expression` is an exact manifest expression name (empty string disables it).
`physics` and `pose` must be booleans, and their manifest files must exist when
enabled. `breath` is a boolean that enables the standard R5 OpenGL sample's
five-parameter breathing profile through SDK `CubismBreath`; it needs no extra
manifest file. Include entries with each effect disabled/enabled separately and in
combination to verify that selected effects actually change the reference state.
The same motion may appear more than once with different effect selections.

Set `loop` to `true` to repeat a motion; it defaults to `false` regardless of
the source motion's loop flag. Both evaluators use R5 V2 looping with loop
fade-in enabled. Select steps around the source duration plus one source frame,
and subsequent cycles, to exercise the endpoint correction and repeated fade.
At 60 Hz, a source duration of 10 seconds with 30 FPS has a 602-step cycle;
fractional durations may put the boundary between two evaluation steps.

`look` is either an empty array (the default, disabled) or two finite node-local
pixel coordinates, each within +/-10,000,000. The reference uses the manifest's
SDK model-layout inverse to convert these coordinates, then normalizes and clamps
each axis to [-1,1]. SDK `CubismTargetPoint` smooths the target, and `CubismLook`
applies the standard six-parameter profile at full weight. Redot receives only
the local target through `set_look_target()`. A fresh target's first SDK update
is neutral; include subsequent early steps when checking its acceleration.

The independent SDK reference loads fresh effect objects, applies the native
expression fade settings, and evaluates each step in this order: load saved
primary parameters, motion, save primary parameters, expression, breath, look, physics, pose,
Core update. Physics begins at the SDK's fresh-load state without a separate
stabilization call. Pose initializes through its first normal update. Redot uses
its own native public playback/effect controls; no expected parameters or part
values are assigned to the candidate model.

```sh
REDOT_BIN=/private/redot python tools/run_sdk_motion_tests.py \
  --sdk-root /private/CubismSdkForNative-5-r.5 \
  --project /private/prepared-project \
  --library /private/libgd_cubism.linux.debug.x86_64.so \
  --fixtures /private/fixtures.json --output /private/motion-results
```

Repeat with the release library. Linux requires a C++17 compiler (`CXX`, default
`g++`). On Windows use the VS2022 MSVC14.3 x64 Native Tools environment, set
`REDOT_BIN` and `PYTHONUTF8=1`, and supply native DLL/EXE paths. The reference
uses the pinned Core MD library and `/MD`; it is independent of the addon's CRT.
Linux uses `-fwrapv` to define the SDK's signed string-hash arithmetic without
editing SDK sources. Python needs only its standard library. Output must be
outside the prepared project and allow native execution. The test copies
imported files as-is; it does not edit engine import metadata.

The private desktop workflow runs this comparison at the default 60 Hz and at
2 Hz with the explicit manual test flag, for both build variants.
Provision `CUBISM_MOTION_PROJECT` and `CUBISM_MOTION_FIXTURES` on each runner as
described in [desktop CI setup](desktop-testing.md#private-ci-setup).

The default samples are steps 1, 30, 90 and 180 at 60 Hz. Use `--steps` and
`--fps` (10–240) to select additional samples. For 1–9 Hz, explicitly add
`--uncapped-manual-step`; this enables the runtime's manual test flag and records
it in the report. Without that option the runner removes any inherited flag,
preserving the normal 0.1-second delta cap. Both evaluators start motion time at zero
when playback is accepted; the first evaluated step is `1 / fps`. This avoids
the SDK sample manager's default first-update start offset. Each case starts
with a fresh model and plays one motion, looping only when explicitly selected.
Physics, pose, breath, look and
expression are off unless explicitly selected in the fixture; blink,
lip-envelope and custom effects remain off. The reference applies manifest fade settings and authored blink/lip
targets using SDK APIs. It does not reproduce the addon's motion implementation.

Before comparing values, the native test checks the imported manifest, MOC
and motion hashes against the reference inputs. Selected expression, physics
and pose files must also match their recorded hashes. Every parameter and part ID
must match, and every numeric value must be finite and within `1e-5` absolute
error. Missing cases, mismatched times/identities, runtime errors and timeouts
fail. The report records exact engine, addon, Framework, Core, reference and
test-source identities, commands, logs and per-case differences.

`sdk-motion-report.json` refers only to the listed motions, sample times,
platform and addon variant. This numeric headless test does not qualify visual
rendering, event dispatch or interruption policy, other procedural effects, expression transitions,
audio, export or the whole desktop release. Keep its generated JSON, logs and copied project
private. Windows qualification requires an actual Windows run.

The comparison also guards JSON numeric fidelity: the runtime retains the
original decimal number tokens when adapting JSON for the SDK. Cubism's R5
parser accumulates decimal digits in single precision, so re-serializing a
number through double precision can change its evaluated value. Compact JSON,
BOM, whitespace, Unicode escapes and scientific notation are exercised through
native loading by `sdk_json_checks.gd`, including exported test projects.

The Linux debug and release comparison covers Haru Idle/0 with F03 and Mao
Idle/0 with exp_02, each with all eight expression/physics/pose combinations
at the four default sample times: 64 cases per variant. All values match within
the unchanged `1e-5` tolerance. Separate SDK comparisons against motion-only
controls confirm that each selected effect changes parameters or part opacity.
Expression and physics first change the sampled state at step 30; pose changes
it at step 1 for both models.

These checks exposed a stale legacy part-opacity accessor: pose and queued
part writes ran after its cached value was read. The runtime now refreshes
unchanged part values after the final evaluation stage. Writes queued by legacy
epilogue callbacks remain pending for the next update. The node regression
fails on the earlier library and passes with this fix. This result covers the
listed native effect states; it does not expand the release scope above.

The same Linux matrix also compares breathing off/on for every combination:
128 cases per debug/release variant. All states match the SDK at `1e-5`, and
every breathing-on reference differs from its corresponding off control at
these sample times. The debug and release parameter/part results are identical.
This verifies the standard breathing profile in the listed effect order; it
does not qualify procedural blink timing, look targets or effect transitions.

The independent look matrix adds a local target to each of those combinations,
plus neutral, opposite-direction and clamped targets with the full effect stack.
At steps 1, 2, 8, 30, 90 and 180 at 60 Hz, all 420 cases per Linux variant match
the SDK at `1e-5`. The 32 first-step look controls stay neutral; all 160 later
paired controls change when look is enabled. Debug/release results are identical,
and the previous 128 breathing controls are unchanged. This covers a fixed target
from fresh smoothing state; moving targets, weights and pause/reload controls
remain covered by the separate native look suite, not this independent oracle.

The Linux loop matrix compares Haru and Mao Idle/0 with looping off/on, both
motion-only and with the full expression/breath/look/physics/pose combination.
Fifteen 60 Hz samples bracket the first and second loop boundaries and include
the following fade-in. All 120 cases per variant match the SDK at `1e-5`, and
debug/release states are identical. Initial loop/one-shot controls agree; later
looped states differ from the completed one-shot controls. This checks repeated
native curve/effect evaluation; event counts, terminal reasons and explicit
stop/interruption behavior remain separate motion API tests.
