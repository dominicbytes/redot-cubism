#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Install a user-supplied Cubism Core beside dynamically linked Linux builds."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


DEPENDENCY_SECTION = '''

[dependencies]

linux.x86_64 = {"bin/libLive2DCubismCore.so": ""}
'''


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_dynamic_library(path):
    environment = dict(os.environ, LC_ALL="C")
    result = subprocess.run(["readelf", "-d", str(path)], text=True, env=environment,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f"readelf could not inspect {path}: {result.stderr.strip()}")
    if "Shared library: [libLive2DCubismCore.so]" not in result.stdout:
        raise ValueError(
            f"{path} is not linked to the external Cubism Core; rebuild with linux_core_link=dynamic")
    if "Library runpath: [$ORIGIN]" not in result.stdout and "Library rpath: [$ORIGIN]" not in result.stdout:
        raise ValueError(f"{path} does not search its own directory for Cubism Core")


def install(repo, sdk, addon):
    pins = json.loads((repo / "DEPENDENCIES.json").read_text())
    source = sdk / "Core/dll/linux/x86_64/libLive2DCubismCore.so"
    if not source.is_file():
        raise ValueError(
            "User-supplied Core is missing: expected Core/dll/linux/x86_64/"
            f"libLive2DCubismCore.so under {sdk}")
    expected = pins["cubism_sdk"]["core_library_sha256"].get(
        "dll/linux/x86_64/libLive2DCubismCore.so")
    if not expected or sha256(source) != expected:
        raise ValueError("User-supplied Linux Core does not match the pinned SDK 5-r.5 SHA-256")

    binaries = sorted((addon / "bin").glob("libgd_cubism.linux.*.x86_64.so"))
    if not binaries:
        raise ValueError(f"No Linux addon library found under {addon / 'bin'}")
    for binary in binaries:
        inspect_dynamic_library(binary)

    descriptor = addon / "gd_cubism.gdextension"
    text = descriptor.read_text()
    if "[dependencies]" in text:
        if DEPENDENCY_SECTION.strip() not in text:
            raise ValueError("Existing GDExtension dependencies differ from the external-Core setup")
    else:
        descriptor.write_text(text.rstrip() + DEPENDENCY_SECTION + "\n")

    destination = addon / "bin/libLive2DCubismCore.so"
    shutil.copyfile(source, destination)
    if sha256(destination) != expected:
        raise ValueError("Copied Cubism Core failed SHA-256 verification")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--addon-dir", type=Path,
                        default=Path("demo/addons/gd_cubism"))
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        destination = install(args.repo.resolve(), args.sdk_root.expanduser().resolve(),
                              args.addon_dir.resolve())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"External Cubism Core install failed: {error}", file=sys.stderr)
        return 1
    print(f"Installed verified user-supplied Cubism Core: {destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
