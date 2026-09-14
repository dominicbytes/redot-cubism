# Redot Cubism documentation

These guides describe the Redot 26.2 port in this checkout. The port is still in
development: Linux has native, export and graphics evidence; Windows and the
complete release gates remain unqualified. SDK/model assets are supplied separately.

Start with [setup and first character](quick-start.md). Use the
[dependency pins and build requirements](../DEPENDENCIES.md) for the native build.

| Task | Guide |
|---|---|
| Import a model and choose options | [Editor import](editor-import.md), [texture import](texture-import.md) |
| Inspect the imported model | [Model Inspector](model-inspector.md), [resource format](model-resource.md), [motion/expression descriptors](descriptors.md) |
| Display and animate a character | [Preferred runtime API](preferred-runtime.md) |
| Play dialogue with optional recorded voice | [Dialogue integration](dialogue-integration.md), [VN/RPG examples](../demo/addons/gd_cubism/examples/character_workflows/README.md) |
| Migrate existing GDCubism scenes | [Legacy compatibility](legacy-compatibility.md), [resource loading](resource-runtime.md) |
| Refresh changed assets | [Dependency tracking](dependency-tracking.md) |
| Export a game | [Checked exports](export-validation.md), [licensing](licensing.md) |
| Diagnose rendering and ownership | [Debug overlays](debug-overlay.md), [statistics](debug-statistics.md) |
| Reproduce qualification checks | [Desktop suite](desktop-testing.md), [editor suite](editor-testing.md), [SDK motion comparison](sdk-motion-testing.md), [visual comparison](visual-testing.md), [benchmarks](benchmarks.md), [sanitizers](sanitizers.md) |

The Markdown files are the maintained port documentation and render directly in
GitHub or a Markdown viewer; no website build is required. The original
[AsciiDoc documentation](../docs-src/README.md) and its Antora playbook are retained
as an upstream archive. Their API, shader uniforms, SDK versions, platform claims
and build commands are historical, not instructions for this port.
