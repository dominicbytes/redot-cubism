#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Audit tracked bytes or Git history; never trust ignore rules as a scanner."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import zipfile

MAX_BYTES = 128 * 1024 * 1024
MAX_MEMBERS = 10000
MAX_DEPTH = 4
NATIVE = {".dll", ".so", ".dylib", ".a", ".lib", ".aar", ".exe"}
SAMPLES = {"haru", "hiyori", "mark", "natori", "rice", "mao", "ren", "wanko"}


def git(*args):
    return subprocess.check_output(["git", *args])


def inspect_bytes(name, data, approved=None, depth=0, budget=None, public=False):
    """Return problems; approvals allow only one exact native file/hash pair."""
    approved = approved or {}
    budget = budget if budget is not None else [MAX_BYTES, MAX_MEMBERS]
    lower = name.replace("\\", "/").lower()
    parts = PurePosixPath(lower).parts
    suffix = PurePosixPath(lower).suffix
    problems = []
    if public:
        public_parts = PurePosixPath(lower.replace("!", "/")).parts
        if (any(p in {".local-build", ".private-fixtures", ".local-sdk"} for p in public_parts)
                or "source-of-truth.xlsx" in public_parts or suffix == ".bundle"):
            problems.append(f"{name}: private publication content")
    # Upstream history contains this empty SDK-directory placeholder, not SDK bytes.
    sdk_placeholder = (lower == "thirdparty/cubismsdkfornative/.gitignore"
                       and data == b"*\n!.gitignore\n")
    if "live2dcubismcore" in lower or ("cubismsdkfornative" in lower and not sdk_placeholder):
        problems.append(f"{name}: restricted Core/SDK path")
    if suffix == ".moc3" or any(p in SAMPLES for p in parts):
        problems.append(f"{name}: model/sample path requires separate review")
    if any(p in {".private-fixtures", ".local-sdk", "cubism-core", "cubism-sdk"} for p in parts):
        problems.append(f"{name}: private input directory")
    if suffix in NATIVE or ".so." in lower or any(p.endswith(".framework") for p in parts) or data.startswith((b"\x7fELF", b"MZ", b"!<arch>\n", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf")):
        if approved.get(name) != hashlib.sha256(data).hexdigest():
            problems.append(f"{name}: unapproved native binary")
    if data.startswith(b"MOC3"):
        problems.append(f"{name}: Cubism MOC signature")
    if suffix in {".h", ".hpp"} and re.search(rb"CSM_API\s+[^;\n]*\bcsmGetVersion\s*\(", data):
        problems.append(f"{name}: Cubism Core header signature")
    if len(data) > MAX_BYTES:
        return problems + [f"{name}: audit size limit exceeded"]

    def member(child_name, size, read, is_link=False):
        child = f"{name}!{child_name}"
        path = PurePosixPath(child_name.replace("\\", "/"))
        if path.is_absolute() or ".." in path.parts or is_link:
            problems.append(f"{child}: unsafe archive member")
            return
        budget[0] -= size
        budget[1] -= 1
        if depth >= MAX_DEPTH or min(budget) < 0:
            problems.append(f"{child}: archive audit limit exceeded")
            return
        problems.extend(inspect_bytes(child, read(), approved, depth + 1, budget, public))

    try:
        stream = io.BytesIO(data)
        if zipfile.is_zipfile(stream):
            with zipfile.ZipFile(stream) as archive:
                for entry in archive.infolist():
                    if not entry.is_dir():
                        member(entry.filename, entry.file_size,
                               lambda e=entry: archive.read(e),
                               (entry.external_attr >> 16) & 0o170000 == 0o120000)
                    if min(budget) < 0:
                        break
        elif lower.endswith((".zip", ".xlsx", ".jar", ".aar")):
            problems.append(f"{name}: invalid ZIP archive")
        elif (lower.endswith((".tar", ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2"))
              or tarfile.is_tarfile(stream)):
            stream.seek(0)
            with tarfile.open(fileobj=stream, mode="r:*") as archive:
                for entry in archive:
                    if not entry.isdir():
                        member(entry.name, entry.size,
                               lambda e=entry: archive.extractfile(e).read(),
                               not entry.isfile())
                    if min(budget) < 0:
                        break
    except (OSError, ValueError, RuntimeError, tarfile.TarError, zipfile.BadZipFile) as exc:
        problems.append(f"{name}: unreadable archive ({type(exc).__name__})")
    return problems


def scan_repository(history=None):
    problems = []
    count = 0
    if history:
        # Object contents, including deleted historical files. No checkout or execution.
        objects = git("rev-list", "--objects", history).splitlines()
        proc = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            for entry in objects:
                oid, _, name = entry.partition(b" ")
                if not name:
                    continue
                proc.stdin.write(oid + b"\n")
                proc.stdin.flush()
                header = proc.stdout.readline().split()
                if len(header) != 3:
                    raise ValueError("Invalid git cat-file response")
                size = int(header[2])
                if size > MAX_BYTES:
                    raise ValueError("History object exceeds audit size limit")
                data = proc.stdout.read(size)
                proc.stdout.read(1)
                if header[1] == b"blob":
                    count += 1
                    problems.extend(inspect_bytes(name.decode("utf-8", "replace"), data))
        finally:
            proc.stdin.close()
            proc.stdout.close()
            proc.wait()
    else:
        for raw in git("ls-files", "-s", "-z").split(b"\0"):
            if not raw:
                continue
            meta, path = raw.split(b"\t", 1)
            mode, oid, stage = meta.split()
            if mode == b"160000":  # submodules have their own pinned source audit
                continue
            if mode == b"120000":
                problems.append(f"{path.decode()}: tracked symlink requires review")
                continue
            name = path.decode("utf-8")
            count += 1
            problems.extend(inspect_bytes(name, git("cat-file", "blob", oid.decode())))
            if Path(name).is_file():
                problems.extend(inspect_bytes(name, Path(name).read_bytes()))
    return count, sorted(set(problems))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", help="Audit all reachable file versions in a Git revision")
    args = parser.parse_args()
    try:
        count, problems = scan_repository(args.history)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"Audit failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"files_checked": count, "status": "FAIL" if problems else "PASS", "problems": problems}, indent=2))
    return int(bool(problems))


if __name__ == "__main__":
    sys.exit(main())
