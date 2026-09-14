# Linux x86_64 source build

Use Redot 26.2 single precision, the pinned Redot bindings and Cubism Native SDK
5-r.5. The SDK is obtained separately after accepting its agreements. Linux
debug/release builds and real model/export tests have passed; a final release
still requires the full qualification gates in [desktop testing](../desktop-testing.md).

The complete environment setup and sequential debug/release commands are in
[Setup and first character](../quick-start.md#build-the-native-addon-on-linux).
Run them from the source checkout. Install the pinned SCons version in a
project-local virtual environment, initialize the `godot-cpp` submodule, set
`REDOT_BIN`, `CUBISM_SDK_ROOT` and `REDOT_CPP_ROOT`, then generate the API using
`tools/verify_dependencies.py`. Require its `PASS` before building.

Pass that generated API as `custom_api_file` and use
`build_profile=tools/native_build_profile.json` for both variants. Build them
sequentially when sharing a binding checkout. The ordinary libraries are written
to `demo/addons/gd_cubism/bin`; copy the entire addon folder into the game.

If the checkout is on a share that rejects compiler metadata or executable files,
set `CUBISM_BUILD_DIR` to a persistent local directory. Keep compiler outputs and
the binding checkout on a suitable local filesystem. Preserve private test
reports before reclaiming build space. See [dependency details](../../DEPENDENCIES.md)
for exact hashes and [sanitizers](../sanitizers.md) for the separate instrumented
build; sanitizer success does not replace graphical testing.
