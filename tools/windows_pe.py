# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Small, dependency-free PE import reader for release and installer checks."""
import struct


def imported_dlls(data):
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError("not a PE image")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if pe + 24 > len(data) or data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("invalid PE header")
    sections = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    if optional + optional_size > len(data):
        raise ValueError("truncated PE optional header")
    magic = struct.unpack_from("<H", data, optional)[0]
    directory = optional + (112 if magic == 0x20B else 96 if magic == 0x10B else -1)
    if directory < optional or directory + 16 > optional + optional_size:
        raise ValueError("unsupported PE optional header")
    import_rva, import_size = struct.unpack_from("<II", data, directory + 8)
    if not import_rva or not import_size:
        return []
    table = optional + optional_size
    section_rows = []
    for index in range(sections):
        row = table + index * 40
        if row + 40 > len(data):
            raise ValueError("truncated PE section table")
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, row + 8)
        section_rows.append((virtual_address, max(virtual_size, raw_size), raw_offset, raw_size))

    def offset(rva):
        for virtual_address, span, raw_offset, raw_size in section_rows:
            delta = rva - virtual_address
            if 0 <= delta < span and delta < raw_size and raw_offset + delta < len(data):
                return raw_offset + delta
        raise ValueError("PE import RVA is outside file-backed sections")

    cursor = offset(import_rva)
    end = min(len(data), cursor + import_size)
    names = []
    while cursor + 20 <= end:
        descriptor = struct.unpack_from("<IIIII", data, cursor)
        if descriptor == (0, 0, 0, 0, 0):
            return names
        name_offset = offset(descriptor[3])
        terminator = data.find(b"\0", name_offset, min(len(data), name_offset + 4096))
        if terminator < 0:
            raise ValueError("unterminated PE import name")
        try:
            names.append(data[name_offset:terminator].decode("ascii"))
        except UnicodeDecodeError as exc:
            raise ValueError("non-ASCII PE import name") from exc
        cursor += 20
    raise ValueError("unterminated PE import table")


def imported_dlls_from_file(path):
    with open(path, "rb") as stream:
        return imported_dlls(stream.read())
