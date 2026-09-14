# Redot Cubism documentation

These guides describe the Redot 26.2 port in this checkout. The port is still in
development: Linux has native, export and graphics evidence; Windows and the
complete release gates remain unqualified. SDK/model assets are supplied separately.

Start with [setup and first character](quick-start.md). Use the
[dependency pins and build requirements](../DEPENDENCIES.md) for the native build.

| Task | Guide |
|---|---|
| Build the addon | [Linux](build/linux.md), [Windows](build/windows.md), [macOS status](build/macos.md), [mobile status](build/mobile.md) |
| Import a model and choose options | [Importing models](usage/importing-models.md), [editor options](editor-import.md), [texture import](texture-import.md) |
| Inspect the imported model | [Model Inspector](model-inspector.md), [resource format](model-resource.md), [motion/expression descriptors](descriptors.md) |
| Display and animate a character | [CubismModel2D](usage/cubism-model-2d.md), [motions and expressions](usage/motions-and-expressions.md), [detailed runtime API](preferred-runtime.md) |
| Play dialogue with optional recorded voice | [Lip sync](usage/lip-sync.md), [dialogue integration](dialogue-integration.md), [VN example](usage/visual-novel-example.md), [RPG example](usage/rpg-example.md) |
| Migrate existing GDCubism scenes | [Migration](migration/from-gd-cubism.md), [legacy contracts](legacy-compatibility.md), [resource loading](resource-runtime.md) |
| Refresh changed assets | [Dependency tracking](dependency-tracking.md) |
| Export a game | [Export workflow](usage/exporting.md), [validation details](export-validation.md), [licensing](licensing.md) |
| Check compatibility or recover from errors | [Redot](compatibility/redot.md), [SDK matrix](compatibility/cubism_sdk_matrix.md), [troubleshooting](troubleshooting.md) |
| Diagnose rendering and ownership | [Debug overlays](debug-overlay.md), [statistics](debug-statistics.md) |
| Reproduce qualification checks | [Desktop suite](desktop-testing.md), [editor suite](editor-testing.md), [SDK motion comparison](sdk-motion-testing.md), [visual comparison](visual-testing.md), [benchmarks](benchmarks.md), [sanitizers](sanitizers.md) |

The Markdown files are the maintained port documentation and render directly in
GitHub or a Markdown viewer; no website build is required. The original
[AsciiDoc documentation](../docs-src/README.md) and its Antora playbook are retained
as an upstream archive. Their API, shader uniforms, SDK versions, platform claims
and build commands are historical, not instructions for this port.
