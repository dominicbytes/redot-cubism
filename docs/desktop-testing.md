# Desktop functional sequence

`tools/run_desktop_tests.py` executes the existing licensed functional runners
in dependency order for one platform/build variant. Run it separately for Linux
and Windows, debug and release, with locally provisioned SDK-built libraries,
a matching Redot editor/template, and a permitted model with motions and a known
non-neutral expression:

```sh
REDOT_BIN=/private/redot python tools/run_desktop_tests.py \
  --model /private/model/character.model3.json --expression Smile \
  --library /private/build/libgd_cubism.linux.debug.x86_64.so \
  --other-library /private/build/libgd_cubism.linux.release.x86_64.so \
  --template /private/templates/linux_debug.x86_64 \
  --mode debug --output /private/desktop-results
```

For release, swap the two libraries and provide the release template and mode.
On Windows set `REDOT_BIN` and `PYTHONUTF8=1` in the environment and supply the
native DLL and EXE paths. Child harnesses also force UTF-8 for Unicode fixtures.
A Windows build must run on Windows; cross-compilation alone is not
qualification. Both libraries must have matching source/dependency inputs.

The sequence runs physical-path checks; legacy and imported-resource native
playback/render/export; the [editor lifecycle](editor-testing.md); fresh import
and live dependency replacement; preferred-model playback, effects, examples,
30-second audio timing and export; selective export; checked-export failure
preservation and its editor dialog; legacy export rejection/bridge behavior;
and rejection of the opposite native build variant in a checked export.

Each invocation creates a unique directory below `--output`. Its
`desktop-report.json` is updated before and after each stage, so a crash cannot
turn unfinished work into a passing run. Child exit status, report status,
reported library/engine identity, and individual check statuses must agree.
Failure stops subsequent stages. Each stage has a 30-minute wall-clock bound
in addition to the child harness's own process timeouts. Logs and fixture
projects remain in that directory. Allow several GB of free space per run.

`status: PASS` refers to this functional sequence on the recorded platform and
variant. `release_qualified` remains false: sanitizer lifecycle, the complete
SDK visual fixture matrix, dedicated performance thresholds, remaining manual
editor checks, the other platform/variant, and publication review are separate
required gates.

`run_tests.py --suite licensed-desktop --output /private/licensed-results`
builds both variants and runs the functional sequences, normal and uncapped
manual-step SDK comparisons, visual comparisons against reviewed limits, all
eight benchmarks against a reviewed baseline, and Linux ASan/UBSan lifecycle
checks. It uses the private environment variables listed below; SDKs, fixtures,
limits and baselines must already exist. It does not download them or generate
acceptance thresholds. The same `tools/run_licensed_tests.py` implementation is
used locally and by private CI.

Each invocation creates a fresh `licensed-<platform>-...` directory containing
`licensed-desktop.json`, build directories, child reports and logs. Configuration
errors exit 2 before building. Failed commands, missing reports, mismatched
library/engine identities, incomplete functional stages, measurement-only visual
or benchmark results, and incomplete combined sanitizer coverage fail the run.
Subsequent stages stop after failure. Builds and functional sequences have
one-hour and 90-minute limits respectively; other suites have 30-minute limits
(benchmarks allow 2500 seconds). A timeout terminates the child process tree.

A passing aggregate covers the supplied fixtures on that native host. Its
`release_qualified` remains false until the complete approved fixture matrix,
other platform, remaining manual editor checks and publication review are also
verified. Wiring this command does not establish that those runs have occurred.

The aggregate frontend can also run the editor or all five export stages against
a retained passing fixture from the same library and pinned editor:

```sh
python tools/run_tests.py --suite editor \
  --native-report /private/native/native-report.json \
  --library /private/build/libgd_cubism.linux.debug.x86_64.so \
  --output /private/editor-results

python tools/run_tests.py --suite export \
  --importer-report /private/importer/importer-report.json \
  --library /private/build/libgd_cubism.linux.debug.x86_64.so \
  --other-library /private/build/libgd_cubism.linux.release.x86_64.so \
  --template /private/templates/linux_debug.x86_64 \
  --export-mode debug --output /private/export-results
```

Set `REDOT_BIN` as above. Keep the prepared projects referenced by the input
reports; copying only their JSON files is insufficient. Editor runs require a
graphics session. Export runs include the checked-export dialog and graphical
legacy bridge. A fresh directory below `--output` contains `editor.json` or
`export.json`, child reports and logs. Missing or failing child reports fail the
aggregate even if the child exits zero. These commands qualify only their named
suite; `release_qualified` remains false.

For licensed CI, execute reviewed commits in an isolated private runner with
locally provisioned SDK/model inputs. Do not expose that runner, its cache, or
its artifacts to public pull-request jobs. These output directories contain
licensed models and must not be uploaded to public workflow artifacts.
GitHub's [runner security guidance](https://docs.github.com/en/actions/reference/security/secure-use)
explains why persistent self-hosted runners require isolation.

## Private CI setup

