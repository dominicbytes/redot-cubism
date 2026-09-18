# Legacy assets compatibility

Existing `GDCubismUserModel` scenes and scripts can keep using the `assets`
string. When that source has a Cubism import, the setter loads its
`CubismModelResource` through Redot's normal resource loader. Otherwise it retains
the original raw-file loading path. No import or project write happens in the
runtime setter. The public `model` property remains empty in legacy mode;
assigning `model` clears `assets`, and assigning an empty `assets` unloads it.

To prepare existing scenes for selective, checked exports:

1. Let the model's textures and audio finish importing.
2. Use **Project → Tools → Prepare Legacy Cubism Model** and select the original
   project-local `.model3.json`.
3. Reopen and save each legacy scene using that source. Existing runtime scripts
   can reassign the same `assets` path to reload the prepared model.
4. Use **Project → Tools → Validate and Export Cubism**.

Preparation asks Redot to import the original source. Redot creates and owns its
import metadata and generated output; the addon does not edit those files.
Existing Cubism Import-dock choices are retained. A source assigned to a different
importer is refused. This is distinct from **Import Cubism Model**, which writes
an independently configured `.res` to a user-chosen destination.

Saving a prepared legacy scene stores a hidden `_legacy_model` resource edge
alongside its original `assets` value. Redot can then discover its texture, audio
and native-extension dependencies. The exporter validates the model and injects
its declared raw inputs. The generated resource path comes from Redot, so models
with the same filename in different directories remain distinct. The hidden
property is addon-managed; use `assets` or `model` in game code.

Unprepared scenes, unsaved bridge changes and mismatched bridge references fail
checked export with a scene/node diagnostic. For paths assigned only by script,
include their imported source resources in the export preset or in an exported
resource catalog; a string constructed at runtime does not declare a dependency.
Resource edits follow the same snapshot/reload rules as the explicit `model` API.

Legacy `GDCubismUserModel` playback retains the upstream timing and lifecycle
behavior. A positive finite, SDK-representable update uses the full `delta * speed_scale`;
it is not capped at 0.1 seconds. In manual mode, explicit `advance()` calls also
work outside the scene tree or while tree processing is paused. Detaching and
reattaching a legacy node preserves its model, parameters and active playback.
Explicit unloading, replacing its assets, or deleting the node still releases
that state. The preferred `CubismModel2D` retains its own pause and lifecycle
contract.

Raw legacy loading skips missing or empty optional physics, pose and user-data
files, while rejecting malformed files that are present. It accepts textures
that Redot can load as `Texture2D`, including imported SVG textures. Imported
`CubismModelResource` dependencies retain their stricter validation.

`CubismModelImporter.import_source(source_file)` exposes preparation to editor
tools and returns a Redot `Error`. Call it after filesystem scanning/importing
finishes. It is editor-only; runtime assignment uses the already imported data.

`tools/run_legacy_bridge_tests.py` exercises raw fallback, the native preparation
menu, importer ownership, scene persistence, source switching, inherited and
nested scenes, and source-free checked exports. Its optional `--graphics` run
captures four exported legacy instances with OpenGL. These checks do not replace
the separate Windows and renderer-parity qualification gates.
