#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Fail closed on restricted source/package contents, including nested archives."""
import argparse
import json
from pathlib import Path
import sys
from check_restricted_files import inspect_bytes, MAX_BYTES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--approved-native", type=Path, help="Reviewed JSON mapping of archive!member paths to exact SHA-256 values")
    args = parser.parse_args()
    if not args.archive.is_file() or args.archive.stat().st_size > MAX_BYTES:
        parser.error("archive is missing or exceeds the audit size limit")
    approved = json.loads(args.approved_native.read_text()) if args.approved_native else {}
    problems = inspect_bytes(args.archive.name, args.archive.read_bytes(), approved)
    print(json.dumps({"status": "FAIL" if problems else "PASS", "problems": problems}, indent=2))
    return int(bool(problems))


if __name__ == "__main__":
    sys.exit(main())
