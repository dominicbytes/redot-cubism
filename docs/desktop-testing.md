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
required gates. The aggregate `run_tests.py --suite licensed-desktop` remains
unqualified until all required gates are connected and verified.

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
`CUBISM_MODEL`, `CUBISM_EXPRESSION`, `CUBISM_TEMPLATE_DEBUG`, and
`CUBISM_TEMPLATE_RELEASE`. Paths refer to that runner's private filesystem.
Install the pinned Python/SCons toolchain and compiler first. Windows currently
requires VS 2022/MSVC 14.3; other toolsets fail the Core-library selection check.
The runner needs an interactive graphics session for real editor/render tests.

The workflow verifies the editor/API, builds both native variants sequentially,
then runs each functional sequence. Builds and reports remain under
`CUBISM_WORK_ROOT/<run-id>/<attempt>`. Retain that directory privately or use a
private artifact store. Provisioning, environment approval, actual Windows runs,
and required status propagation to the public release branch must still be
completed; merely committing the workflow does not satisfy those release gates.

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
