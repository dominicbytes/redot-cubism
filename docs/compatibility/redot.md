# Redot compatibility

Native runtime targets are **Redot 26.2 and 26.3 single precision**. Both use
one binary built against the **26.2 binding ABI**, pinned to
`4f5b14abade2239104847d03d8f9056e4467cfcd` and redot-cpp
`9e7161bd7a3572a36ffa93109e73169861e9f834`. The 26.3 reference is
`85e5203945af15755dd2f66cb6fdf7545fd88c0b`. Keep editor/export templates matched
to each other; they need not match the addon's binding baseline.

Set `REDOT_BIN` to the runtime editor and `REDOT_BINDING_BIN` to the pinned
26.2 editor, then require `tools/verify_dependencies.py` to pass. Build with its
root `extension_api.json`; the separate `runtime/` dump is diagnostic only.
The descriptor's `compatibility_minimum="26.2"`, demo feature version and class
documentation baseline remain 26.2 intentionally. No public API is renamed.
Exact hashes are in [DEPENDENCIES.json](../../DEPENDENCIES.json).

The engine interface differs only by appending Struct at Variant type 39.
The addon-used rendering, viewport, image, import/export, resource-loader and
audio class signatures are unchanged. Bindings are staged in a private build
copy with a bounds check in `Variant::clear`; unknown engine types delegate
destruction to the engine instead of indexing the older cleanup table.

26.3 Windows headless checks exercise the same debug/release DLLs as 26.2.
Official 26.3 can crash during headless editor import/shutdown even without the
addon; compare a plugin-free control and a corrected engine before attributing
such a crash. Test runners keep crashes as failures. Neither rendering parity,
Linux 26.3 nor 26.3 Mono is certified by these Windows headless checks. The
retained C# project remains pinned to `Redot.NET.Sdk/26.2.0`.

Godot binaries, Redot releases after 26.3, double precision and other architectures
are not certified by the current evidence. Do not substitute their API dumps or
assume newer Godot APIs exist in this engine. The project remains `project.godot`
and the retained binding submodule folder remains `godot-cpp`.

Linux and Windows x86_64 have scoped debug/release runtime and export coverage
using GL Compatibility. This does not qualify every engine, platform and renderer
combination or complete the release gates. See [current status](../current-status.md)
for supported workflows and remaining qualification limits,
[desktop testing](../desktop-testing.md) for the required checks, and the
[SDK matrix](cubism_sdk_matrix.md) for SDK compatibility.

## Forward+ status

Forward+ remains unqualified. Use **GL Compatibility** for the tested renderer
path. A rendered frame alone does not establish passing lifecycle behavior or
visual parity. Qualify each renderer and target platform separately, with its
own reviewed visual limits and clean shutdown checks.

## Import and export limitations

Stock 26.2 needs the explicit **Import Cubism Model** menu for fresh compound
`.model3.json` discovery. Its export dependency scan also does not enumerate
GDScript `preload()` dependencies: retain dynamically chosen resources explicitly,
and keep the examples' attached Interface script. The checked-export pipeline
validates the actual preset dependency selection.
