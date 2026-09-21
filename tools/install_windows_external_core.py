#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Install a user-supplied Cubism Core beside dynamically linked Windows builds."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

from windows_pe import imported_dlls_from_file


DEPENDENCY_LINE = 'windows.x86_64 = {"bin/Live2DCubismCore.dll": ""}'


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def descriptor_with_dependency(text):
    lines = text.splitlines()
    section = next((index for index, line in enumerate(lines)
                    if line.strip() == "[dependencies]"), None)
    if section is None:
        return text.rstrip() + "\n\n[dependencies]\n\n" + DEPENDENCY_LINE + "\n"
    end = next((index for index in range(section + 1, len(lines))
                if lines[index].strip().startswith("[") and lines[index].strip().endswith("]")),
               len(lines))
    existing = next((line.strip() for line in lines[section + 1:end]
                     if line.strip().startswith("windows.x86_64") and "=" in line), None)
    if existing and existing != DEPENDENCY_LINE:
        raise ValueError("Existing Windows GDExtension dependency differs from the external-Core setup")
    if existing:
        return text
    lines.insert(end, DEPENDENCY_LINE)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


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

    descriptor = addon / "gd_cubism.gdextension"
    original = descriptor.read_text()
    updated = descriptor_with_dependency(original)
    destination = addon / "bin/Live2DCubismCore.dll"
    shutil.copyfile(source, destination)
    if sha256(destination) != expected:
        raise ValueError("Copied Cubism Core failed SHA-256 verification")
    if updated != original:
        descriptor.write_text(updated)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--addon-dir", type=Path, default=Path("demo/addons/gd_cubism"))
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        destination = install(args.repo.resolve(), args.sdk_root.expanduser().resolve(),
                              args.addon_dir.resolve())
    except (OSError, ValueError) as error:
        print(f"External Cubism Core install failed: {error}", file=sys.stderr)
        return 1
    print(f"Installed verified user-supplied Cubism Core: {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
