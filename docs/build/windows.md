# Windows x86_64 source build

Windows x86_64 debug/release builds and scoped native, graphical, editor and
checked-export tests have passed with VS 2022 (MSVC 19.44.35221, VCTools
14.44.35207), Python 3.14.7 and SCons 4.11.1. The image-comparison tests used
Pillow 12.3.0. Full release qualification remains incomplete; see
[current status](../current-status.md) for exact tested revisions and open gates.

Use a VS 2022/MSVC 14.3 x64 Native Tools environment, Python with `venv`, the
Redot 26.2 single-precision editor and matching templates, and the separately
obtained Cubism Native SDK 5-r.5. Core libraries must come from its `143` toolset
directory. Read [dependencies](../../DEPENDENCIES.md) and [licensing](../licensing.md).
The recommended extracted SDK root is
`.local-build/sdk/CubismSdkForNative-5-r.5`; it must contain
`Core/include/Live2DCubismCore.h`, `Core/lib/windows/x86_64/143` and
`Framework/src`. Do not point `CUBISM_SDK_ROOT` at the SDK ZIP.

First [clone the Redot development branch](../quick-start.md#get-the-source).
From PowerShell, run from that checkout and replace the editor path. If you
extracted the SDK elsewhere, also replace the `CUBISM_SDK_ROOT` value.
Start the VS 2022 x64 shell in that PowerShell process, even if newer Visual
Studio versions are installed:

```powershell
& 'C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/Common7/Tools/Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64
git submodule update --init godot-cpp
python -m venv .local-build/tools
& ./.local-build/tools/Scripts/python.exe -m pip install scons==4.11.1
$env:REDOT_BIN = 'C:/tools/redot/redot.exe'
$env:CUBISM_SDK_ROOT = (Resolve-Path './.local-build/sdk/CubismSdkForNative-5-r.5').Path
$env:REDOT_CPP_ROOT = (Resolve-Path './godot-cpp').Path
$env:PYTHONUTF8 = '1'
& ./.local-build/tools/Scripts/python.exe tools/verify_dependencies.py --output .local-build/identity
& ./.local-build/tools/Scripts/python.exe -m SCons -j2 platform=windows arch=x86_64 target=template_debug precision=single use_static_cpp=yes debug_crt=no custom_api_file=.local-build/identity/extension_api.json build_profile=tools/native_build_profile.json
& ./.local-build/tools/Scripts/python.exe -m SCons -j2 platform=windows arch=x86_64 target=template_release precision=single use_static_cpp=yes debug_crt=no custom_api_file=.local-build/identity/extension_api.json build_profile=tools/native_build_profile.json
```

Stop if dependency verification fails. Run the builds sequentially. The expected
outputs are `libgd_cubism.windows.debug.x86_64.dll` and
`libgd_cubism.windows.release.x86_64.dll` under `demo/addons/gd_cubism/bin`.
The build creates a v143-selecting copy of redot-cpp's Windows tool under
`CUBISM_BUILD_DIR/tools` (default `.local-build/native/tools`). Confirm the SCons
output says `MSVC_VERSION = 14.3`; the pinned redot-cpp checkout stays clean.
For long-path failures, set `CUBISM_BUILD_DIR` to a short writable local path.
Keep `TEMP` and `TMP` on a writable path without spaces for this PowerShell
session; the pinned MSVC output wrapper uses that path in shell redirection.
Do not substitute a Linux binary or rename a debug DLL to stand in for release.

After building both DLLs, follow [Install and import](../quick-start.md#install-and-import)
to copy the addon into a GL Compatibility project and import your first model.

Before distributing a Windows build, run both variants through the native editor,
graphics and checked-export tests described in [desktop testing](../desktop-testing.md).
The checked exporter must launch the packaged executable on Windows and validate
its actual native build identity. Cross-compilation is insufficient evidence.
