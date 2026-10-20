# SPDX-License-Identifier: MIT
"""Stage the pinned bindings with forward-compatible Variant destruction."""
from pathlib import Path
import subprocess

PATCH_ID = "variant-clear-forward-types-v1"
OLD = "if (unlikely(needs_deinit[get_type()]))"
NEW = "if (unlikely(get_type() >= VARIANT_MAX || needs_deinit[get_type()]))"


def patch_variant(source):
    if source.count(OLD) != 1:
        raise ValueError("Pinned Variant::clear no longer has the expected cleanup lookup")
    return source.replace(OLD, NEW)


def prepare_bindings(cpp, output):
    files = subprocess.check_output(["git", "-C", str(cpp), "ls-files"], text=True).splitlines()
    for name in files:
        relative = Path(name)
        if relative.parts[0] not in ("src", "include", "gdextension", "tools") and relative.name != "SConstruct" and relative.suffix != ".py":
            continue
        data = (cpp / relative).read_bytes()
        if name == "src/variant/variant.cpp":
            data = patch_variant(data.decode()).encode()
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
    return output
