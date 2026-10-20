#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Install a user-supplied Cubism Core beside dynamically linked Windows builds."""
import argparse
import json
from pathlib import Path
import sys

from external_core_install import (descriptor_with_dependency as merge_dependency,
                                   install_files, sha256)

from windows_pe import imported_dlls_from_file


DEPENDENCY_LINE = 'windows.x86_64 = {"bin/Live2DCubismCore.dll": ""}'


def descriptor_with_dependency(text):
    return merge_dependency(text, "windows.x86_64", DEPENDENCY_LINE)


def inspect_dynamic_library(path):
    imports = {name.lower() for name in imported_dlls_from_file(path)}
    if "live2dcubismcore.dll" not in imports:
        raise ValueError(
            f"{path} is not linked to the external Cubism Core; rebuild with windows_core_link=dynamic")


def install(repo, sdk, addon):
    pins = json.loads((repo / "DEPENDENCIES.json").read_text())
    relative = "dll/windows/x86_64/Live2DCubismCore.dll"
    source = sdk / "Core" / relative
    if not source.is_file():
        raise ValueError(f"User-supplied Core is missing: expected Core/{relative} under {sdk}")
    expected = pins["cubism_sdk"]["core_library_sha256"].get(relative)
    if not expected or sha256(source) != expected:
        raise ValueError("User-supplied Windows Core does not match the pinned SDK 5-r.5 SHA-256")

    binaries = sorted((addon / "bin").glob("libgd_cubism.windows.*.x86_64.dll"))
    if not binaries:
        raise ValueError(f"No Windows addon library found under {addon / 'bin'}")
    for binary in binaries:
        inspect_dynamic_library(binary)

    return install_files(addon, source, expected, "Live2DCubismCore.dll", descriptor_with_dependency)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--addon-dir", type=Path, default=Path("demo/addons/gd_cubism"))
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        destination = install(args.repo.resolve(), args.sdk_root.expanduser().resolve(),
                              args.addon_dir.absolute())
    except (OSError, ValueError) as error:
        print(f"External Cubism Core install failed: {error}", file=sys.stderr)
        return 1
    print(f"Installed verified user-supplied Cubism Core: {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
