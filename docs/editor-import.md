# Editor model import (provisional)

With the native addon loaded, use **Project → Tools → Import Cubism Model**.
Select a project-local `.model3.json`, then choose a `.res` destination. The
model's PNG and audio assets must already have finished importing. The saved
`CubismModelResource` opens in the Inspector and retains real texture/audio
resource references. Repeating the action replaces the chosen resource after
the editor's save dialog confirmation. Factory diagnostics appear in the
editor output; optional missing-file warnings are stored on the resource.
The save dialog includes **Strict optional files**, **Import manifest motions**
and **Import expressions** checkboxes. Motions and expressions are enabled by
default; strict optional-file validation is disabled by default.

Editor tools can call
`CubismModelImporter.import_model(source_file, destination, strict_optional_files=false)`.
It returns a Redot `Error`. Destinations must be physically inside the project
and end in `.res` or `.tres`. Validation completes before saving. This API is
editor-only; the saved resource class is available at runtime.

Use `CubismModelImporter.import_model_with_options(source_file, destination, options)`
to supply the same choices by their keys: `validation/strict_optional_files`,
`motions/import_manifest_motions`, and `expressions/import`. All require actual
booleans. Unspecified choices use the defaults. The old boolean-based method
remains compatible. The factory offers `build_with_options(source_path, options)`
for unsaved resources with the same validation.

Disabled categories are not cataloged, loaded, or included in dependency hashes;
their missing content does not warn or fail strict optional-file validation.
Manifest structure and path safety are still checked before filtering. The source
manifest is untouched. The saved options survive dependency changes and editor
restart. Reimport with a category enabled to restore its descriptors and dependencies.
An independent engine-managed import of the raw `.model3.json` uses its own
Import dock settings. Creating a separate `.res` does not change those settings.
If Redot imports that source as well, configure its categories in the Import dock;
default motion loading can still report a missing declared motion even when a
separate `.res` intentionally omits motions. Source import settings are never
silently overwritten to match one of potentially several derived resources.
`motions/convert_to_redot_animation=false` is accepted; true reports that P1
conversion is unavailable. Other unsupported or misspelled options fail explicitly.

The native importer advertises only `model3.json`, priority 2, import order 100
(after default texture/audio imports), format version 5, and disables threaded
import. The Import dock exposes the same three implemented choices. Remaining
planned settings, including motion discovery and mask quality, are not implemented.

**Project Settings → Cubism → Import → Maximum File Count** limits the manifest
plus unique normalized source paths in enabled catalogs. The default is 1,024; allowed
integer values are 1–4,096. Missing optional references still count, while repeated
references to the same file count once. Disabled motion/expression references
are excluded. Generated textures and engine import sidecars are not source files
for this budget. The parser's separate 4,096-reference bound and all byte, pixel,
type and path limits remain in force regardless of this setting.

The limit applies to factory and editor imports and participates in the import
fingerprint. Lowering it can fail validation while preserving the last saved
model; raising it allows reimport without changing source files. It is a project
policy, not a per-model option. Invalid types or values fail with a diagnostic
naming `project_settings.cubism/import/maximum_file_count`.

## Stock discovery limitation

On pinned Redot 26.2 (`4f5b14aba`), a fresh project with the native addon and Haru
imports its textures/audio but creates no `Haru.model3.json.import`, including
after restart. The editor's filesystem processing checks the final extension
against `valid_extensions` before reaching its compound-suffix import check.
The UID startup scan likewise checks the final extension. No catch-all JSON
importer or engine-owned import metadata workaround is installed.

Reproduce with the following command, with `REDOT_BIN` set to the pinned editor:

```sh
python tools/run_importer_tests.py --model /path/to/Haru.model3.json \
  --library /path/to/native-library --output /persistent/results \
  --template /path/to/matching-template
```

The report records `automatic_discovery` separately
from explicit import checks. Ordinary JSON and backup files must remain unclaimed.
Coexistence with a generic JSON importer and automatic UID discovery are pending.
The template check loads and animates the resource from the isolated test project; it does
not claim full-model selective PCK export. Dialog callbacks are exercised in a headless
editor. The new checkbox layout and defaults have also been checked in a rendered
Linux X11/GL editor; full interactive workflow and other platform checks remain pending.

This action is the plan's provisional fallback. Its saved resources now participate
in [dependency tracking](dependency-tracking.md). The editor refreshes them after
source changes; **Project → Tools → Validate Cubism Models** requests a scan.
Assign the result to `GDCubismUserModel.model` for [runtime playback](resource-runtime.md).
The preferred `CubismModel2D` API and checked export remain unfinished.
