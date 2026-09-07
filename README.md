# Redot Cubism

Unofficial GDCubism port for Redot Engine LTS 26.2 and Cubism Native SDK 5-r.5.
Implementation is in progress. The repository bootstrap and source checks are
available; native Cubism playback is not yet qualified on Windows or Linux.
The SDK and test models are not bundled.

- [Implementation plan](redot_live2d_cubism_importer_codex_plan.md)
- [Preflight findings, sources and remaining gates](docs/gamedev/preflight-report.md)
- [Source, decision and risk index](docs/gamedev/source-of-truth.xlsx)

The first milestone preserves the upstream API. Importer, export workflow and
gameplay additions follow the plan's dependency graph. Run the current public
checks with `python tools/run_tests.py --suite public`. Read [dependencies](DEPENDENCIES.md)
and [licensing](docs/licensing.md) before a native build. The original GDCubism
notices and documentation remain in the `.adoc` files.
