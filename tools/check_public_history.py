#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reject private publication paths and restricted bytes in every reachable tree."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from check_restricted_files import inspect_bytes, MAX_BYTES
from publication_policy import inspect_commit


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


def blobs(repo, oids):
    """Yield requested blobs through one bounded cat-file process."""
    process = subprocess.Popen(
        ['git', '-c', 'safe.directory=' + str(repo), '-C', str(repo), 'cat-file', '--batch'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    complete = False
    try:
        for oid in oids:
            process.stdin.write((oid + '\n').encode('ascii'))
            process.stdin.flush()
            header = process.stdout.readline().split()
            if len(header) != 3 or header[0].decode() != oid or header[1] != b'blob':
                raise ValueError('Invalid Git blob response: ' + oid)
            size = int(header[2])
            if size > MAX_BYTES:
                raise ValueError('Git blob exceeds audit size limit: ' + oid)
            data = process.stdout.read(size)
            if len(data) != size or process.stdout.read(1) != b'\n':
                raise ValueError('Truncated Git blob response: ' + oid)
            yield oid, data
        complete = True
    finally:
        if not complete and process.poll() is None:
            process.kill()
        process.stdin.close()
        process.stdout.close()
        code = process.wait()
        if complete and code:
            raise subprocess.CalledProcessError(code, process.args)


def validate_metadata(repo, sha, metadata_base=None):
    if metadata_base is None:
        policy = 'tools/publication-policy.json'
        if git(repo, 'ls-tree', sha, '--', policy):
            metadata_base = json.loads(git(repo, 'show', sha + ':' + policy)).get('metadata_base')
    revisions = [sha]
    if metadata_base:
        base = revision(repo, metadata_base)
        if subprocess.run(['git', '-C', str(repo), 'merge-base', '--is-ancestor', base, sha],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode:
            raise ValueError('Commit metadata base must be an ancestor of the audited revision')
        revisions.append('^' + base)
    records = git(repo, 'log', '-z', '--format=%H%x00%an <%ae>%x00%cn <%ce>%x00%B',
                  *revisions).decode('utf-8', 'replace').split('\0')
    count = 0
    for offset in range(0, len(records) - 1, 4):
        commit, author, committer, message = records[offset:offset + 4]
        problems = inspect_commit(author, committer, message)
        if problems:
            raise ValueError(commit + ': ' + '; '.join(problems))
        count += 1
    return count


def validate_history(repo, ref, metadata_base=None):
    sha = revision(repo, ref)
    metadata_commits = validate_metadata(repo, sha, metadata_base)
    commits = git(repo, 'rev-list', sha).decode().splitlines()
    seen = {}
    by_oid = {}
    for commit in commits:
        for name, mode, kind, oid in entries(repo, commit):
            key = (name, mode, oid)
            if key in seen:
                continue
            seen[key] = commit
            # Check path policy even for an empty submodule or renamed identical blob.
            problems = inspect_bytes(name, b'', public=True)
            if kind == 'commit':
                if problems:
                    raise ValueError(commit + ': ' + '; '.join(problems))
                continue
            if mode not in ('100644', '100755') or kind != 'blob':
                raise ValueError(commit + ': unsupported source entry ' + name)
            by_oid.setdefault(oid, []).append((commit, name))
    for oid, data in blobs(repo, by_oid):
        for commit, name in by_oid[oid]:
            problems = inspect_bytes(name, data, public=True)
            if problems:
                raise ValueError(commit + ': ' + '; '.join(problems))
    return {'revision': sha, 'commits': len(commits), 'file_versions': len(seen),
            'metadata_commits': metadata_commits}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='HEAD')
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--metadata-base', help='Audit commit identities and trailers after this ancestor; empty audits all')
    args = parser.parse_args()
    try:
        result = validate_history(args.repo.resolve(), args.ref, args.metadata_base)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(json.dumps({'status': 'FAIL', 'error': str(error)}, indent=2))
        return 1
    print(json.dumps(dict(status='PASS', **result), indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
