# Exporting a Cubism game

Install templates matching the pinned Redot editor and build both native addon
variants for the target OS. Save scenes and imported resources before exporting.
Configure an existing Linux or Windows Desktop preset with the intended scene
or resource selection. Windows exported-game execution remains unqualified.

Choose **Project → Tools → Validate and Export Cubism**, select the preset and
debug/release mode, then choose a directory for the complete build. The checked
pipeline validates dependencies, builds in a fresh staging directory, inspects
the package and launches a smoke check before promoting the result. A failed
attempt preserves an existing managed output. Python is required for this helper.

Keep imported resource references in scenes or exported resource catalogs.
Runtime-generated strings alone do not declare dependencies. Normal resource
edges retain imported textures, audio and the native extension; the export plugin
adds enabled declared raw model inputs and runtime shaders. Do not add broad
JSON/MOC wildcard filters to compensate for missing references. Prepare and save
[legacy scenes](../migration/from-gd-cubism.md) before selective export.

The [export validation guide](../export-validation.md) documents supported preset
selection, standalone PCK requirements, CLI commands, diagnostics, build identity
checks and failure recovery. Validate the package on its native target and review
[licensing](../licensing.md) before distribution. A successful package smoke does
not establish renderer parity, Windows support or full release qualification.
