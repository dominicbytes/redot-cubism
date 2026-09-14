#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reject private publication paths and restricted bytes in every reachable tree."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from check_restricted_files import inspect_bytes, MAX_BYTES


def git(repo, *args):
    return subprocess.check_output(['git', '-c', 'safe.directory=' + str(repo), '-C', str(repo), *args])


def revision(repo, ref):
    return git(repo, 'rev-parse', '--verify', '--end-of-options', ref + '^{commit}').decode().strip()


def entries(repo, ref):
    for row in git(repo, 'ls-tree', '-rz', ref).split(b'\0'):
        if row:
            meta, name = row.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            yield name.decode('utf-8'), mode, kind, oid


def blob(repo, oid):
    if int(git(repo, 'cat-file', '-s', oid)) > MAX_BYTES:
        raise ValueError('Git blob exceeds audit size limit: ' + oid)
    return git(repo, 'cat-file', 'blob', oid)


def validate_history(repo, ref):
    sha = revision(repo, ref)
    commits = git(repo, 'rev-list', sha).decode().splitlines()
    seen = set()
    for commit in commits:
        for name, mode, kind, oid in entries(repo, commit):
            key = (name, mode, oid)
            if key in seen:
                continue
            seen.add(key)
            # Check path policy even for an empty submodule or renamed identical blob.
            problems = inspect_bytes(name, b'', public=True)
            if kind == 'commit':
                if problems:
                    raise ValueError(commit + ': ' + '; '.join(problems))
                continue
            if mode not in ('100644', '100755') or kind != 'blob':
                raise ValueError(commit + ': unsupported source entry ' + name)
            problems = inspect_bytes(name, blob(repo, oid), public=True)
            if problems:
                raise ValueError(commit + ': ' + '; '.join(problems))
    return {'revision': sha, 'commits': len(commits), 'file_versions': len(seen)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='HEAD')
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        result = validate_history(args.repo.resolve(), args.ref)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(json.dumps({'status': 'FAIL', 'error': str(error)}, indent=2))
        return 1
    print(json.dumps(dict(status='PASS', **result), indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
