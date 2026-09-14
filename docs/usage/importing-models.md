# Importing models

Install the complete native addon for the matching Redot build. Copy your
licensed model folder into the project while preserving the manifest's relative
paths. Let PNG and audio imports finish, then choose **Project → Tools → Import
Cubism Model**. Select the `.model3.json` and save the resulting
`CubismModelResource`, normally as a `.res` file in your character folder.

Stock Redot 26.2 recognizes the compound suffix when matching an importer but
does not discover `*.model3.json` on a fresh filesystem scan. Use this explicit
menu action; a catch-all JSON importer or renaming the manifest is unnecessary.

Use the [Model Inspector](../model-inspector.md) to check diagnostics, motion IDs
and expression IDs. Configure enabled optional features and texture policy using
the [import options](../editor-import.md) and [texture guide](../texture-import.md).
The manifest and required MOC/texture data must be valid and contained in the
allowed source tree. Optional dependency handling follows the selected import
settings; inspect warnings rather than assuming every declared effect loaded.

Keep source files available for reimport and export validation. After editing
inputs, allow dependency refresh and inspect the result before reloading a live
model. [Dependency tracking](../dependency-tracking.md) explains supported changes
and recovery. Do not manually edit Redot's `.import` or `.md5` files.
