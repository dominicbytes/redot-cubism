# Cubism for Redot

An unofficial, open-source Live2D Cubism plugin for **Redot Engine LTS 26.2**, with shared
source for **Windows and Linux x86_64**. Based on
[GDCubism](https://github.com/MizunagiKB/gd_cubism), with its original credits
and license preserved. This is an independent Redot port.

Load Cubism models with `CubismModel2D` and `CubismModelResource`, play motions
and expressions, and use `CubismCharacterController` for character and audio
cues. The legacy GDCubism API is retained.

## Get started

Build the addon locally for Redot 26.2 single precision and the **GL
Compatibility** renderer. Obtain Cubism Native SDK 5-r.5 separately, extract it
under `.local-build/sdk/CubismSdkForNative-5-r.5`, and follow the setup guide.
Source builds link Core statically by default. A Windows external-Core package
instead lets each user install the verified DLL from their own SDK copy without
a compiler; see the Windows guide. The package and repository do not contain
Cubism Core.

External-Core previews: [Linux](https://github.com/dominicbytes/redot-cubism/releases/tag/redot-26.2-linux-sdk-external-preview-2026-09-20) ·
[Windows](https://github.com/dominicbytes/redot-cubism/releases/tag/redot-26.2-windows-sdk-external-preview-2026-09-21).
Each user must obtain the official SDK separately and run the included installer.

- [Setup and first character](docs/quick-start.md)
- [Windows build](docs/build/windows.md) · [Linux build](docs/build/linux.md)
- [API reference](docs/api-reference.md) · [Examples](demo/addons/gd_cubism/examples/character_workflows/README.md)
- [Troubleshooting](docs/troubleshooting.md) · [Documentation](docs/README.md)

## Compatibility and status

Windows and Linux debug/release builds and scoped runtime checks have passed.
The tested dependency set is Redot 26.2 single precision and Cubism Native SDK
5-r.5; exact versions and hashes are in [dependencies](DEPENDENCIES.md).

## License and dependencies

The plugin is open source under the [MIT license](LICENSE.en.adoc). Cubism SDK,
Core and model assets have separate terms; see [licensing](docs/licensing.md).
Obtain those dependencies separately. External-Core preview packages contain
the addon binaries and installer source, but no SDK/Core binaries, headers,
import libraries or model assets.
