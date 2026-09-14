# Migrating from GDCubism

Keep a source-control checkpoint of the original project, then install the entire
Redot addon and matching native libraries. Do not mix old shader/editor helper
files with the port. The original AsciiDoc material is retained as an archive;
its old SDK versions and SubViewport-only instructions are not the current setup.

For gradual migration, existing `GDCubismUserModel.assets` paths remain usable.
To make those scenes exportable, let textures/audio import, choose **Project →
Tools → Prepare Legacy Cubism Model**, select the original project-local
manifest, then reopen and save each scene before checked export. Preparation
creates Redot-owned import metadata; saved scenes gain an addon-managed resource
edge. Do not edit `_legacy_model` or engine metadata manually.

For new scenes, import a `CubismModelResource`, assign it to `CubismModel2D.model`,
and use the [preferred API](../usage/cubism-model-2d.md). Adapt scripts deliberately:
motion calls return retained handles, expression calls use declared IDs, lifecycle
events are deferred, and manual evaluation has explicit pause/speed behavior.
Use `CubismCharacterController` when coordinating audio and character cues.

Remove obsolete manual export wildcards after replacing string-only dependencies
with imported resource references or prepared legacy scenes, and verify the same
selected-resource export. See [legacy compatibility](../legacy-compatibility.md)
for property precedence, source switching and inherited scenes, and
[checked exports](../usage/exporting.md) for validation. Test behavior before
removing legacy nodes; a type rename alone is not a migration.
