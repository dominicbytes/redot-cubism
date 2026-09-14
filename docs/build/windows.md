# Windows x86_64 source build

Windows is a required desktop target, but native Windows execution has not yet
been qualified. These commands reflect the pinned build configuration and CI
dispatch; they are not a claim of a passing Windows build or export.

Use a VS 2022/MSVC 14.3 x64 Native Tools environment, Python with `venv`, the
Redot 26.2 single-precision editor and matching templates, and the separately
obtained Cubism Native SDK 5-r.5. Core libraries must come from its `143` toolset
directory. Read [dependencies](../../DEPENDENCIES.md) and [licensing](../licensing.md).

From PowerShell with the VS compiler environment initialized, run from the port
checkout and replace the editor/SDK paths:

```powershell
git submodule update --init godot-cpp
python -m venv .local-build/tools
& ./.local-build/tools/Scripts/python.exe -m pip install scons==4.11.1
$env:REDOT_BIN = 'C:/tools/redot/redot.exe'
$env:CUBISM_SDK_ROOT = 'C:/SDK/CubismSdkForNative-5-r.5'
$env:REDOT_CPP_ROOT = (Resolve-Path './godot-cpp').Path
$env:PYTHONUTF8 = '1'
& ./.local-build/tools/Scripts/python.exe tools/verify_dependencies.py --output .local-build/identity
& ./.local-build/tools/Scripts/python.exe -m SCons -j2 platform=windows arch=x86_64 target=template_debug precision=single use_static_cpp=yes debug_crt=no custom_api_file=.local-build/identity/extension_api.json build_profile=tools/native_build_profile.json
& ./.local-build/tools/Scripts/python.exe -m SCons -j2 platform=windows arch=x86_64 target=template_release precision=single use_static_cpp=yes debug_crt=no custom_api_file=.local-build/identity/extension_api.json build_profile=tools/native_build_profile.json
```

Stop if dependency verification fails. Run the builds sequentially. The expected
outputs are `libgd_cubism.windows.debug.x86_64.dll` and
`libgd_cubism.windows.release.x86_64.dll` under `demo/addons/gd_cubism/bin`.
Do not substitute a Linux binary or rename a debug DLL to stand in for release.

Before distributing a Windows build, run both variants through the native editor,
graphics and checked-export tests described in [desktop testing](../desktop-testing.md).
The checked exporter must launch the packaged executable on Windows and validate
its actual native build identity. Cross-compilation is insufficient evidence.
