# Troubleshooting

Start with the first editor or test-log error. Keep the engine version, addon
build identity, selected model/resource and relevant report when reproducing a
failure. Public bug reports must exclude licensed model files, private recordings
and local permission records.

| Symptom | Check and recovery |
|---|---|
| Cubism classes or editor menus are missing | Install the entire addon at `res://addons/gd_cubism`, including the matching platform library and descriptor, then restart. Inspect native loader errors and verify Redot 26.2 single precision. |
| `.model3.json` does not appear as a new import | Use Project → Tools → Import Cubism Model; fresh compound-extension discovery is a known stock 26.2 limitation. |
| Model import or export reports stale/missing dependencies | Let texture/audio scanning finish, inspect Model Inspector diagnostics, restore contained source paths, then reimport and reload. Do not hand-edit `.import`/`.md5`. |
| Motion/expression does not play | Use IDs from that imported model, inspect the returned Error/handle, and check pause, speed, process mode and priority. Models do not all declare the same groups. |
| Voice plays but the mouth does not move | Check lip-sync parameters, the selected voice bus and profile, and authored mouth curves that take priority. Give simultaneous speakers separate buses. |
| Model is invisible or reports `rendering_error` | Start with Direct and GL Compatibility. Check scale/visibility, viewport size and supported blend/composition data; read the fallback limits before selecting it. |
| Export works only with broad wildcards | Retain models/audio through resource references or preset selection; prepare and save legacy scenes. Use the checked exporter and its preflight diagnostics. |
| Checked export rejects a native library | Build the actual target OS/architecture/mode and use its matching template. Renaming a debug library does not make it release-compatible. |
| Build fails on a shared filesystem | Put `CUBISM_BUILD_DIR` and compiler/binding outputs on a suitable local filesystem. Keep saved reports outside disposable build caches. |

See [build dependencies](../DEPENDENCIES.md), [import recovery](editor-import.md),
[runtime contracts](preferred-runtime.md), [debug overlays](debug-overlay.md),
[statistics](debug-statistics.md) and [export diagnostics](export-validation.md).
Headless success establishes load/state behavior; graphics and target-platform
checks are still needed for rendering and exported-game failures.

## Very short first editor run crashes on exit

On 2026-09-14, the pinned Linux Redot `26.2.stable.official.4f5b14aba` crashed
during shutdown of a fresh extension project with
`--headless --editor --quit-after 2` while testing addon revision `fd9a0e2`.
The same failure reproduced with a minimal extension containing no Cubism code or
SDK. A captured null pointer and matching engine source/disassembly support an
inference that deferred documentation generation accessed cleared data. The
official binary lacked symbols, so this is not a symbolized function attribution.
This headless reproduction is separate from the later
[Forward+ rendered shutdown failure](compatibility/redot.md#forward-status),
whose exact engine/driver cause remains unknown.

For automated project setup, let the editor finish importing resources. The
following bounded import run passed on a fresh Cubism project; a fresh 60-frame
editor run and a cached restart also passed:

```sh
timeout 120 "$REDOT_BIN" --headless --editor --path /path/to/project \
  --import --quit-after 60
```

These checks establish a working setup path on the tested Linux build, not an
engine fix or Windows qualification. Keep the complete log if a normal editor
session or import-and-quit run fails.