`.github/workflows/desktop-functional.yml` is a manual workflow for a private
mirror of reviewed source. Its first job rejects public repositories before
selecting a licensed runner. It has no pull-request trigger, SDK download,
artifact upload, or public cache. Supply the full reviewed commit SHA when
dispatching it; configure approval on the private `licensed-desktop` environment
before attaching runners. See GitHub's [workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
for manual dispatch and environment settings.

Provision one isolated runner per target with the `cubism-licensed` label and
the standard `Linux` or `Windows` label. Each must provide these environment
variables: `REDOT_BIN`, `REDOT_CPP_ROOT`, `CUBISM_SDK_ROOT`, `CUBISM_WORK_ROOT`,
`CUBISM_MODEL`, `CUBISM_EXPRESSION`, `CUBISM_TEMPLATE_DEBUG`,
`CUBISM_TEMPLATE_RELEASE`, `CUBISM_MOTION_PROJECT`, `CUBISM_MOTION_FIXTURES`,
`CUBISM_VISUAL_PROJECT`, `CUBISM_VISUAL_FIXTURES`, and `CUBISM_VISUAL_LIMITS`.
Prepare the private SDK captures and reviewed adapter-specific limits using
[visual testing](visual-testing.md). Install `tools/requirements-visual.txt`
in the runner's project-local Python environment before running the workflow.
`CUBISM_MOTION_PROJECT` and `CUBISM_MOTION_FIXTURES` identify the prepared project
and explicit fixture list described in [SDK motion testing](sdk-motion-testing.md).
Paths refer to that runner's private filesystem.
The Linux runner also requires `CUBISM_SANITIZER_RUNTIME`, pointing to the
matched ASan Redot test engine described in [sanitizer testing](sanitizers.md).
It must be provisioned before dispatch; Windows does not use this Linux-only gate.
Install the pinned Python/SCons toolchain and compiler first. Windows currently
requires VS 2022/MSVC 14.3; other toolsets fail the Core-library selection check.
The runner needs an interactive graphics session for real editor/render tests.

Performance acceptance additionally requires these runner variables:

- `CUBISM_BENCHMARK_PROJECT`, `CUBISM_BENCHMARK_RESOURCE` and
  `CUBISM_BENCHMARK_MASK_RESOURCE`: the prepared project and its two imported
  model resource paths.
- `CUBISM_BENCHMARK_MOTION` and `CUBISM_BENCHMARK_EXPRESSION`: authored IDs used
  by the eight workloads.
- `CUBISM_BENCHMARK_RUNNER_ID`: the stable dedicated-machine identity used when
  recording the baseline.
- `CUBISM_BENCHMARK_BASELINE`: the reviewed baseline report on that machine.
- `CUBISM_BENCHMARK_RELATIVE_THRESHOLD`: the reviewed nonnegative fractional
  regression limit, such as `0.10` for 10%; no default is supplied.

Record and review a baseline with [the benchmark runner](benchmarks.md) before
dispatching licensed CI. Use its default 60 warmup and 300 measured frames and
the same fixture IDs. Configuration must match the baseline, including the
runner, engine, graphics driver and benchmark scripts. A changed measurement
script requires a newly reviewed baseline. Missing inputs or a missing baseline
file fail before any build; mismatched identities or regressions fail the job.

The workflow verifies the editor/API, builds both native variants sequentially,
then runs each functional sequence and the independent SDK motion comparison
and visual tests for both variants. It then runs all eight benchmark scenarios
with the debug library and requires the baseline comparison to pass. A failed
comparison fails the job. The benchmark report and raw measurements are retained
in `benchmark-debug` alongside the other private build/test artifacts under
`CUBISM_WORK_ROOT/<run-id>/<attempt>/licensed-<platform>-...`. Retain that directory privately or use a
private artifact store. Provisioning, environment approval, actual Windows runs,
and required status propagation to the public release branch must still be
completed; merely committing the workflow does not satisfy those release gates.

On Linux the workflow also builds a separate `address,undefined` addon/Framework
library and runs the existing native sanitizer sequence: runtime identity,
descriptor shutdown, 250 lifecycle cycles, handles and loading/removal. It checks
the reported instrumentation modes and completed cycle count; an ASan-only
result cannot satisfy the combined gate. A build failure, test failure, missing
report or incomplete sanitizer coverage fails the job. The instrumented library
and logs stay under the private run's `build-asan-ubsan` and `sanitizers` folders.
Ordinary debug/release libraries remain available for the graphical tests.

## Dependency updates

`.github/dependabot.yml` schedules weekly review PRs for GitHub Actions and the
Redot binding submodule. No auto-merge workflow is installed. The configuration
uses GitHub's [supported Dependabot ecosystems and schedule fields](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference).

A binding update PR does not update the reviewed pin in `DEPENDENCIES.json`.
Review compatibility, update that pin and generated API identity deliberately,
and rerun the licensed matrix before merging. Engine and Cubism Framework/Core
updates also require an explicit compatibility review; the automation never
downloads or replaces the licensed SDK. Dependabot begins operating only after
this configuration is present on the repository's default branch.
