# SPDX-License-Identifier: MIT
"""Inspect bounded, unencrypted standalone test PCKs using the pinned v2/v3 layout."""
import hashlib
from pathlib import Path, PurePosixPath
import struct


def inspect_pack(path: Path) -> dict:
    size = path.stat().st_size
    if size > 8 * 1024**3:
        raise ValueError("PCK exceeds inspection size limit")
    with path.open('rb') as stream:
        def read(count):
            data = stream.read(count)
            if len(data) != count:
                raise ValueError("Truncated PCK")
            return data

        def number(fmt):
            return struct.unpack(fmt, read(struct.calcsize(fmt)))[0]

        magic, version, major, minor, patch, flags = struct.unpack('<6I', read(24))
        if magic != 0x43504447 or version not in (2, 3) or flags & ~2:
            raise ValueError("Unsupported PCK header, encryption or sparse pack")
        base = number('<Q')
        directory = number('<Q') if version == 3 else 96
        if not 32 <= directory < size:
            raise ValueError("Invalid PCK directory offset")
        stream.seek(directory)
        count = number('<I')
        if count > 100000:
            raise ValueError("PCK exceeds file-count limit")
        entries = {}
        for _ in range(count):
            length = number('<I')
            if not 0 < length <= 16384:
                raise ValueError("Invalid PCK path length")
            name = read(length).rstrip(b'\0').decode('utf-8').removeprefix('res://')
            if not name or '\0' in name or '\\' in name or ':' in name or PurePosixPath(name).is_absolute() or any(part in ('', '.', '..') for part in name.split('/')):
                raise ValueError("Unsafe PCK path")
            offset, length = struct.unpack('<QQ', read(16))
            md5 = read(16)
            entry_flags = number('<I')
            if entry_flags or base + offset + length > size:
                raise ValueError("Unsupported or out-of-bounds PCK entry")
            if name in entries:
                raise ValueError("Duplicate PCK entry: " + name)
            entries[name] = {'offset': base + offset, 'size': length, 'md5': md5.hex()}
        for name, entry in entries.items():
            stream.seek(entry['offset'])
            remaining = entry['size']
            md5, sha256 = hashlib.md5(), hashlib.sha256()
            while remaining:
                data = read(min(remaining, 1024 * 1024))
                md5.update(data)
                sha256.update(data)
                remaining -= len(data)
            if md5.hexdigest() != entry['md5']:
                raise ValueError("PCK content checksum mismatch: " + name)
            entry['sha256'] = sha256.hexdigest()
    return {'format_version': version, 'engine_version': [major, minor, patch], 'files': entries}
