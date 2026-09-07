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

- [Implementation plan](redot_live2d_cubism_importer_codex_plan.md)
- [Preflight findings, sources and remaining gates](docs/gamedev/preflight-report.md)
- Local source, decision and risk index: `docs/gamedev/source-of-truth.xlsx`
  (excluded from the public source branch).

The first milestone preserves the upstream API. Importer, export workflow and
gameplay additions follow the plan's dependency graph. Run the current public
checks with `python tools/run_tests.py --suite public`. Read [dependencies](DEPENDENCIES.md)
and [licensing](docs/licensing.md) before a native build. The original GDCubism
notices and documentation remain in the `.adoc` files.
