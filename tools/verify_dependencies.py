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

from build_inputs import supported_engine

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".local-build/identity")
    parser.add_argument("--binding-bin", default=os.environ.get("REDOT_BINDING_BIN"),
                        help="Pinned 26.2 editor for the binding API when REDOT_BIN selects another runtime")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    pins = json.loads((ROOT / "DEPENDENCIES.json").read_text())
    binary = os.environ.get("REDOT_BIN")
    if not binary or not Path(binary).is_file():
        parser.error("Set REDOT_BIN to a supported Redot editor.")
    binary = str(Path(binary).resolve())
    env = dict(os.environ)
    for name in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{name}_HOME"] = str(args.output / name.lower())

    def run(*switches, executable=binary, directory=args.output):
        result = subprocess.run([executable, *switches], cwd=directory, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        clean = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout)
        if result.returncode or re.search(r"(?:SCRIPT ERROR|ERROR:|WARNING:)", clean):
            raise ValueError(clean)
        return clean

    try:
        version = run("--version").strip()
        if not supported_engine(version, pins):
            raise ValueError("Unsupported Redot runtime: " + version)
        help_text = run("--help")
        (args.output / "redot-help.txt").write_text(help_text)
        for switch in ("--headless", "--editor", "--dump-extension-api", "--dump-gdextension-interface", "--quit-after"):
            if switch not in help_text:
                raise ValueError(f"Required editor switch missing: {switch}")
        binding = str(Path(args.binding_bin).resolve()) if args.binding_bin else binary
        binding_version = run("--version", executable=binding).strip()
        if binding_version != pins["redot"]["version"]:
            raise ValueError("Set --binding-bin or REDOT_BINDING_BIN to the pinned 26.2 editor; runtime API dumps are not binding inputs")
        switches = ("--headless", "--audio-driver", "Dummy", "--editor", "--dump-extension-api", "--dump-gdextension-interface", "--quit-after", "2")
        log = run(*switches, executable=binding)
        (args.output / "api-dump.log").write_text(log)
        if version != binding_version:
            runtime_output = args.output / "runtime"
            runtime_output.mkdir(exist_ok=True)
            runtime_log = run(*switches, directory=runtime_output)
            (runtime_output / "api-dump.log").write_text(runtime_log)
            runtime_api = json.loads((runtime_output / "extension_api.json").read_text())
            header = runtime_api.get("redot_header", {})
            if (header.get("version_major"), header.get("version_minor"), header.get("precision")) != (26, int(version.split(".")[1]), "single"):
                raise ValueError("Runtime API must match the supported single-precision engine")
        api = json.loads((args.output / "extension_api.json").read_text())
        redot_header = api.get("redot_header", {})
        if (redot_header.get("version_major"), redot_header.get("version_minor"), redot_header.get("precision")) != (26, 2, "single"):
            raise ValueError("Generated API must be Redot 26.2 single precision")
        if sha256(args.output / "extension_api.json") != pins["redot"]["api_sha256"]:
            raise ValueError("Binding API SHA-256 differs from DEPENDENCIES.json")
        report = {"binding_engine_version": binding_version, "status": "PASS", "platform": platform.system(), "architecture": platform.machine(),
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
