# PR 2B native SDK port checkpoint

2026-09-07. Linux x86_64 native builds and real-model smoke tests pass. This is
partial PR 2B coverage, not the full native-port or P0 release milestone.

## Inputs

The official Native SDK 5-r.5 archive was downloaded by the user after accepting
its agreements. ZIP integrity passed. Its SHA-256 is
`7ff3a4bbc19c0a8728965aa522ab77eb11b252916453e68a8a78d3b71188bb12`.
Framework source matches the pinned `145155d2c5bdd8d23475cef9cc3ab46d3220190c`
tree. Core reports 6.0.1 (`0x06000001`); header and platform library hashes are in
`DEPENDENCIES.json`. Redot, API, binding and template identities remain those in
[PR 2A](pr-02a-report.md). Linux uses GCC 16.2.1, binutils 2.47 and SCons 4.11.1.

The internal-development fixture is the unchanged SDK Haru model: manifest hash
`5a41969802b8f9019ca731b07d918fc137e6a61eb9943bdd3f532aeaa0936f8c`, MOC hash
`aa59f7a3dc3b30b23b5f10afd9192ed755e4d01dc9a12442d99b972a418e2543`.
Its copyright notice accompanies the private test project/export. SDK files,
model data, captures and Core-bearing binaries are excluded from public source.

## Changes

Redot-specific changes select the pinned binding/API and descriptor compatibility
settings and expose `CubismBuildInfo.get_versions()`. Upstream class names, entry
symbol, binary names, effect nodes, assets API and shader paths are retained.

R5 changes replace removed loop, expression and blend APIs, update renderer
factory/constructor arguments, implement the two required render-target hooks,
and use `GetRenderOrders()`. Models needing offscreen composition or unsupported
blend pairs fail before renderer creation. See the [SDK matrix](../compatibility/cubism_sdk_matrix.md).

The optional binding profile limits generated classes to the addon and binding
support code. The pinned generator omitted the profile as a dependency, so the
build explicitly adds it. A stale full-profile generation initially produced
unresolved editor-class symbols; a clean task-owned generated tree and the added
dependency fixed it. Linux now rejects unresolved symbols at link time.
Windows Core selection matches the binding's actual CRT flags and rejects
unqualified compiler/architecture choices. That unit test is not a Windows build.

Core informational messages are printed as information rather than warnings.
The new class documentation uses explicit closing tags accepted by Redot's
XML documentation reader. Neither change alters Cubism playback.

## Tests and evidence

The clean committed checkpoint `1ca0e1608d45959fb770f86dd13da2d5f3ff20b2`
was rebuilt and retested after the initial working-tree runs below. Its debug
library SHA-256 is `a0407b8decefa09770d27969c60101f8a9d038158f72f5d5f3e74677b93bc3ec`;
release is `dc888c1d95e748aa5be2fec12d05e9796703fd37e1f3759323cd02166e867b26`.
Both passed seven checks: fresh import, editor restart, runtime, compatibility
graphics, export, exported runtime and exported compatibility graphics. Build
metadata reports the committed revision and `addon_dirty=false`. The filtered
public equivalent is `eec01e1e152edf9b980b97b977d873ac0d73b7d0`;
[public CI passed](https://github.com/dominicbytes/redot_cubism/actions/runs/34168700703).

The first passing debug library hash was
`ad6c5095670a68a33b67632f6b6b734525eb54cc9c928b74933abe62f9f1b7dd`;
release was `15be25ddf987aa783b3e4f9eec70fde78312a2720718d348e5a88f119702b275`.
Those libraries identify local source base `3e760588` with the port working diff.
They passed fresh editor import, editor restart/exit, expected ClassDB entries,
Core/Redot version checks, model/mesh creation, a ten-second Idle motion with
parameter changes and exactly one completion signal, F02 expression parameter
changes, model reload/free, export and real debug/release template execution.
The export ran after moving the source project out of reach. Editor-only plugin
registration was absent from export templates. No runtime errors or warnings
occurred in those passing runs.

Raw reports are private under `.local-build/evidence/pr2b-native/`; the reusable
[test harness](../../tests/native/README.md) documents the commands. Each engine
process has an isolated profile, a 60-second wall-clock timeout and a quit bound.
Haru F01 is unsuitable for this parameter-change assertion: it adds 0.27 to
ParamMouthForm, whose initial/max value is 1. F02 is explicitly selected instead.
Physics and pose are disabled for isolated parameter checks; pose is restored
for visual captures.

A compatibility graphics smoke loaded and captured Haru without shader/runtime
errors through X11, OpenGL 4.2 / Mesa 26.2.2, adapter
`virgl (NVIDIA GeForce RTX 5060 Ti/PCIe/SSE2)`. The capture shows the model with
textures and pose groups. This is virtualized graphics evidence, not physical
GPU qualification or measured parity with the official SDK renderer.

## Remaining gates

Windows debug/release compile/runtime, licensed CI runner provisioning, full
renderer comparisons, lifecycle adversarial tests, importer and checked export,
controller/audio timing and release qualification remain open. Private smoke
exports currently use explicit fixture filters. That workaround does not qualify
the planned general-purpose export workflow. Core-bearing binary publication
requires the separate publication decision in the plan.
