# Redot Cubism

Unofficial GDCubism port for Redot Engine LTS 26.2 and Cubism Native SDK 5-r.5.
Implementation is in progress. Linux debug/release native model loading, motion,
expression and private exported-template smoke tests pass. Compatibility rendering
has been exercised on this Linux host. Windows and full renderer parity remain unqualified.
The SDK and test models are not bundled.

Source destination: [dominicbytes/redot_cubism](https://github.com/dominicbytes/redot_cubism).
See [publication status](docs/gamedev/publication-status.md) for the current upload checkpoint.

Current evidence: [bootstrap](docs/gamedev/pr-01-report.md) and
[Linux compatibility spike](docs/gamedev/pr-02a-report.md), and
[real SDK port tests](docs/gamedev/pr-02b-native-report.md).

- [Setup and first character](docs/quick-start.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Documentation index](docs/README.md)
- [Implementation plan](redot_live2d_cubism_importer_codex_plan.md)
- [Provisional editor model import](docs/editor-import.md)
- [Editor workflow regression](docs/editor-testing.md)
- [Desktop functional test sequence](docs/desktop-testing.md)
- [SDK motion-state comparison](docs/sdk-motion-testing.md)
- [Imported resource runtime loading](docs/resource-runtime.md)
- [VN and RPG character examples](demo/addons/gd_cubism/examples/character_workflows/README.md)
- [Dialogue manager integration](docs/dialogue-integration.md)
- [Preflight findings, sources and remaining gates](docs/gamedev/preflight-report.md)
- Local source, decision and risk index: `docs/gamedev/source-of-truth.xlsx`
  (excluded from the public source branch).

The port retains the legacy API alongside the preferred `CubismModel2D` resource
workflow and `CubismCharacterController` for motion and recorded-audio cues. Run the current public
checks with `python tools/run_tests.py --suite public`. Read [dependencies](DEPENDENCIES.md)
and [licensing](docs/licensing.md) before a native build. The original GDCubism
notices and [archived documentation](docs-src/README.md) remain in the `.adoc` files.

The tested Linux dependency set uses Redot `26.2.stable.official.4f5b14aba`,
Redot bindings `598ec78e86b2c240a023f6de13daba70f7de8610`, and Cubism Native SDK
`5-r.5` with Core `6.0.1` and Framework
`145155d2c5bdd8d23475cef9cc3ab46d3220190c`. Build tooling and content hashes are
pinned in [DEPENDENCIES.json](DEPENDENCIES.json). See the
[Linux build](docs/build/linux.md), pending [Windows build](docs/build/windows.md)
and [Redot compatibility](docs/compatibility/redot.md) guides for their scope.
