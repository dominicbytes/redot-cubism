# Current status and tested evidence

## Development status on 2026-09-17

The Linux and Windows source is public in
[dominicbytes/redot-cubism](https://github.com/dominicbytes/redot-cubism).
[Draft PR #1](https://github.com/dominicbytes/redot-cubism/pull/1) targets this
Redot repository, not the original Godot project. Publication is source-only:
there is no qualified binary release, and the SDK and private test models are
not bundled. The release decision remains **not qualified**.

The preceding published qualification snapshot is
`b338d9cd8527321bfa566ca827e3696a59a79dd3` on
`review/windows-integration`. Its [public push CI](https://github.com/dominicbytes/redot-cubism/actions/runs/35292818863)
passed all 110 Python tests and source/history/format checks; draft PR CI also
passed at its merge commit. The private source mirror passed hosted source CI at
`00e3d521652df6e28ab8420ea5b0928f49303e55`. No licensed native job has
executed for this snapshot. Passing source CI does not establish native release
qualification.

## Windows parser robustness checkpoint

Clean source `a6133baf7b45c20a6550a9b6949ac25885bb1267` fixes two
reproduced import-option diagnostic defects: nontext keys now produce a text
path, and echoed option names are limited to 4096 characters. Valid short
String/StringName option names retain their behavior. The only production
file changed from the preceding snapshot is `src/cubism_import_options.cpp`.

Fresh Windows x86_64 debug and release builds used the same pinned VS 2022,
Redot API, bindings and SDK. The debug DLL SHA-256 is
`6fd521d19da3dee9bd68af94936c55c465717908848dd86e25704e406942e983`;
release is `8780a937517cb589858f43891e13ef25513e903554715cb42acb8fd16bc218fe`.
Both builds report this exact source commit and `addon_dirty=false`.

The [bounded parser fuzz gate](parser-fuzzing.md) passed 108 cases twice per
variant, for 432 fresh worker executions. It covers the six planned input
targets, explicit parser boundaries, malformed UTF-8 and a 2 MiB option key.
There were no crashes, timeouts, memory/output-limit violations, unexplained
engine diagnostics, or same-input replay differences in this fixed-seed
campaign. The original failing runs are retained privately. These checks
supply no MOC/model input to proprietary Core; the linked library still
initializes Core at startup. This is scoped Windows evidence, not exhaustive
fuzzing, a Linux result, or binary release qualification.

The real-model Windows importer retest also passed all 23 stages in each
variant with these rebuilt DLLs and matching export templates. Its import-option
stage passed 88 assertions, including the eight new diagnostic regressions;
restart, cache removal, runtime and exported-resource checks passed with clean
logs outside the deliberately marked invalid-input checks. An initial sandbox
attempt failed to access the Windows certificate store and is retained
separately; the accepted runs used the normal Windows user context. The
three graphical dependency-change stages were outside this headless retest.

## Windows builds and scoped checks

Clean integrated source `bc0c6ed82262ca573524c5223085ed596543cd55`
produced Windows x86_64 debug/release DLLs with VS 2022, MSVC 19.44.35221
(VCTools 14.44.35207). Both use the pinned editor, bindings and SDK documented
in [dependencies](../DEPENDENCIES.md). At clean source
`55dd0604d605586e79f65664d448f78d9a8dad36`, the complete Windows debug
and release desktop suites each passed all ten stages with those frozen DLLs.
That evidence belongs to `55dd060`, not to the later source snapshot. On those
same DLLs, earlier split-stage evidence recorded:

- Graphical native/runtime checks passed 59/59 per variant and importer checks
  26/26. The complete debug Model2D sequence passed 45/45; the original release
  sequence failed after 39 checks at `exported-debug-overlay`. A separate fresh
  complete release sequence passed 45/45. The original failure remains recorded.
- The editor capture harness at `8e85f48892024862decf20bc4ca1abafbf52dc95`
  passed 51 debug and 44 release assertions with real rendered captures.
- Export selection passed 30/30 and legacy export 8/8 per variant. The repaired
  checked-export helper at `9c5ce939ee2af710c3a39b92c25352cf38e15809`
  passed legacy bridge 6/6, export identity 2/2 and checked export 7/7 per variant.
  The repair retains `.godot/imported` in isolated snapshots so copied import
  remaps can resolve their generated resources; editor state remains excluded.

The later `b338d9c` change only bundles an existing icon for a legacy addon
example and adds its scene dependency regression. Independent retesting copied
the whole addon into five fresh Windows projects: imports passed 5/5, a clean
installed-host all-resources export and source-absent texture load passed 2/2,
and source-absent exported lifecycle checks passed 20/20 across debug/release
and legacy/primary paths. This targeted retest does not reattribute the full
`55dd060` desktop suites to `b338d9c`. An earlier release overlay test crashed
with `0xC0000005`; the original intermittent failure's cause remains unproven.
The editor capture timeout and missing imported-resource export failures were
reproduced and repaired; their original failing reports are retained.

At `b338d9c`, the separate [SDK-free ABI fixture](../tests/abi/README.md)
built with pinned Windows inputs and passed 8/8 import, restart, export
and source-absent exported-runtime checks in each debug/release variant. Its
importer is synthetic and does not exercise a licensed Cubism model. A private
production-importer coexistence check installed the complete `b338d9c` addon
and frozen integrated DLLs alongside a test-only generic JSON importer at
priority `0.5`, below the Cubism importer's `2.0`. Fresh import and restart
checks passed 4/4 per variant: the real Haru `.model3.json` selected
`CubismModelResource`, ordinary JSON selected the generic importer, a backup
suffix remained unimported, and the model's positive UID stayed stable across
restart. These conditional results do not change stock Redot's compound-suffix
discovery limitation without a generic JSON importer.

A later fresh visual run used `b338d9c` visual scripts/shaders and the frozen
`bc0c6ed` debug/release DLLs. All 92 comparisons across 16 family/variant runs
passed against unchanged reviewed SDK references and RGB/alpha limits on
Windows RTX 5060 Ti / GL Compatibility. This renders transferred SDK states;
it does not qualify native effect evaluation, external editor input, Linux,
or the later `a6133ba` DLLs.

The overlay capture harness at `35eb5b3e1461a2af1cf3d1548902f30955d62a70`
now waits for process frames and explicitly draws before reading pixels.
Its unchanged 99 assertions passed in debug and release exports, both normally
and with automatic rendering deliberately disabled (four clean runs on the
same integrated DLLs). The previous harness stalled under that controlled
condition and crashed during forced shutdown with a matching diagnostic
signature. This fixes the demonstrated capture starvation; it does not prove
that the same condition caused the original intermittent failure.

Earlier source `13d45b96e4b79552c443f1c1e02aa4ed3288603b` passed
1,660 SDK numeric comparisons and 92 fresh Windows visual comparisons against
independently reviewed, fixture-specific limits (16 runs, eight visual families).
This is scoped GL Compatibility evidence on the recorded Windows adapter, not
a new visual run on the integrated DLLs. Lifecycle scenarios also passed on that
earlier source. Eight benchmark scenarios were measured. Nine original-build
calibration runs across three sets remained inconsistent, with no accepted
baseline or candidate comparison and therefore no performance qualification
verdict.

The Git symlink source-package fixture was repaired at
`234bb2920eee0f2bd247f5954f8ef96ce6cf2f9a`. The separate Windows
filesystem-link prerequisite was subsequently run with the required privilege:
all 18 real-link cases and JSON-read validation passed. The latest published
source suite passed 110/110 in public CI, as recorded above.

## Linux validation snapshots

The [2026-09-18 Linux snapshot](linux-validation-2026-09-18.md) records fresh
`55dd060` debug/release builds, completed desktop coverage with the `6299432`
test-only correction, 384 SDK comparisons, 92 visual cases, and 250 sanitizer
lifecycle cycles. Debug coverage is composite; its original aggregate remains
failed. Release passed one complete ten-stage run. The later `b338d9c` icon
change passed a focused installed-addon asset check with the frozen libraries.

Three complete VM benchmark trials passed all eight workloads (7,200 measured
frames), with qualification `MEASURED_ONLY`. An earlier offscreen attempt ended
without a result; its focused rerun and the three full trials passed, but the
initial exit remains unexplained. The linked snapshot preserves source/library
identities, measurement ranges, limitations and pending release gates.

A later targeted follow-up on clean `3d1ed62` rebuilt both Linux variants for
the import-option diagnostic fix. Each passed 108 parser cases with two replays
and all 23 real-model importer stages, including 88 option assertions. Canonical
parser results matched both Windows variants. See the linked snapshot for the
new library hashes and the boundary between this targeted run and older full
suite evidence.

### Earlier build and load checks

Source `234bb2920eee0f2bd247f5954f8ef96ce6cf2f9a` was built in both
variants with GCC/G++ 12.2.0, GNU ld 2.40, Python 3.14.7 and SCons 4.11.1.
Both libraries passed strict headless load/build-identity checks and normal
bounded editor-import runs. This is a separate build environment from the
historical compiler record in `DEPENDENCIES.json` and does not repeat the full
graphical suite below. Earlier `--quit-after 2` import attempts crashed during
editor layout loading; normal `--quit-after 1000` runs passed. The short-bound
failures remain recorded, without a proven root cause.

## Remaining release gates

- Complete current-source cross-platform native qualification and Windows
  external pointer/keyboard editor acceptance at the required UI scale.
- Resolve or disposition the intermittent Windows overlay and Linux early-exit
  failures with adequate evidence.
- Execute licensed native CI on both platforms and verify required status
  propagation; hosted source checks alone are insufficient.
- Establish a dedicated performance baseline and reviewed relative thresholds.
- Complete the distribution review and notices for any future binary package.
  Public plugin source does not grant rights to separately licensed Core or models.

The [source archive workflow](source-release.md) prepares a checked source
artifact; it cannot certify runtime or binary-distribution qualification.

## Earlier Linux candidate checked on 2026-09-16

Clean sanitized revision `fd43bd35add05ea348e1a1d7d5e68a773b96471d`
passed both ten-stage Linux desktop suites, 1,660 SDK numeric cases, 92 visual
cases, and 26 sanitizer checks with 250 lifecycle cycles. Its debug/release
libraries also passed 14 scoped checks at 200% editor UI scale: rendered model,
origin selection, scaled dragging, exact undo, readable resource summary, and
clean shutdown. This evidence covers Linux X11 GL Compatibility on the recorded
VM graphics environment; it does not qualify Windows, physical/mixed-DPI panels,
or Forward+.

These results remain attributed to that exact revision and environment; later
build and script evidence is listed separately above.

## Historical baseline checked on 2026-09-14

The historical results below are keyed to the clean tested baseline
`90f8d18298369a3ecd942928806ed52269e5871c` (2026-09-14). Later source-only
packaging, CI, or documentation commits may advance the checkout; they are not
automatically covered by the results below. Re-key and rerun the relevant gates
before describing a later revision as tested.

The port targets Redot 26.2 single precision and Cubism Native SDK 5-r.5. The
current release decision is **not qualified**: these scoped passes do not establish
Windows support, complete renderer parity, or a distributable release.

## Historical baseline results

- Linux x86_64 debug and release desktop-functional suites pass their ten staged
  sequences, including native model/runtime checks, importer/resource paths,
  preferred-model behavior, legacy compatibility, checked exports and exported
  identity checks. The tested graphics path is GL Compatibility.
- Linux debug and release SDK-numeric comparisons pass 830 cases each (1,660 total)
  across look, loop, expression-switch, all-motion and manual-step matrices at the
  documented `1e-5` tolerance. This is numeric/headless coverage, not visual,
  audio, event/interruption, or Windows qualification.
- Linux GL Compatibility visual acceptance passes 92 reviewed cases across
  transforms, effects, pair ordering and additive coverage, in straight and
  premultiplied texture encodings and both debug/release variants. The review is
  limited to the recorded Linux graphics environment and is not external approval.
- The combined Linux sanitizer run passes 26 native checks and 250 lifecycle
  cycles. Addon/Framework address+undefined and ASan-engine coverage do not
  instrument proprietary Core or qualify graphics/export behavior.
- Separate Linux default-DPI editor evidence passes 12 external pointer/keyboard
  checks for each debug/release variant. Separate resource-dialog evidence passes
  8 debug and 11 release checks, including release invalid-resource guidance and
  undo recovery. A supplemental debug invalid-resource UI recovery pass adds 5
  checks on the same baseline library: empty-resource unload guidance, restored
  factory-model rendering after undo, ready state, and clean exit without
  diagnostics. This supplement is not a new full native rerun. At that baseline, supplemental high-DPI coverage had not yet been included
  in this page. Current-candidate scope is stated above; physical audible output
  remains unqualified rather than a P0 requirement.

## Historical baseline boundaries

- Use GL Compatibility for the tested environment. Forward+ remains unqualified:
  the debug attempt rendered an initial fixture but failed during shutdown, and
  the plugin-free control reproduces a shutdown failure under the tested Forward+
  path. Release Forward+, other GPUs, and Windows are not covered.
- Stock Redot 26.2 does not fresh-discover compound `*.model3.json` files. Use
  **Project → Tools → Import Cubism Model** as described in the
  [import guide](usage/importing-models.md); do not add a catch-all JSON importer.
- Private CI provisioning and status propagation, a dedicated performance baseline
  with a reviewed threshold, the remaining manual/editor checks, and final
  package/legal/history review remain open.

See the [quick start](quick-start.md), [current API reference](api-reference.md),
[desktop test scope](desktop-testing.md), [editor test scope](editor-testing.md),
[visual-test limits](visual-testing.md), and [publication status](gamedev/publication-status.md)
for the detailed contracts and qualification boundaries.
