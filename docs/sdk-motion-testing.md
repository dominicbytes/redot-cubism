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

Use `"expression_switch": {"id": "Smile", "step": 30}` to start another
native expression immediately before a one-based evaluation step (1–36000).
The default empty object schedules no change. The initial `expression` may be
empty, and the scheduled ID may repeat the initial ID. Each play gets a fresh
expression instance and retains its file's fade settings. Both expression files
are checked against the imported resources' hashes. Include samples before the
switch, at its first update and during the overlap. This checks native SDK
switching; the addon's explicit clear-to-primary adapter has separate tests.

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
rendering, event dispatch or interruption policy, other procedural effects,
explicit expression clearing or fade overrides,
audio, export or the whole desktop release. Keep its generated JSON, logs and copied project
private. Windows qualification requires an actual Windows run.

The comparison also guards JSON numeric fidelity: the runtime retains the
original decimal number tokens when adapting JSON for the SDK. Cubism's R5
parser accumulates decimal digits in single precision, so re-serializing a
number through double precision can change its evaluated value. Compact JSON,
BOM, whitespace, Unicode escapes and scientific notation are exercised through
native loading by `sdk_json_checks.gd`, including exported test projects.

The runtime refreshes legacy part-opacity values after the final evaluation
stage. Writes queued by legacy epilogue callbacks remain pending for the next
update.

## Comparison scope

Use effect matrices with expression, physics, pose and breathing enabled/disabled
separately and in combination, alongside motion-only controls. Include early
samples to check fresh effect state, and require each enabled effect to change
parameters or part opacity in its SDK reference control. Compare both build
variants independently; matching numeric samples do not extend qualification
beyond the selected inputs and times.

Look fixtures should cover neutral, opposite-direction and clamped fixed targets
from fresh smoothing state, with samples after the neutral first update. Moving
targets, weights and pause/reload controls belong to the separate native look
suite.

For looping, bracket the first and second loop boundaries and the following
fade-in, comparing looping off/on with motion-only and full-effect fixtures.
Event counts, terminal reasons and explicit stop/interruption behavior remain
separate motion API tests.

Expression-switch fixtures should include same-ID replay, different-ID
transitions and a delayed first expression, with and without the other effects.
Sample before, at and after the scheduled change; reject mismatched expression
hashes even for samples before the switch. Explicit expression clearing and fade
overrides remain outside this independent comparison.
