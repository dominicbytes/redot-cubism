#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build and verify a source-only archive of an immutable, sanitized Git revision."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
from check_public_history import blobs, entries, git, revision, validate_history
from check_restricted_files import inspect_bytes, MAX_BYTES

REQUIRED = {'README.md', 'LICENSE.adoc', 'LICENSE.en.adoc', 'NOTICE.md',
            'DEPENDENCIES.json', 'SConstruct', 'docs/quick-start.md',
            'demo/addons/gd_cubism/gd_cubism.gdextension'}


def source_manifest(repo, sha):
    files = {}
    source_entries = list(entries(repo, sha))
    by_oid = {}
    for name, mode, kind, oid in source_entries:
        if kind == 'commit':  # Git archive does not bundle submodule worktrees.
            continue
        if kind != 'blob' or mode not in ('100644', '100755'):
            raise ValueError('Unsupported source entry: ' + name)
        by_oid.setdefault(oid, []).append((name, mode))
    for oid, data in blobs(repo, by_oid):
        for name, mode in by_oid[oid]:
            files[name] = {'sha256': hashlib.sha256(data).hexdigest(),
                           'executable': mode == '100755'}
    missing = REQUIRED - files.keys()
    if missing:
        raise ValueError('Missing required source files: ' + ', '.join(sorted(missing)))
    return files


def verify_archive(repo, sha, archive):
    if not archive.is_file() or archive.stat().st_size > MAX_BYTES:
        raise ValueError('Archive missing or exceeds audit size limit')
    problems = inspect_bytes(archive.name, archive.read_bytes(), public=True)
    if problems:
        raise ValueError('; '.join(problems))
    expected = source_manifest(repo, sha)
    prefix = 'redot-cubism-' + sha[:12] + '/'
    directories = {prefix.rstrip('/')}
    for path, _, _, _ in entries(repo, sha):
        parts = path.split('/')
        directories.update(prefix + '/'.join(parts[:i]) for i in range(1, len(parts)))
    for path, _, kind, _ in entries(repo, sha):
        if kind == 'commit':
            directories.add(prefix + path)
    seen = set()
    seen_directories = set()
    with tarfile.open(archive, 'r:gz') as source:
        for member in source:
            if member.isdir():
                if member.name not in directories or member.name in seen_directories:
                    raise ValueError('Unexpected or duplicate source directory: ' + member.name)
                seen_directories.add(member.name)
                continue
            if not member.name.startswith(prefix):
                raise ValueError('Unexpected archive prefix')
            name = member.name[len(prefix):]
            if not member.isfile() or name not in expected or name in seen:
                raise ValueError('Unexpected or duplicate source member: ' + name)
            with source.extractfile(member) as data:
                digest = hashlib.file_digest(data, 'sha256').hexdigest()
            if digest != expected[name]['sha256'] or bool(member.mode & 0o111) != expected[name]['executable']:
                raise ValueError('Source member differs from Git revision: ' + name)
            seen.add(name)
    if seen != set(expected) or seen_directories != directories:
        raise ValueError('Source archive omits tracked files')
    dependencies = json.loads(git(repo, 'show', sha + ':DEPENDENCIES.json'))
    if not isinstance(dependencies, dict) or not isinstance(dependencies.get('addon_version'), str) or not dependencies['addon_version'].strip():
        raise ValueError('Dependency manifest must record the addon version')
    return {'revision': sha, 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'addon_version': dependencies['addon_version'], 'dependencies': dependencies,
            'dependencies_sha256': expected['DEPENDENCIES.json']['sha256'],
            'submodules': {name: oid for name, _, kind, oid in entries(repo, sha) if kind == 'commit'},
            'files': expected}


def package(repo, ref, archive):
    if not re.fullmatch(r'[0-9a-f]{40}', ref):
        raise ValueError('Use a full immutable 40-character commit SHA')
    sha = revision(repo, ref)
    if sha != ref:
        raise ValueError('Use the exact full 40-character commit SHA, not another object type')
    history = validate_history(repo, sha)
    source_manifest(repo, sha)  # Reject incomplete refs before creating an output.
    manifest = archive.with_name(archive.name + '.manifest.json')
    if archive.exists() or manifest.exists():
        raise ValueError('Output or manifest already exists')
    archive.parent.mkdir(parents=True, exist_ok=True)
    archive_created = False
    manifest_created = False
    try:
        with archive.open('xb') as output:
            archive_created = True
            subprocess.run(['git', '-c', 'safe.directory=' + str(repo), '-C', str(repo),
                            'archive', '--format=tar.gz', '--prefix=redot-cubism-' + sha[:12] + '/', sha],
                           stdout=output, check=True)
        result = verify_archive(repo, sha, archive)
        result.update(history=history, source_only=True, release_qualified=False)
        with manifest.open('x') as output:
            manifest_created = True
            output.write(json.dumps(result, indent=2, sort_keys=True) + '\n')
    except Exception:
        if archive_created:
            archive.unlink(missing_ok=True)
        if manifest_created:
            manifest.unlink(missing_ok=True)
        raise
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-only', action='store_true', required=True)
    parser.add_argument('--ref', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        result = package(args.repo.resolve(), args.ref, args.output.resolve())
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print('Source package rejected: ' + str(error), file=sys.stderr)
        return 1
    print(json.dumps({'status': 'PASS', 'revision': result['revision'],
                      'archive_sha256': result['archive_sha256'], 'release_qualified': False}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
