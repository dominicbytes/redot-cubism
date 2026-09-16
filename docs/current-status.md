# Current status and tested evidence

## Linux candidate checked on 2026-09-16

Clean sanitized revision `fd43bd35add05ea348e1a1d7d5e68a773b96471d`
passed both ten-stage Linux desktop suites, 1,660 SDK numeric cases, 92 visual
cases, and 26 sanitizer checks with 250 lifecycle cycles. Its debug/release
libraries also passed 14 scoped checks at 200% editor UI scale: rendered model,
origin selection, scaled dragging, exact undo, readable resource summary, and
clean shutdown. This evidence covers Linux X11 GL Compatibility on the recorded
VM graphics environment; it does not qualify Windows, physical/mixed-DPI panels,
or Forward+.

Later documentation and source-release workflow changes do not change native
behavior, but these results remain attributed to the exact revision above.
Windows qualification, actual public/private CI and required status propagation,
dedicated-hardware benchmark comparison, and final publication remain pending.
The development version remains unreleased. The [source archive workflow](source-release.md)
only prepares a checked source artifact and cannot certify runtime qualification.

## Scoped Windows progress on 2026-09-16

Sanitized source `13d45b96e4b79552c443f1c1e02aa4ed3288603b` produced
Windows x86_64 debug and release DLLs with the pinned VS 2022 v143 toolchain.
Split native, editor, importer, model, and export checks passed in recorded
Windows runs, while the complete ten-stage desktop suites remain open. A private
comparison harness passed 1,660 numeric cases and measured 92 visual cases
against 46 fresh Windows references. The visual limits have not been accepted,
so those measurements are not visual PASS results.

The isolated checked-export repair at `4f2b85402f26f1f5f500b1568f9ca75f9e473cd5`
and lock-cleanup follow-up `48ecf132146a9f92e51c9930f2fef5fa7bdd520a`
passed 7/7 graphical debug and 7/7 release checked-export cases, plus 13/13
focused Python checks on the final exporter source. Tested failure paths preserved
the previous build; a post-promotion lock cleanup error reports PASS with an
actionable warning because the new output is already committed.
The Windows tooling changes at
`77dba74d7db9f18617b745aac6540fe2a0efb508` produced actual debug and
release builds; `bce60670b30702d7d7861cca2b926f7d15c51e52` only corrected
the build guide afterward. These results belong to those identified sources,
not automatically to a later integrated commit.

The combined Windows Python run had 108 tests: 103 passed, four skipped, and
one errored because this host lacks Windows symlink-creation privilege
(`WinError 1314`). The complete debug/release desktop rerun, accepted visual
limits, dedicated performance baseline, private licensed CI, and final
publication decisions remain open. No Windows release qualification is claimed.

## Historical baseline checked on 2026-09-14

The historical results below are keyed to the clean tested baseline
`90f8d18298369a3ecd942928806ed52269e5871c` (2026-09-14). Later source-only
packaging, CI, or documentation commits may advance the checkout; they are not
automatically covered by the results below. Re-key and rerun the relevant gates
before describing a later revision as tested.

The port targets Redot 26.2 single precision and Cubism Native SDK 5-r.5. The
current release decision is **not qualified**: these scoped passes do not establish
Windows support, complete renderer parity, or a distributable release.

## Baseline results

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

## Known boundaries

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
