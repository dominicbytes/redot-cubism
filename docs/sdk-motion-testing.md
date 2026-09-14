# SDK motion-state comparison

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
with a fresh model and plays one motion without looping, physics, pose, blink
or breath. The reference applies manifest fade settings and authored blink/lip
targets using SDK APIs. It does not reproduce the addon's motion implementation.

Before comparing values, the native test checks the imported manifest, MOC
and motion hashes against the reference inputs. Every parameter and part ID
must match, and every numeric value must be finite and within `1e-5` absolute
error. Missing cases, mismatched times/identities, runtime errors and timeouts
fail. The report records exact engine, addon, Framework, Core, reference and
test-source identities, commands, logs and per-case differences.

`sdk-motion-report.json` refers only to the listed motions, sample times,
platform and addon variant. This numeric headless test does not qualify visual
rendering, loop/event policy, procedural-effect ordering, audio, export or the
whole desktop release. Keep its generated JSON, logs and copied project
private. Windows qualification requires an actual Windows run.

The comparison also guards JSON numeric fidelity: the runtime retains the
original decimal number tokens when adapting JSON for the SDK. Cubism's R5
parser accumulates decimal digits in single precision, so re-serializing a
number through double precision can change its evaluated value. Compact JSON,
BOM, whitespace, Unicode escapes and scientific notation are exercised through
native loading by `sdk_json_checks.gd`, including exported test projects.
