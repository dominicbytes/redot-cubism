# Cubism for Redot

An unofficial, open-source Live2D Cubism plugin for **Redot Engine LTS 26.2**, with shared
source for **Windows and Linux x86_64**. Based on
[GDCubism](https://github.com/MizunagiKB/gd_cubism), with its original credits
and license preserved. This is an independent Redot port.

Load Cubism models with `CubismModel2D` and `CubismModelResource`, play motions
and expressions, and use `CubismCharacterController` for character and audio
cues. The legacy GDCubism API is retained.

## Get started

Build the addon for your platform, copy `demo/addons/gd_cubism` into your
project's `addons` folder, and use **Project → Tools → Import Cubism Model**.
Use the **GL Compatibility** renderer.

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
Obtain those dependencies separately. This repository contains source, not a
prebuilt binary release or bundled model assets.
