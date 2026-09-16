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

## Separate external-input evidence

The tested `90f8d18298369a3ecd942928806ed52269e5871c` baseline also has a
separate Linux GL Compatibility pass using XTest pointer and keyboard events.
It is not part of `tools/run_editor_tests.py`: debug and release each pass 12
checks covering viewport dragging, grid snapping, Inspector transform edits,
undo/redo, selection, save, autoplay/default-motion edits and clean shutdown.
The setup does not write transforms directly after the initial scene setup.

Separate resource-dialog passes cover 8 debug checks and 11 release checks for
clear/load/import, default options, metadata, assignment, save/reload and clean
shutdown. The release pass also records invalid-resource guidance and undo
recovery. A supplemental debug invalid-resource UI recovery pass on the same
`90f8d18` baseline adds 5 checks: an empty resource unloads the model and shows
the import guidance, and Ctrl+Z restores the rendered factory model with a ready
state and clean error field before an exit-0 shutdown. It is supplemental UI
evidence, not a new full native rerun, and does not claim a captured invalid
`get_last_error` value. These Linux default-DPI results do not qualify Windows,
high-DPI or audible audio behavior. See [current status](current-status.md) for
the complete boundary.

A Linux `sanitize=undefined` addon can use this runner with the normal editor.
That instruments addon/Framework code only. Do not preload ASan into the normal
editor: its deep-bound extension loading is incompatible with that setup. See
[sanitizer testing](sanitizers.md) for the separate ASan engine workflow.
