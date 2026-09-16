# Current status and tested evidence

This page is keyed to the clean tested baseline
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
  diagnostics. This supplement is not a new full native rerun. High-DPI, audible
  audio, and Windows behavior remain open.

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
