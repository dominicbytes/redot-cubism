# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Validate local inputs before scheduling a native build; never download them."""
import hashlib
import json
from pathlib import Path
import subprocess


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_file(path):
    if not path.is_file():
        raise ValueError(f"Required build input is missing: {path}")
    return path


def check_hash(path, expected, label):
    require_file(path)
    if not expected:
        raise ValueError(f"Record the verified {label} SHA-256 in DEPENDENCIES.json before building")
    if sha256(path) != expected:
        raise ValueError(f"{label} SHA-256 does not match DEPENDENCIES.json: {path}")


def source_hash(root):
    """Hash sorted relative filenames and contents, independent of host metadata."""
    digest = hashlib.sha256()
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix()):
        digest.update((path.relative_to(root).as_posix() + "\0" + sha256(path) + "\n").encode())
    return digest.hexdigest()


def sdk_roots(options, pins):
    value = options.get("CUBISM_SDK_ROOT")
    if not value:
        raise ValueError("Set CUBISM_SDK_ROOT to the locally provisioned Cubism Native SDK 5-r.5; automatic discovery is disabled")
    sdk = Path(value).expanduser().resolve()
    core = sdk / "Core"
    framework = Path(options.get("CUBISM_FRAMEWORK_ROOT") or sdk / "Framework").expanduser().resolve()
    require_file(core / "include/Live2DCubismCore.h")
    require_file(framework / "src/CubismFramework.cpp")
    require_file(framework / "src/Model/CubismModel.cpp")
    expected = pins["cubism_framework"].get("source_sha256")
    if not expected or source_hash(framework / "src") != expected:
        raise ValueError("Framework source does not match the pinned 5-r.5 source tree in DEPENDENCIES.json")
    check_hash(core / "include/Live2DCubismCore.h", pins["cubism_sdk"].get("core_header_sha256"), "Core header")
    if not pins["cubism_sdk"].get("archive_sha256"):
        raise ValueError("Record the official SDK archive SHA-256 in DEPENDENCIES.json before building")
    return core, framework


def binding_root(root, options, pins, api_file, precision):
    cpp = Path(options.get("REDOT_CPP_ROOT") or root / "godot-cpp").expanduser().resolve()
    require_file(cpp / "SConstruct")
    actual = subprocess.check_output(["git", "-C", str(cpp), "rev-parse", "HEAD"], text=True).strip()
    if actual != pins["redot_cpp"]["commit"]:
        raise ValueError("REDOT_CPP_ROOT must match the pinned redot-cpp commit in DEPENDENCIES.json")
    dirty = subprocess.check_output(["git", "-C", str(cpp), "status", "--porcelain", "--untracked-files=no"], text=True)
    if dirty.strip():
        raise ValueError("REDOT_CPP_ROOT contains modified tracked files; use the pinned source unchanged")
    if precision != "single":
        raise ValueError("The Redot 26.2 port requires precision=single")
    if not api_file:
        raise ValueError("Set custom_api_file to the API dump produced by tools/verify_dependencies.py")
    api_path = Path(api_file).expanduser().resolve()
    check_hash(api_path, pins["redot"].get("api_sha256"), "Redot API")
    header = json.loads(api_path.read_text()).get("redot_header", {})
    if (header.get("version_major"), header.get("version_minor"), header.get("precision")) != (26, 2, "single"):
        raise ValueError("The API dump must target Redot 26.2 single precision")
    return cpp


def core_library(path, core, pins):
    relative = path.relative_to(core).as_posix()
    check_hash(path, pins["cubism_sdk"]["core_library_sha256"].get(relative), "Core library")


def windows_core_library(core, env, link="static"):
    """Match the pinned VS 2022 SDK library to the requested Core linkage."""
    if not env.get("is_msvc") or str(env.get("MSVC_VERSION")) != "14.3" or env["arch"] != "x86_64":
        raise ValueError("The Windows baseline requires Visual Studio 2022 (MSVC_VERSION=14.3) and arch=x86_64")
    if link == "dynamic":
        return core / "dll/windows/x86_64/Live2DCubismCore.lib"
    if link != "static":
        raise ValueError("windows_core_link supports static or dynamic")
    # redot-cpp always uses /MDd for debug_crt, including use_static_cpp=yes.
    crt = "MDd" if env["debug_crt"] else ("MT" if env["use_static_cpp"] else "MD")
    return core / "lib/windows/x86_64/143" / f"Live2DCubismCore_{crt}.lib"


def windows_tool_override(cpp, output):
    """Select the pinned v143 toolset through redot-cpp's custom_tools option."""
    source = (cpp / "tools/windows.py").read_text()
    original = 'env["MSVC_VERSION"] = None'
    if source.count(original) != 1:
        raise ValueError("Pinned redot-cpp Windows tool no longer has the expected MSVC selection")
    selected = source.replace(original, 'env["MSVC_VERSION"] = "14.3"')
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "windows.py"
    if not destination.exists() or destination.read_text() != selected:
        destination.write_text(selected)
    return output


def sanitizer_flags(mode, platform):
    """Return addon compiler/linker flags; SDK Core and binding archives stay unchanged."""
    if mode not in ("none", "address", "undefined", "address,undefined"):
        raise ValueError("sanitize supports none, address, undefined or address,undefined")
    if mode == "none":
        return [], []
    if platform != "linux":
        raise ValueError("Sanitizer builds are supported on Linux only")
    flags = ["-fsanitize=" + mode]
    compile_flags = flags + ["-fno-omit-frame-pointer", "-g1"]
    if "undefined" in mode:
        compile_flags += ["-fno-sanitize-recover=undefined"]
    return compile_flags, flags
