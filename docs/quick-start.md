# Setup and first character

Use a checkout containing this guide and the pinned Redot **26.2 single-precision**
editor. This is a development port, not a qualified release. Linux x86_64 has
runtime evidence; Windows x86_64 qualification is pending. Other architectures,
Godot binaries and later SDK versions are not covered by these instructions.

## Build the native addon on Linux

You need Git, a C++17 toolchain, Python 3.11+ with `venv`/`pip`, and the separately
obtained Cubism Native SDK **5-r.5**. Read [dependencies](../DEPENDENCIES.md) and
[licensing](licensing.md). Run these commands from the port checkout; replace the
two `/absolute/path/...` values with your installed editor and extracted SDK:

```sh
git submodule update --init godot-cpp
python3 -m venv .local-build/tools
.local-build/tools/bin/python -m pip install scons==4.11.1
export REDOT_BIN=/absolute/path/to/redot
export CUBISM_SDK_ROOT=/absolute/path/to/CubismSdkForNative-5-r.5
export REDOT_CPP_ROOT="$PWD/godot-cpp"
.local-build/tools/bin/python tools/verify_dependencies.py --output .local-build/identity
.local-build/tools/bin/python -m SCons -j2 platform=linux arch=x86_64 \
  target=template_debug precision=single \
  custom_api_file="$PWD/.local-build/identity/extension_api.json" \
  build_profile=tools/native_build_profile.json
.local-build/tools/bin/python -m SCons -j2 platform=linux arch=x86_64 \
  target=template_release precision=single \
  custom_api_file="$PWD/.local-build/identity/extension_api.json" \
  build_profile=tools/native_build_profile.json
```

Run the two builds sequentially because they share generated bindings. The
verifier must report `PASS`; the build rejects mismatched binding/API/SDK inputs.
On a shared filesystem that cannot handle build metadata, set `CUBISM_BUILD_DIR`
to a persistent directory on the machine's local filesystem before building.
The binding checkout also needs a filesystem suitable for compiler outputs.

The resulting libraries are in `demo/addons/gd_cubism/bin`:
`libgd_cubism.linux.debug.x86_64.so` and
`libgd_cubism.linux.release.x86_64.so`. Both variants are needed for editor/debug
use and release exports. Windows requires its own native build and DLLs; see
[the VS 2022 input requirements](../DEPENDENCIES.md).

## Install and import

1. Create or open a Redot project using **GL Compatibility** for this tested
   path. Copy the entire `demo/addons/gd_cubism` folder into its `addons` folder,
   including `bin`, `editor`, `res`, `examples` and `gd_cubism.gdextension`.
   Preserve the folder name: resources use `res://addons/gd_cubism/...` paths.
2. Open or restart the editor. The native extension registers its editor tools
   automatically; there is no `plugin.cfg` checkbox to enable. If the Cubism
   classes/tools are absent, inspect the editor output for a missing library,
   wrong architecture or version mismatch before importing a model.
3. Copy your licensed model folder into the game project, preserving the
   manifest's relative paths to its MOC, textures, motions and other files.
   Let Redot finish importing PNG/audio assets.
4. Choose **Project → Tools → Import Cubism Model**, select the `.model3.json`,
   and save a `.res` such as `res://characters/hero.res`. Stock Redot 26.2 does
   not discover `*.model3.json` automatically on a fresh scan. Use this explicit
   action; ordinary JSON files should keep their normal importer behavior.
5. Inspect the resulting `CubismModelResource`. Review warnings and note its
   motion IDs (`Group/index`) and expression IDs. Import options, source refresh
   and recovery are described in [editor import](editor-import.md).

## Run a character with or without voice

Open `res://addons/gd_cubism/examples/character_workflows/visual_novel.tscn`.
Select its root and expand **Character** in the Inspector. Assign the imported
resource to **Model**, choose **Idle Motion**, **Talk Motion** and **Talk
Expression** from that resource's IDs, then run the scene with F6. **Next line**
plays the cue. Assign an `AudioStream` to **Voice** for recorded dialogue, or
leave it empty for motion without audio. **Pause**, **Hide**, **Show**, **Save**
and **Restore** exercise the controller's presentation and stable checkpoints.

Live2D motions are authored/exported in Cubism Editor and played by this addon.
The addon does not record a new Live2D animation. Lip sync uses an audio envelope;
it is not phoneme recognition, and authored mouth curves have priority by default.
See the [example setup](../demo/addons/gd_cubism/examples/character_workflows/README.md)
for RPG movement/interaction and [dialogue integration](dialogue-integration.md)
for per-line audio, motion-only cues and completion handling in your own game.

## Export

Install the export templates matching the pinned editor, configure an existing
Linux Desktop preset and its scene/resource selection, then use **Project →
Tools → Validate and Export Cubism**. Keep the full addon and imported resource
references in the project. The checked export validates dependencies and tests
the staged package before replacing the destination. Do not add broad JSON/MOC
wildcards as a workaround for missing dependencies. Dynamically selected models
must be retained through exported resource references or preset selection.

Follow [checked exports](export-validation.md) for exact preset, output and CLI
requirements. Distribution still needs the applicable notices and permissions
in [licensing](licensing.md). A successful local example or package is not proof
of Windows support or completed release qualification.
