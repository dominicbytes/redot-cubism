# Linux x86_64 source build

Use Redot 26.2 single precision, the pinned Redot bindings and Cubism Native SDK
5-r.5. The SDK is obtained separately after accepting its agreements. Linux
debug/release builds and real model/export tests have passed; a final release
still requires the full qualification gates in [desktop testing](../desktop-testing.md).

A fresh build at `234bb2920eee0f2bd247f5954f8ef96ce6cf2f9a` used
GCC/G++ 12.2.0, GNU ld 2.40, Python 3.14.7 and SCons 4.11.1. Both variants
passed strict headless load/identity and bounded editor-import checks. This is
a separate environment from the historical GCC 16.2.1/ld 2.47 record in
`DEPENDENCIES.json`; its smoke checks do not repeat the earlier full graphical
qualification. See [current status](../current-status.md) for the evidence boundaries.

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

## Build the retained C# demo

Use the official **Redot 26.2 Mono** editor and a .NET 8 SDK. The demo project
targets `Redot.NET.Sdk/26.2.0` and `net8.0`; `demo/project.godot` sets its
assembly name to `demo` so Redot loads the resulting `demo.dll`.

After building the native addon above, unpack the matching official Mono editor
and set `REDOT_MONO_ROOT` to the directory containing `GodotSharp`. Restore from
the Redot packages shipped with that editor. Put `NuGet.Config` beside the demo
project so the MSBuild SDK resolver finds the package before restore:

```sh
export REDOT_MONO_ROOT=/path/to/redot-26.2-linux-mono
cat > demo/NuGet.Config <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration><packageSources>
  <clear />
  <add key="redot-26.2.0" value="$REDOT_MONO_ROOT/GodotSharp/Tools/nupkgs" />
</packageSources></configuration>
EOF
cd demo
dotnet restore demo.csproj --configfile NuGet.Config -p:Configuration=Debug
dotnet build demo.csproj --configuration Debug --no-restore
```

Open `demo/project.godot` with that Mono editor. The project's main scene uses
GDScript; to run a retained C# example, open its scene under
`demo/addons/gd_cubism/example`, replace the root node's attached `.gd` script
with the matching `.cs` script, and run that scene. The ordinary Redot editor
cannot load the managed assembly. A successful build only verifies compilation;
the audio effect example also needs a `Voice` bus with a spectrum analyzer and
a mouth parameter matching its exported `param_mouth_name`.
