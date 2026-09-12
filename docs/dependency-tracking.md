# Dependency tracking

Resources saved through the [editor importer](editor-import.md) retain their
source path and an import fingerprint. While the editor is open, the native
plugin checks their referenced files and rebuilds resources whose inputs change.
The Project → Tools → Validate Cubism Models action requests an immediate scan.
Import errors appear in the editor output; the last successfully saved resource
is preserved when validation fails.

The fingerprint covers exact source bytes, referenced MOC/JSON/texture/audio
files, explicit missing-file markers, texture/audio import sidecars, all stored
import options with their defaults, importer format and resource schema versions, and pinned
addon/SDK/Redot API identity. Import sidecars remain owned by Redot: the plugin
reads them and asks EditorFileSystem to reimport assets. It does not rewrite them.
The current project-wide file-count limit also participates in the fingerprint,
so changing that policy revalidates existing model resources without a source edit.
Disabled motion/expression catalogs are filtered from both the factory dependency
list and the tracker scan. Changing their files does not invalidate that model.
Existing engine-managed import parameters and explicit-resource options are
retained when rebuilding; the tracker does not reset them to the default choices.
Changed PNG or audio content is reimported by the engine before the model is
saved, even when no filesystem notification arrives. Already loaded model
resources are refreshed in place after a successful save.

Checks run after startup, filesystem changes, resource reimports, application
focus, explicit validation, and a two-second pause between completed polling
cycles. Dependency reads advance one file at a time with at most 1 MiB hashed
per editor frame, 64 MiB per file and 512 MiB per model. Manifest parsing retains
newly declared missing paths so creating a missing file can recover a failed
import. An unchanged failure is not retried on every poll. Scanning the resource
index, loading resources and performing an actual model/texture/audio import
still run on the main thread; these operations are not claimed to be asynchronous.

The index is reconstructed from saved imported resources and existing engine
import metadata. Deleting `.godot` does not remove the saved `.res` source link.
For an engine-managed model with existing Cubism `.import` metadata, a missing
generated resource is rebuilt through EditorFileSystem before it is loaded.
This does not fix fresh compound-suffix discovery in stock Redot. The tracker
does not load an unselected raw manifest merely to discover it.

Renaming or removing a source produces a diagnostic. Restoring it allows another
attempt. Raw paths in Cubism JSON are not rewritten when files move. Removing an
imported resource, replacing it with another resource type, or selecting another
native importer stops tracking that output. A failed first GUI import with no
saved output is remembered for the current editor session; after restarting,
repeat the import action. Resources created directly through the runtime factory,
or by importer format 1 without an import fingerprint, must be explicitly imported
once to opt into tracking.

Run the integration checks with the pinned editor, licensed Haru fixture and
matching native library/template:

```sh
python tools/run_importer_tests.py --model /path/to/Haru.model3.json \
  --library /path/to/native-library --template /path/to/matching-template \
  --dependencies --graphics gl_compatibility --output /persistent/results
```

The dependency suite uses an actual graphics backend for live texture pixels.
Pinned Redot's dummy renderer discards texture replacements, so headless pixel
readback cannot qualify that behavior. Restart and template checks remain
headless. A current editor index is not an export guarantee: checked/selective
export and full import-option support are still separate unfinished work.
