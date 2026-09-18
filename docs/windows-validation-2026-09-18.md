# Windows validation snapshot (2026-09-18)

Windows x86_64 debug and release libraries built from clean source
`02e15cfdfb4a42df2b5ba4979f2c3d31d3b0b9ec` passed the focused native
followup for the Linux parity repairs. The C# source and managed exported apps
also exercised audio-driven mouth values and scene reentry successfully, but
the first plain run of each managed export reported an ObjectDB leak at exit.
These results establish the behavior below, not warning-free release qualification.

## Native results

Both variants passed full legacy `advance(0.5)`, paused/off-tree stepping,
retained parameter identity and active motion across reentry, masks, and
motion-finished callback restart. The raw-asset checks passed with textured
models, missing or empty optional physics/pose/user-data files, rejection of
malformed present files, and imported SVG textures. A corrected strict-import
case rejected a missing optional dependency with a valid physics filename.
The earlier invalid-suffix fixture tested a different rejection path and was
retained separately.

A GL Compatibility frame after reentry visibly contained the model in both
variants. The tested adapter was an NVIDIA GeForce RTX 5060 Ti. These checks
cover the changed native paths; earlier importer/export evidence retains its
original source and binary attribution.

| Input/artifact | Identity |
| --- | --- |
| Redot editor | `26.2.stable.official.4f5b14aba` |
| Bindings | `598ec78e86b2c240a023f6de13daba70f7de8610` |
| SDK | Cubism SDK for Native 5-r.5 |
| Windows debug DLL SHA-256 | `4846835c0f3d43a2d5c485c92f495452d9ec5ed8105c4a22ad8f48143e27825a` |
| Windows release DLL SHA-256 | `14a0e1ff75919e87cb832e568617bfd47c97e393602cdf3135eb07f19ce3ffb5` |

## C# results and open warning

The official Redot `26.2.stable.mono.official.4f5b14aba` editor, .NET SDK
8.0.423 and official 8.0.29 Windows runtime packs built and exported the demo.
Compilation had zero errors and seven existing CS8981 naming warnings.
Source and saved debug/release apps drove the actual mouth parameter from
0 to 1 before and after reentry, retained the model, and exited with code 0.
No crash occurred in these probes. This does not establish audible speaker
output, rendered C# scene coverage, or every upstream wrapper surface.

Each first plain exported run also printed
`WARNING: ObjectDB instances leaked at exit`. Later diagnostic runs did not
identify the leaked object or reproduce that warning; verbose runs did print
three engine input-map diagnostics concerning `misc2`. A private lifetime
diagnostic observed the model, effect and all 48 tracked parameter native IDs
become invalid after cleanup; it did not prove collection of managed wrappers.
A minimal plugin-free Mono audio control exited cleanly
and showed the same surviving analyzer/playback objects before shutdown.
That lifetime observation is not addon-specific, but a clean control cannot
attribute the intermittent warning or establish that it is harmless.

The initial Mono console export stalled after publishing and packing.
Launching the same official Mono GUI editor directly in headless mode allowed
both exports to complete normally. This was a test-launcher correction; no
plugin code changed during this Windows followup.

The managed shutdown warning remains open. GL Compatibility is the proven
renderer scope; these results do not qualify Forward+, other architectures,
or a binary release. The tests do not establish redistribution rights for
Cubism Core, SDK components or models, or approve a binary release. Proprietary
Core, model assets, binaries and raw private test artifacts are not included in
this source repository.
