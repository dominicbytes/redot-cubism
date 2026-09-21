# Cubism for Redot

An unofficial, open-source Live2D Cubism plugin for **Redot Engine LTS 26.2**, with shared
source for **Windows and Linux x86_64**. Based on
[GDCubism](https://github.com/MizunagiKB/gd_cubism), with its original credits
and license preserved. This is an independent Redot port.

Load Cubism models with `CubismModel2D` and `CubismModelResource`, play motions
and expressions, and use `CubismCharacterController` for character and audio
cues. The legacy GDCubism API is retained.

## Get started

**PREVIEW:** Prebuilt ZIPs for Redot 26.2 single precision and the
**GL Compatibility** renderer are being prepared on the
[preview release page](https://github.com/dominicbytes/redot-cubism/releases/tag/redot-26.2-preview-2026-09-20).
After publication, download the Windows x86_64 ZIP or the Linux x86_64 ZIP,
which requires glibc 2.43 or newer, and extract it into your project root.
You can also build the addon from source using the guides below.

- [Setup and first character](docs/quick-start.md)
- [Windows build](docs/build/windows.md) · [Linux build](docs/build/linux.md)
- [API reference](docs/api-reference.md) · [Examples](demo/addons/gd_cubism/examples/character_workflows/README.md)
- [Troubleshooting](docs/troubleshooting.md) · [Documentation](docs/README.md)

## Compatibility and status

Windows and Linux debug/release builds and scoped runtime checks have passed.
The tested dependency set is Redot 26.2 single precision and Cubism Native SDK
5-r.5; exact versions and hashes are in [dependencies](DEPENDENCIES.md).

A Windows C# test reported an intermittent shutdown warning. A focused check
exited cleanly after pending audio playback cleanup; the earlier warnings are
not conclusively attributed; warning-free managed shutdown remains unqualified.
See [tested scope and limitations](docs/current-status.md) and
[publication status](docs/gamedev/publication-status.md).
Other renderers and platforms are not qualified by these checks.

## License and dependencies

The plugin is open source under the [MIT license](LICENSE.en.adoc). Cubism SDK,
Core and model assets have separate terms; see [licensing](docs/licensing.md).
This source repository does not contain SDK/Core binaries or model assets.
The preview ZIPs contain native libraries that statically link Cubism Core;
their included third-party notices and separate terms remain applicable.
