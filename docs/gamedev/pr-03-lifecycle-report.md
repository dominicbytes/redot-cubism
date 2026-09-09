# PR 3 lifecycle hardening — work in progress

2026-09-09. Linux debug and release each pass all 19 native/export checks.
The final sanitizer run also passes 250 lifecycle cycles, motion handles and
removal during loading. Windows and actual minimization evidence remain open. This does not complete the native-port milestone or P0 release.

## Changes under test

Required updates use native internal-process notifications, with exactly one
idle/physics source or manual advancement. Tree reentry recreates the runtime;
teardown invalidates retained parameter references and cancels motion handles.
Explicit load states and structured errors cover failed and partial loads.

Model signals are deferred and generation-checked. Native loading and custom
effect callbacks defer conflicting unload/reload operations until the active
native call unwinds. In particular, the loading-removal test removes the model
from its parent while renderer children enter the tree. The guard keeps the
native model alive through that load operation before disposing it.

Framework startup remains extension-wide with static allocator/options.
Tracked live models are cleared before Framework disposal. Core version is
checked against the pinned SDK. Hot reload remains disabled.

The pinned binding's Dictionary move assignment overwrites existing storage.
The load-error snapshot uses a const local to select copy assignment instead.
The final workaround passes normal-runtime checks and the 250-cycle sanitizer
run with leak detection enabled. No binding revision or SDK
pin was changed for this workaround.

## Current evidence

Inputs remain pinned in `DEPENDENCIES.json`. The private fixture is unchanged
SDK Haru with the F02 expression, as described in the
[native port report](pr-02b-native-report.md). No SDK, fixture or linked binary
is included in public source.

Debug library SHA-256:
`c5c5251c618e81ad98c3223939fb6068727a253d573152766e53617558b27f51`.
Release library SHA-256:
`2e24bfc8eb1037993c7824e519ec6cda993dddcbe07166f9fa09191e65a41826`.
Both are working-tree builds based on local commit `1ca0e16`, not a clean
release or published PR 3 checkpoint.

Before the added visibility regression, all 17 checks passed in both debug and release: fresh import, editor restart, runtime playback, internal
processing, lifecycle, removal during loading, handles, deltas, graphics,
export, and the seven applicable runtime/graphics checks in the exported game.
The source project was moved out of reach for exported execution. Native and
exported PNGs are byte-identical, SHA-256
`1d501356905615dc06493f581ea530dcf0e09a5c5cc1aacfaa39b9331a0e9232`.
The inspected capture renders Haru; it is not measured SDK-renderer parity.

Five visibility cycles retained 91 owned nodes in both graphics runs. Both
reported `minimize_observed=false`; actual minimization remains unverified.
These are Linux virtualized compatibility-renderer results, not physical GPU
or Windows qualification. The editor probe is a downstream smoke test, not
before/after proof of an upstream Windows crash fix.

Private reports, logs and captures are retained under
`.local-build/evidence/post-expansion-debug-full/` and
`.local-build/evidence/post-expansion-release-full/`. The
[native harness instructions](../../tests/native/README.md) describe the test
commands and boundaries. The public suite separately passed 24 tests and the
restricted-file audit; it does not test Cubism runtime behavior.

## Visibility regression update

The initially hidden mask regression failed on the baseline binary, then passed
with visibility notifications updating mask viewport modes. All 17 debug checks
passed with the fix, including exported processing and graphics. Debug library
SHA-256: `450b625dbf23f9d63a38394044773f4b8fc328ebcc42bc2001ba7f64c5280b98`.
Evidence is retained in `.local-build/evidence/visibility-debug/`. Native and
exported captures retain the baseline hash above. Local and inherited visibility
cycles suspend masks without stopping manual animation or adding owned nodes.
The release visibility build also passed all 17 checks; SHA-256:
`b5c75ea3f0cb8ffb2882e160061f7f88e1c12e827e141681b2861012bbe0c1b4`.
Evidence is retained in `.local-build/evidence/visibility-release/`. An explicit
zero-model startup/shutdown test has since been added to native and exported
runs; the expanded 19-check debug and release suites both passed. Their reports, logs
and captures are retained in `.local-build/evidence/lifecycle-empty-debug/` and
`.local-build/evidence/lifecycle-empty-release/`. The debug
zero-model log already shows exactly one Framework initialization and disposal.
The final sanitizer run passed all 12 selected checks: nine normal headless
checks followed by 250 lifecycle cycles, handles and loading-removal under
ASan/LSan. No sanitizer errors or leaks were reported. Runtime SHA-256:
`e3054e06289fc0375bf761d073cae537819bdbe6fdc1fa71d94980386e4815d0`.
Instrumented addon SHA-256:
`be5064cb56918e7c078574500ba9e9ea5d9b26bfce68e99dcb0be6f428578afc`.
Evidence is retained in `.local-build/evidence/lifecycle-final-asan/`.
Instrumentation covers the engine, addon and public Framework. Core and the
binding archive are not instrumented; the dummy renderer does not qualify GPU
behavior.

## Remaining acceptance gates

- Validate final committed binaries; working-tree debug and release tests pass.
- Obtain actual minimized-window and Windows editor/runtime evidence.
- Revalidate the final committed build, update local records, audit all staged
  files and filtered publication history, then publish source and verify CI.

Renderer ordering/masks, the importer, checked export, full animation/controller
and audio contracts, editor tooling and release qualification remain subsequent
plan stages. The fixture-specific export harness does not replace checked export.
