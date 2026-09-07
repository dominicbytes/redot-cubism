# PR 2A: Linux SDK-free binding/import/export checkpoint

Status: FOCUSED_TESTED and exported SDK-free harness tested on Linux x86_64.
The Cubism plugin itself is not complete. Windows PR 2A, matched Core/Framework
builds, model playback/rendering, production import/export and controller stages
remain open. This harness contains no Core implementation or model-runtime stub.

## Source and commands

The prior bootstrap commit is `9f33623e2d631c047fa0c27f9ce83bfe0a8667c5`.
Source pins are unchanged from `DEPENDENCIES.json`. The separate binding checkout
uses redot-cpp `598ec78e86b2c240a023f6de13daba70f7de8610`; the original production
submodule/build script remain for PR 2B. Framework source was retrieved at
`145155d2c5bdd8d23475cef9cc3ab46d3220190c`; no proprietary SDK was downloaded.

Commands run from the repository root, with actual local paths supplied through
the documented variables:

```text
REDOT_BIN=<editor> python tools/verify_dependencies.py --output <identity>
REDOT_CPP_ROOT=<pinned checkout> CUBISM_ABI_OUTPUT=<build> python -m SCons -f tests/abi/SConstruct platform=linux arch=x86_64 target=template_debug precision=single custom_api_file=<identity>/extension_api.json -j4
REDOT_CPP_ROOT=<pinned checkout> CUBISM_ABI_OUTPUT=<build> python -m SCons -f tests/abi/SConstruct platform=linux arch=x86_64 target=template_release precision=single custom_api_file=<identity>/extension_api.json -j4
REDOT_BIN=<editor> CUBISM_ABI_LIBRARY=<debug library> python tools/run_abi_tests.py --output <debug results> --template <debug template> --export-mode debug
REDOT_BIN=<editor> CUBISM_ABI_LIBRARY=<release library> python tools/run_abi_tests.py --output <release results> --template <release template> --export-mode release
clang-format --dry-run --Werror tests/abi/probe.cpp
python tools/run_tests.py --suite public
python tools/check_restricted_files.py --history HEAD
```

## Results

| Check | Debug | Release |
|---|---|---|
| Build native Node2D/Resource probe | PASS | PASS |
| Fresh editor import and native editor-plugin enter/exit | PASS | PASS |
| Native resource Unicode save/load; internal processing despite script overrides | PASS | PASS |
| Scene pause/resume and detach/reentry without a second ready | PASS | PASS |
| Multipart suffix vs competing JSON importer | PASS | PASS |
| Cached resource and UID after editor restart | PASS | PASS |
| Missing synthetic raw input rejected by checked export prototype | PASS | PASS |
| Export plugin injects raw fixture | PASS | PASS |
| Matching export template launches with source project moved away | PASS | PASS |
| Editor class absent from actual export-template ClassDB | PASS | PASS |

All engine processes have a 60-second wall-clock limit. No expected success run
contains errors/warnings or lacks its terminal marker. The test deliberately
deletes/restores its own synthetic raw fixture for the negative export case.
That prototype is not the production reachable-model validator, and does not
prove stock Export-menu cancellation.

The first restricted run failed because the sandbox denied the editor's local
diagnostic sockets; the complete successful runs used isolated profiles with
those sockets allowed. The minimal binding profile initially omitted OS, which
the pinned diagnostics source includes; adding OS fixed compilation. SCons
metadata moved to the build output to avoid the host 9p rename limitation.
Editor binaries register editor-level classes even in game mode; the no-editor
class assertion correctly applies to actual export templates.

## Artifact identity

Editor version: `26.2.stable.official.4f5b14aba`. API and interface hashes are in
[PR 0/1](pr-01-report.md). No dependency pin was upgraded.

| Artifact | SHA-256 |
|---|---|
| SDK-free debug extension | `706354b7f04cad02b5050ce01dc64006cc84cfc830883a672cb0ee8c0927d5a5` |
| SDK-free release extension | `82c882fde1cd387ab4da9f9676229c70f6d967e14490d8d86ce14c6a7a907526` |
| Debug export template/executable | `b94effe58cb906290ed2e2ba5e7cc106391ae4440560e53515614479f826a4a9` |
| Release export template/executable | `93c364a8e89905c710e21bc87d521a540ee6a2b67004b78cb2067403481507fc` |
| Debug harness PCK | `541cfed6139814c29bc22bf1d10a7143360cd7c93f1724d780e8cfaade5c7d7a` |
| Release harness PCK | `52fb3315d106f4c2f2d2de530d33a6379b13b4dde88fa6537fbba988592e0bea` |

The matching templates were extracted from the existing local Redot 26.2 template
archive, not downloaded. The harness exports and logs remain local under ignored
`.local-build` evidence. They are test artifacts, not distributable Cubism builds.

## Remaining gates

- Authenticated browser/gh access for the authorized dominicbytes/redot-cubism fork.
- Official SDK 5-r.5 download (authorized; download-page license consent pending),
  Core/library/archive identity and permitted model.
- Windows compiler, editor and actual exported runtime tests.
- Every subsequent native, renderer, importer, controller, audio, sanitizer,
  visual/reference, private CI and release requirement from the plan.
- Public CI is defined but has not executed remotely.

No source-only PASS is counted as a licensed-desktop PASS. No Core/model bytes
entered Git. Source publication is authorized, but binary publication and model
redistribution are not asserted as approved.
