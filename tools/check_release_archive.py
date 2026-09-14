#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Fail closed on restricted source/package contents, including nested archives."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
from check_restricted_files import inspect_bytes, MAX_BYTES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--approved-native", type=Path, help="Reviewed JSON mapping of archive!member paths to exact SHA-256 values")
    parser.add_argument("--source-ref", help="Verify source-only payload and history against a full commit SHA")
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if not args.archive.is_file() or args.archive.stat().st_size > MAX_BYTES:
        parser.error("archive is missing or exceeds the audit size limit")
    if args.source_ref:
        if args.approved_native or not re.fullmatch(r'[0-9a-f]{40}', args.source_ref):
            parser.error("Source verification requires a full commit SHA and forbids native approvals")
        from check_public_history import validate_history
        from package_addon import verify_archive
        try:
            validate_history(args.repo.resolve(), args.source_ref)
            result = verify_archive(args.repo.resolve(), args.source_ref, args.archive)
        except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
            print(json.dumps({'status': 'FAIL', 'error': str(error)}, indent=2))
            return 1
        print(json.dumps({'status': 'PASS', 'revision': result['revision'],
                          'archive_sha256': result['archive_sha256']}, indent=2))
        return 0
    approved = json.loads(args.approved_native.read_text()) if args.approved_native else {}
    problems = inspect_bytes(args.archive.name, args.archive.read_bytes(), approved)
    print(json.dumps({"status": "FAIL" if problems else "PASS", "problems": problems}, indent=2))
    return int(bool(problems))


if __name__ == "__main__":
    sys.exit(main())
