#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Fingerprint the actual Redot host and generate its native API, without Core."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".local-build/identity")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    pins = json.loads((ROOT / "DEPENDENCIES.json").read_text())
    binary = os.environ.get("REDOT_BIN")
    if not binary or not Path(binary).is_file():
        parser.error("Set REDOT_BIN to an executable Redot 26.2 editor.")
    binary = str(Path(binary).resolve())
    env = dict(os.environ)
    for name in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{name}_HOME"] = str(args.output / name.lower())

    def run(*switches):
        result = subprocess.run([binary, *switches], cwd=args.output, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        clean = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout)
        if result.returncode or re.search(r"(?:SCRIPT ERROR|ERROR:|WARNING:)", clean):
            raise ValueError(clean)
        return clean

    try:
        version = run("--version").strip()
        if version != pins["redot"]["version"]:
            raise ValueError(f"Expected {pins['redot']['version']}; got {version}")
        help_text = run("--help")
        (args.output / "redot-help.txt").write_text(help_text)
        for switch in ("--headless", "--editor", "--dump-extension-api", "--dump-gdextension-interface", "--quit-after"):
            if switch not in help_text:
                raise ValueError(f"Required editor switch missing: {switch}")
        log = run("--headless", "--editor", "--dump-extension-api", "--dump-gdextension-interface", "--quit-after", "2")
        (args.output / "api-dump.log").write_text(log)
        api = json.loads((args.output / "extension_api.json").read_text())
        redot_header = api.get("redot_header", {})
        if (redot_header.get("version_major"), redot_header.get("version_minor"), redot_header.get("precision")) != (26, 2, "single"):
            raise ValueError("Generated API must be Redot 26.2 single precision")
        report = {"status": "PASS", "platform": platform.system(), "architecture": platform.machine(),
                  "engine_version": version, "engine_sha256": sha256(binary), "python": platform.python_version(),
                  "api_sha256": sha256(args.output / "extension_api.json"), "api_header": api["header"], "redot_api_header": redot_header,
                  "interface_sha256": sha256(args.output / "gdextension_interface.h"),
                  "sdk_provisioned": bool(os.environ.get("CUBISM_SDK_ROOT")), "model_runtime_tested": False}
        (args.output / "host.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        return 0
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"Dependency verification failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
