# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 MizunagiKB <mizukb@live.jp>
import sys
import os
import json
import subprocess
from glob import glob
from pathlib import Path


root = Path(Dir("#").abspath)
sys.path.insert(0, str(root / "tools"))
from build_inputs import binding_root, core_library, sdk_roots, windows_core_library, sanitizer_flags, sha256
from framework_patch import patch_csm_string, PATCH_ID

pins = json.loads((root / "DEPENDENCIES.json").read_text())
options = dict(os.environ)
options.update(ARGUMENTS)
try:
    core, framework = sdk_roots(options, pins)
    cpp = binding_root(root, options, pins, ARGUMENTS.get("custom_api_file"), ARGUMENTS.get("precision", "single"))
except (OSError, ValueError) as exc:
    print(f"Redot Cubism build input error: {exc}")
    Exit(1)

build_dir = Path(options.get("CUBISM_BUILD_DIR", root / ".local-build/native")).resolve()
build_dir.mkdir(parents=True, exist_ok=True)
SConsignFile(str(build_dir / ".sconsign.dblite"))
env = SConscript(str(cpp / "SConstruct"))
# Some shared filesystems report a constant or invalid mtime. Do not reuse a
# source signature solely because its timestamp is unchanged.
SetOption("max_drift", -1)
env.Decider("content")
# Addon-only flags must not change targets already declared by redot-cpp.
env = env.Clone()
sanitizer = ARGUMENTS.get("sanitize", "none")
try:
    sanitizer_compile_flags, sanitizer_link_flags = sanitizer_flags(sanitizer, env["platform"])
except ValueError as exc:
    print(f"Redot Cubism build input error: {exc}")
    Exit(1)
if sanitizer != "none":
    # Keep diagnostic symbols and use the same shared C++ runtime as the sanitizers.
    env["LINKFLAGS"] = [flag for flag in env["LINKFLAGS"] if flag not in ("-s", "-static-libgcc", "-static-libstdc++")]
    env.Append(CCFLAGS=sanitizer_compile_flags)
    env.Append(LINKFLAGS=sanitizer_link_flags)
if ARGUMENTS.get("build_profile"):
    # The pinned binding generator omits the profile from its input dependencies.
    env.Depends(str(cpp / "gen/include/godot_cpp/core/ext_wrappers.gen.inc"),
        str(Path(ARGUMENTS["build_profile"]).resolve()))
generated_dir = build_dir / "gen"
generated_dir.mkdir(parents=True, exist_ok=True)
# Patch only a generated build copy. The installed SDK and its input pin stay intact.
original_string = framework / "src/Type/csmString.cpp"
patched_string = generated_dir / "framework/csmString.cpp"
try:
    patched_bytes = patch_csm_string(original_string.read_bytes())
except ValueError as exc:
    print(f"Redot Cubism build input error: {exc}")
    Exit(1)
patched_string.parent.mkdir(parents=True, exist_ok=True)
if not patched_string.exists() or patched_string.read_bytes() != patched_bytes:
    patched_string.write_bytes(patched_bytes)
