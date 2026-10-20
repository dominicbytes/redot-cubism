# Current status and compatibility

## Source and public previews

The Windows and Linux source is available in
[dominicbytes/redot-cubism](https://github.com/dominicbytes/redot-cubism).
Two Redot 26.2 x86_64 external-Core previews are published:

- [Linux preview](https://github.com/dominicbytes/redot-cubism/releases/tag/redot-26.2-linux-sdk-external-preview-2026-09-20).
- [Windows preview](https://github.com/dominicbytes/redot-cubism/releases/tag/redot-26.2-windows-sdk-external-preview-2026-09-21).

These packages contain debug/release addon libraries and installer source.
Cubism Core, SDK headers/sources and models must be obtained separately.
Follow the [Linux](build/linux.md) or [Windows](build/windows.md) installation
instructions and [licensing requirements](licensing.md). Preview availability
does not establish complete release qualification or extend the packages'
tested engine version.

## Engine compatibility

Current native source supports Redot **26.2 and 26.3 single precision**, using
Cubism Native SDK **5-r.5** and the pinned 26.2 binding API. When building with a
26.3 runtime, select the pinned 26.2 binding editor with `REDOT_BINDING_BIN`.
See [dependencies](../DEPENDENCIES.md) and the [quick start](quick-start.md).

Windows source-built debug/release libraries have scoped headless model,
Variant, lifecycle and exported-playback coverage on both engine families.
Official 26.3 headless editor import/shutdown can produce crashes or leak
diagnostics also reproduced without the addon; those failed gates remain
failures. Linux 26.3, graphical 26.3 workflows and managed 26.3 exports remain
unqualified. The public 26.2 preview packages are separate from these source
compatibility checks.

## Supported workflows and limits

- Use **GL Compatibility** for the tested rendering path. Forward+, additional
  graphics devices and complete cross-platform renderer parity remain unqualified.
- Use **Project > Tools > Import Cubism Model** for a fresh `*.model3.json`
  import; stock Redot 26.2 does not automatically discover that compound suffix.
  See [importing models](usage/importing-models.md).
- Standalone legacy models retain native state across tree exit/reentry.
  Explicit unload, replacement and deletion release that state. Preferred
  `CubismModel2D` nodes manage their owned runtime separately.
- The [C# regression probes](../tests/csharp/README.md) cover selected wrapper
  behavior on 26.2. They do not establish full wrapper coverage or warning-free
  managed shutdown across configurations.
- [Editor regression](editor-testing.md) uses injected editor APIs/input;
  graphical and external pointer/keyboard acceptance remain separate.
- [Benchmarks](benchmarks.md) provide reproducible measurements. Performance
  acceptance requires a reviewed baseline and thresholds on a dedicated runner.

## Remaining qualification

Complete current-source native and graphical coverage on both platforms,
external editor input and UI scaling checks, licensed CI/status propagation,
and a reviewed performance baseline before claiming complete release
qualification. Resolve unexplained runtime or shutdown diagnostics against the
exact engine/library combination being distributed.

See [desktop testing](desktop-testing.md), [visual testing](visual-testing.md),
[sanitizers](sanitizers.md), and [source packaging](source-packaging.md) for the
reproducible gates and their limits. A passing source archive check does not
certify native runtime behavior or distribution rights.
