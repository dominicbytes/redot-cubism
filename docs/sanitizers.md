# Linux sanitizer builds

`SConstruct` accepts `sanitize=none` (default), `address`, `undefined`, or
`address,undefined`. Instrumented builds are Linux-only and write their library
under `CUBISM_BUILD_DIR/bin`, separate from the ordinary addon installation.
Use a separate build directory per sanitizer configuration. Keep the pinned
SDK, bindings and generated API inputs described by the build setup.

```sh
CUBISM_SDK_ROOT=/private/sdk REDOT_CPP_ROOT=/private/redot-cpp \
CUBISM_BUILD_DIR=/private/build-asan-ubsan scons \
  platform=linux target=template_debug arch=x86_64 \
  sanitize=address,undefined \
  custom_api_file=/private/identity/extension_api.json \
  build_profile=tools/native_build_profile.json -j1
```

Both the addon source and the public Cubism Framework source are instrumented.
The proprietary Core library and prebuilt binding archive remain unchanged;
inline binding code compiled into the addon is covered. UBSan flags include
`-fno-sanitize-recover=undefined`, so detected undefined behavior exits with a
failure even without an environment override. Sanitized builds retain diagnostic
symbols, frame pointers and shared C++ runtime linkage.

Use the matched ASan Redot test engine with an ASan or combined library:

```sh
REDOT_BIN=/private/redot python tools/run_native_tests.py \
  --model /private/fixture/character.model3.json --expression Smile \
  --library /private/ordinary/libgd_cubism.linux.debug.x86_64.so \
  --sanitizer-runtime /private/redot-asan \
  --sanitizer-library /private/build-asan-ubsan/bin/libgd_cubism.linux.debug.x86_64.so \
  --output /private/sanitizer-results
```

The ordinary library is used for the initial non-sanitized tests. The sanitizer
stage switches libraries, checks `CubismBuildInfo.get_versions().sanitizer` from
the loaded addon, then runs descriptor shutdown, 250 lifecycle cycles, motion
handles and loading/removal tests. It forces leak detection and fatal ASan/UBSan
diagnostics; process failure, missing success markers, or sanitizer messages
fail the run. Reports record addon/Framework sanitizer modes separately from the
ASan engine. A non-sanitized addon fails the identity check. The existing engine
version check requires the pinned `.cubism_asan.` test engine build.

A standalone `sanitize=undefined` addon can be exercised with the matched normal
Redot engine and the ordinary runtime test scripts. That does not instrument the
engine itself and does not replace the ASan lifecycle run. The combined build
likewise adds UBSan to the addon/Framework; an ASan-only engine does not acquire
UBSan coverage by loading it.

The existing minimal ASan engine uses `--headless --rendering-driver dummy` and
lacks FreeType and real graphics backends. Its core tests do not qualify UI,
editor previews, GPU behavior, or rendered output. Run the regular graphical
runtime/export suites separately.

`tests/python/test_sanitizers.py` validates supported modes/targets and compiles
a small SDK-free UBSan probe. The valid path must exit successfully; deliberately
triggered signed integer overflow must exit unsuccessfully before its completion
marker. This verifies fatal sanitizer behavior, not Cubism runtime correctness.

## Pinned Framework hash correction

The first combined run stopped during Framework initialization in
`csmString::CalcHashcode`: its signed `hash * 31` overflowed. The build now
replaces only that function in a generated private copy of `csmString.cpp`,
using `src/private/cubism_string_hash.hpp`. Unsigned modulo-2^32 arithmetic
preserves the reverse polynomial, native-char signedness, and the reserved
`-1`/empty-string behavior. Conversion back to a signed result is defined even
at the minimum signed integer. The fix applies to ordinary builds as well as
sanitized builds; no UBSan checks are suppressed.

`tools/framework_patch.py` requires the reviewed original file SHA-256 before
producing the build copy. The full pinned Framework source check still runs,
and the downloaded SDK files are never edited. A dependency update must review
this patch again. `CubismBuildInfo.get_versions().framework_patches` records the
patch identifier plus hashes of the generated implementation and helper.
Generated SDK source remains private and is not included in source packages.

The public UBSan hash test compares ASCII, Unicode, arbitrary bytes, integer
boundaries, and reserved values against an independent Python modular-arithmetic
oracle. Runtime verification must also pass with the real licensed SDK; the
oracle alone does not qualify the port.
