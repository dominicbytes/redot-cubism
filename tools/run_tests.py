#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Run the selected implemented suite. Missing required gates never pass."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", required=True, choices=["public", "abi", "licensed-desktop", "editor", "visual", "export", "benchmark"])
    parser.add_argument("--output", type=Path, default=Path(os.environ.get("TEST_OUTPUT_DIR", ROOT / ".local-build/test-results")))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.suite == "public":
        commands = [[sys.executable, "-m", "unittest", "discover", "-s", "tests/python", "-v"],
                    [sys.executable, "tools/check_restricted_files.py"], ["git", "diff", "--check"]]
    elif args.suite == "abi":
        commands = [[sys.executable, "tools/run_abi_tests.py", "--output", str(args.output)]]
    else:
        print(f"BLOCKED: {args.suite} is not qualified at this stage. It requires the matched SDK, fixture and target runner.", file=sys.stderr)
        return 2
    results = []
    for index, command in enumerate(commands):
        start = time.monotonic()
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
            code, log = result.returncode, result.stdout
        except subprocess.TimeoutExpired:
            code, log = 124, "Test command exceeded the wall-clock limit."
        path = args.output / f"{args.suite}-{index}.log"
        path.write_text(log)
        results.append({"command": command, "exit_code": code, "elapsed_seconds": round(time.monotonic() - start, 3), "log": path.name})
        print(log, end="" if log.endswith("\n") else "\n")
        if code:
            break
    status = "FAIL" if any(r["exit_code"] for r in results) else "PASS"
    (args.output / f"{args.suite}.json").write_text(json.dumps({"suite": args.suite, "status": status, "checks": results, "cubism_model_tests_selected": False}, indent=2) + "\n")
    return int(status != "PASS")


if __name__ == "__main__":
    sys.exit(main())