build_info = {
    "addon_version": pins["addon_version"],
    "addon_commit": subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
    "redot_version": pins["redot"]["version"],
    "redot_api_sha256": pins["redot"]["api_sha256"],
    "redot_cpp_commit": pins["redot_cpp"]["commit"],
    "framework_version": pins["cubism_framework"]["version"],
    "framework_commit": pins["cubism_framework"]["commit"],
    "sdk_version": pins["cubism_sdk"]["version"],
    "sdk_archive_sha256": pins["cubism_sdk"]["archive_sha256"],
    "core_version": pins["cubism_sdk"]["core_version"],
    "platform": env["platform"],
    "arch": env["arch"],
    "target": env["target"],
    "precision": env["precision"],
    "compiler": env.subst("$CXX"),
    "sanitizer": sanitizer,
    "framework_patches": {PATCH_ID: {"source_sha256": sha256(patched_string),
        "helper_sha256": sha256(root / "src/private/cubism_string_hash.hpp")}},
}
build_info["addon_dirty"] = bool(subprocess.check_output(
    ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=normal"], text=True).strip())
info_header = generated_dir / "cubism_build_info.gen.h"
header_text = "#define CUBISM_BUILD_INFO_JSON " + json.dumps(json.dumps(build_info, sort_keys=True)) + "\n"
core_major, core_minor, core_patch = map(int, pins["cubism_sdk"]["core_version"].split("."))
header_text += f"#define CUBISM_EXPECTED_CORE_VERSION {((core_major << 24) | (core_minor << 16) | core_patch)}\n"
if not info_header.exists() or info_header.read_text() != header_text:
    info_header.write_text(header_text)
env.Append(CPPPATH=[str(generated_dir)])
CUBISM_NATIVE_CORE_DIR = str(core)
CUBISM_NATIVE_FRAMEWORK_DIR = str(framework)
for name in ("CUBISM_MOTION_CUSTOMDATA", "COUNTERMEASURES_90017_90030"):
    if ARGUMENTS.get(name, "1") == "1":
        env.Append(CPPDEFINES={name: "1"})


# Add source files.
env.Append(CPPPATH=["src/"])
env.Append(CPPPATH=[os.path.join(CUBISM_NATIVE_CORE_DIR, "include")])


print("                   platform = {:s}".format(env["platform"]))
print("                       arch = {:s}".format(env["arch"]))


if env["platform"] == "windows":
    print(
        "               MSVC_VERSION = {:s}".format(
            env.get("MSVC_VERSION", "(undefined)")
        )
    )
    try:
        o_cubism_lib = windows_core_library(core, env)
    except ValueError as exc:
        print(f"Redot Cubism build input error: {exc}")
        Exit(1)
    env.Append(LIBPATH=[str(o_cubism_lib.parent)])
    print("                       libs = {:s}".format(str(o_cubism_lib)))
    env.Append(LIBS=[o_cubism_lib.stem])

elif env["platform"] == "macos":
    o_cubism_lib = (
        Path(CUBISM_NATIVE_CORE_DIR)
        .joinpath("lib")
        .joinpath(env["platform"])
        .joinpath(env["arch"])
        .joinpath("libLive2DCubismCore.a")
    )
    if env["arch"] == "universal":
        if o_cubism_lib.is_file() is False:
            print("*** File not found, {:s} ***".format(str(o_cubism_lib)))
            print("*** Please refer to doc/BUILD.adoc or doc/BUILD.en.adoc")
            print("*** ex)")
            print("*** pushd {:s}/lib/macos".format(CUBISM_NATIVE_CORE_DIR))
            print("*** mkdir universal")
            print(
                "*** lipo -create arm64/{0:s} x86_64/{0:s} -output universal/{0:s}".format(
                    "libLive2DCubismCore.a"
                )
            )
            print("*** popd")
            sys.exit()
    print("                       libs = {:s}".format(str(o_cubism_lib)))
    env.Append(
        LIBPATH=[os.path.join(CUBISM_NATIVE_CORE_DIR, "lib", "macos", env["arch"])]
    )
    env.Append(LIBS=["Live2DCubismCore"])

elif env["platform"] == "ios":
    o_cubism_lib = (
        Path(CUBISM_NATIVE_CORE_DIR)
        .joinpath("lib")
        .joinpath(env["platform"])
        .joinpath("Release-iphoneos")
        .joinpath("libLive2DCubismCore.a")
    )
    print("                       libs = {:s}".format(str(o_cubism_lib)))
    env.Append(
        LIBPATH=[
            os.path.join(
                CUBISM_NATIVE_CORE_DIR, "lib", env["platform"], "Release-iphoneos"
            )
        ]
    )
    env.Append(LIBS=["Live2DCubismCore"])

elif env["platform"] == "linux":
    env.Append(LINKFLAGS=["-Wl,--no-undefined"])
    o_cubism_lib = (
        Path(CUBISM_NATIVE_CORE_DIR)
        .joinpath("lib")
        .joinpath(env["platform"])
        .joinpath(env["arch"])
        .joinpath("libLive2DCubismCore.a")
    )
    env.Append(
        LIBPATH=[
            os.path.join(
                CUBISM_NATIVE_CORE_DIR, "lib", "linux/{:s}".format(env["arch"])
            )
        ]
    )
    print("                       libs = {:s}".format(str(o_cubism_lib)))
    env.Append(LIBS=["Live2DCubismCore"])

elif env["platform"] == "android":
    dict_arch = {
        "arm64": "arm64-v8a",
        "arm32": "armeabi-v7a",
        "x86_32": "x86",
        "x86_64": "x86_64",
    }
    o_cubism_lib = (
        Path(CUBISM_NATIVE_CORE_DIR)
        .joinpath("lib")
        .joinpath(env["platform"])
        .joinpath(dict_arch[env["arch"]])
        .joinpath("libLive2DCubismCore.a")
    )

    env.Append(
        LIBPATH=[
            os.path.join(
                CUBISM_NATIVE_CORE_DIR, "lib", "android", dict_arch[env["arch"]]
            )
        ]
    )
    print("                       libs = {:s}".format(str(o_cubism_lib)))
    env.Append(LIBS=["Live2DCubismCore"])

else:
    print("!!! Unsupported platform !!!")
    sys.exit()

print("")

try:
    core_library(o_cubism_lib, core, pins)
except (OSError, ValueError) as exc:
    print(f"Redot Cubism build input error: {exc}")
    Exit(1)

sources = glob("src/*.cpp")
sources += glob("src/private/*.cpp")
sources += glob("src/loaders/*.cpp")
sources += glob("src/importers/*.cpp")

env.Append(CPPPATH=[os.path.join(CUBISM_NATIVE_FRAMEWORK_DIR, "src")])

sources_cubism = glob(os.path.join(CUBISM_NATIVE_FRAMEWORK_DIR, "src", "*.cpp"))

for dirname in (
    "Effect",
    "Id",
    "Math",
    "Model",
    "Motion",
    "Physics",
    "Rendering",
    "Type",
    "Utils",
):
    sources_cubism += glob(
        os.path.join(CUBISM_NATIVE_FRAMEWORK_DIR, "src", dirname, "*.cpp")
    )

sources += [str(patched_string) if Path(source).resolve() == original_string else source for source in sources_cubism]


#
if env["target"] in ["editor", "template_debug"]:
    try:
        doc_data = env.GodotCPPDocData(
            str(build_dir / "gen/doc_data.gen.cpp"), source=glob("doc_classes/*.xml")
        )
        sources += list(doc_data)
    except AttributeError:
        print("Not including class reference as we're targeting a pre-4.3 baseline.")


# Keep objects outside both pinned dependency trees.
objects = []
for source in sources:
    path = Path(str(source)).resolve()
    if path.is_relative_to(framework):
        key = Path("framework") / path.relative_to(framework)
    elif path.is_relative_to(build_dir):
        key = Path("generated") / path.relative_to(build_dir)
    else:
        key = Path("addon") / path.relative_to(root)
    objects += env.SharedObject(str(build_dir / "obj" / (str(key) + env["suffix"])), source)
sources = objects

(extension_path,) = glob("demo/addons/*/*.gdextension")

# Find the addon path (e.g. project/addons/example).
addon_path = Path(extension_path).parent
if sanitizer != "none":
    # Keep the instrumented test library out of the ordinary addon install.
    addon_path = build_dir

# Find the project name from the gdextension file (e.g. example).
project_name = Path(extension_path).stem

# TODO: Cache is disabled currently.
# scons_cache_path = os.environ.get("SCONS_CACHE")
# if scons_cache_path != None:
#     CacheDir(scons_cache_path)
#     print("Scons cache enabled... (path: '" + scons_cache_path + "')")

# Create the library target (e.g. libexample.linux.debug.x86_64.so).
debug_or_release = "release" if env["target"] == "template_release" else "debug"
if env["platform"] == "macos":
    library = env.SharedLibrary(
        "{0}/bin/lib{1}.{2}.{3}.framework/{1}.{2}.{3}".format(
            addon_path,
            project_name,
            env["platform"],
            debug_or_release,
        ),
        source=sources,
    )
else:
    library = env.SharedLibrary(
        "{}/bin/lib{}.{}.{}.{}{}".format(
            addon_path,
            project_name,
            env["platform"],
            debug_or_release,
            env["arch"],
            env["SHLIBSUFFIX"],
        ),
        source=sources,
    )

Default(library)
