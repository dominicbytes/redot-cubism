# Redot compatibility

The target is **Redot 26.2 single precision**, pinned to
`4f5b14abade2239104847d03d8f9056e4467cfcd`. Use matching editor/export templates
and the Redot binding commit `598ec78e86b2c240a023f6de13daba70f7de8610`.
Generate the extension API with the installed editor and require
`tools/verify_dependencies.py` to pass. Exact hashes are in
[DEPENDENCIES.json](../../DEPENDENCIES.json).

Godot binaries, later Redot releases, double precision and other architectures
are not certified by the current evidence. Do not substitute their API dumps or
assume newer Godot APIs exist in this engine. The project remains `project.godot`
and the retained binding submodule folder remains `godot-cpp`.

Linux x86_64 debug/release, native model playback and exported-template checks
have passed; graphical evidence uses GL Compatibility. Windows x86_64 remains a
required unqualified target. Full visual acceptance and final release gates are
separate from successful loading. See [desktop testing](../desktop-testing.md)
and the [SDK matrix](cubism_sdk_matrix.md).

## Forward+ status

A separate Linux test on 2026-09-14 used stock Redot 26.2, Vulkan 1.4.343,
and the `Virtio-GPU Venus (NVIDIA GeForce RTX 4080 SUPER)` adapter. The debug
plugin rendered the first SDK-reference transform fixture, but the process
segfaulted during shutdown. The visual runner correctly rejected that capture;
the remaining fixtures and release variant were not qualified.

The shutdown failure also reproduces without Cubism: a project containing only
a `SubViewport` and `ColorRect`, waiting for five rendered frames, reading back
the image, freeing the viewport and quitting exits with SIGSEGV under Forward+.
The same control exits
normally under GL Compatibility. Repeating the Forward+ control on the VM's
native filesystem eliminates shared-folder shader-cache errors but retains the
crash. A debugger catches a worker thread executing an unresolved address during
shutdown; the exact engine/driver cause is not established.

Use GL Compatibility for this tested environment. This result does not establish
Forward+ behavior on other GPUs or Windows, and a rendered frame alone is not a
passing lifecycle or visual-parity test. Keep Forward+ results and reviewed
visual policies separate from GL Compatibility.

## Import and export limitations

Stock 26.2 needs the explicit **Import Cubism Model** menu for fresh compound
`.model3.json` discovery. Its export dependency scan also does not enumerate
GDScript `preload()` dependencies: retain dynamically chosen resources explicitly,
and keep the examples' attached Interface script. The checked-export pipeline
validates the actual preset dependency selection.
