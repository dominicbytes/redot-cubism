# Editor workflow regression

Run the real editor against a private fixture prepared by a passing
`tools/run_native_tests.py` run. The fixture must retain its project directory
and use a known non-neutral expression. Use the matching editor version and
test each debug/release addon separately:

```sh
REDOT_BIN=/private/redot python tools/run_editor_tests.py \
  --native-report /private/native-results/native-report.json \
  --library /private/build/libgd_cubism.linux.debug.x86_64.so \
  --output /private/editor-results
```

The runner copies the prepared fixture to a unique directory below `--output`,
preserves imported resources, installs the selected library, and starts an
isolated editor with no initial scene. It uses X11 on Linux and the default
display driver on Windows, GL Compatibility rendering, and dummy audio. The
process is bounded to 180 seconds. Reports, logs, scenes, and the editor capture
remain private: they contain or refer to the licensed test model.

The editor plugin test exercises empty-scene mouse input; preferred-model
assignment through the editor undo manager; undo/redo; invalid-resource recovery;
selection; motion/expression preview; scene saving without generated drawables;
reopening; selected-node deletion; and closing a scene during preview. It also
selects, deletes, and closes the legacy node, then verifies empty-scene input
again. Debug builds check that runtime-owned resources return to zero.

`editor-report.json` passes only with a zero exit code, the completion marker,
no logged errors/warnings, and a saved capture. Inspect the capture as part of
visual review; its existence alone does not prove rendering correctness.
`--headless` is available for diagnostics and records `graphics: false`; it does
not qualify graphical editor behavior.

These checks use actual editor APIs and injected input. They do not exercise
mouse-driven inspector edits, toolbar undo shortcuts, viewport dragging, grid
snapping, high-DPI behavior, or audio output. They cover part of the release's
editor requirements and do not replace the remaining platform and UI checks.

## Compatibility and remaining acceptance

Use the supported Redot 26.2/26.3 runtime selected for the passing native report.
Saving even an empty scene through `EditorInterface.save_scene()` requests an
editor thumbnail. In headless mode, Redot 26.2/26.3's dummy renderer reports
`Parameter "t" is null` at `texture_2d_get` in its texture storage header, line 115.
This also reproduces without the addon. The headless diagnostic gate tolerates
only that exact error and dummy-renderer callsite pair (including Windows source
separators); every other error or warning still fails. Graphical runs tolerate
none of these messages. Headless results cannot qualify graphical editor behavior.
Managed workflows, external input, UI scaling and audible output require separate acceptance. See
[current status](current-status.md) for platform compatibility limits.

A Linux `sanitize=undefined` addon can use this runner with the normal editor.
That instruments addon/Framework code only. Do not preload ASan into the normal
editor: its deep-bound extension loading is incompatible with that setup. See
[sanitizer testing](sanitizers.md) for the separate ASan engine workflow.
