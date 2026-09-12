# Editor model import (provisional)

With the native addon loaded, use **Project → Tools → Import Cubism Model**.
Select a project-local `.model3.json`, then choose a `.res` destination. The
model's PNG and audio assets must already have finished importing. The saved
`CubismModelResource` opens in the Inspector and retains real texture/audio
resource references. Repeating the action replaces the chosen resource after
the editor's save dialog confirmation. Factory diagnostics appear in the
editor output; optional missing-file warnings are stored on the resource.

Editor tools can call
`CubismModelImporter.import_model(source_file, destination, strict_optional_files=false)`.
It returns a Redot `Error`. Destinations must be physically inside the project
and end in `.res` or `.tres`. Validation completes before saving. This API is
editor-only; the saved resource class is available at runtime.

The native importer advertises only `model3.json`, priority 2, import order 100
(after default texture/audio imports), format version 2, and disables threaded
import. It currently exposes only strict optional-file validation. Other planned
options are not yet implemented.

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
not claim selective PCK export. Dialog callbacks are exercised in a headless
editor; manual visual UI verification remains pending.

This action is the plan's provisional fallback. Its saved resources now participate
in [dependency tracking](dependency-tracking.md). The editor refreshes them after
source changes; **Project → Tools → Validate Cubism Models** requests a scan.
Assign the result to `GDCubismUserModel.model` for [runtime playback](resource-runtime.md).
The preferred `CubismModel2D` API and checked export remain unfinished.
