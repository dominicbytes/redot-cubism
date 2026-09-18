# SDK-free compatibility test

This fixture tests the Redot binding and editor/export APIs before linking Cubism.
`CubismAbiNode` and `CubismAbiResource` are test classes, not model-runtime stubs.
Do not package this project as the addon or report its tests as Cubism playback.

Use the exact Redot editor and binding commit in `DEPENDENCIES.json`. Clone the
public binding to a native filesystem, check out the pin, and set `REDOT_CPP_ROOT`.
Keep debug/release object suffixes separate. The small profile includes `OS`
because the pinned binding's diagnostic implementation requires its generated API.

From the repository root, with Python and SCons available:

```sh
export REDOT_BIN=/path/to/redot
export REDOT_CPP_ROOT=/path/to/pinned/redot-cpp
export CUBISM_ABI_OUTPUT=/path/to/abi-build
python tools/verify_dependencies.py --output /path/to/identity
python -m SCons -f tests/abi/SConstruct platform=linux arch=x86_64 \
  target=template_debug precision=single \
  custom_api_file=/path/to/identity/extension_api.json -j4
export CUBISM_ABI_LIBRARY="$CUBISM_ABI_OUTPUT/libcubism_abi.linux.template_debug.x86_64.so"
python tools/run_abi_tests.py --output /path/to/results \
  --template /path/to/matching/linux_debug.x86_64 --export-mode debug
```

Repeat with `target=template_release`, the release library, release template and
`--export-mode release`. Template `--version` must match the editor exactly.
The generic JSON importer is a deliberate competing test plugin; the planned
production importer registers only `model3.json`.

Checks cover native registration, Unicode resource serialization, internal
processing with a script override and regular processing disabled, scene pause,
detach/reentry without another `_ready`, automatic suffix selection, importer
coexistence, UID stability across editor restart, raw-file injection and clean
template launch with the source project moved away. The exporter precheck is a
synthetic required-file prototype, not the PR 9 model-dependency validator. It
does not establish that stock Export-menu callbacks can cancel a failed export.

The runner records logs, library/template/export hashes and explicit scope flags.
It uses a unique project and user profile, a 60-second timeout per process and
bounded frame counts. Nonzero exits, missing success markers, errors and warnings
fail. Editor diagnostic sockets must be permitted by the host. Editor builds may
register editor-level classes even in game mode; actual export templates must not.

Windows remains a separate build/run gate. No graphics, SDK/model behavior,
render parity, audio, private CI or stable release claim follows from this test.
