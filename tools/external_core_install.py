# SPDX-License-Identifier: MIT
"""Validated, rollback-capable replacement of user-supplied Core files."""
from contextlib import ExitStack
import hashlib
import os
from pathlib import Path
import re
import secrets
import shutil
import stat


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def descriptor_with_dependency(text, key, dependency):
    lines = text.splitlines()
    section = next((i for i, line in enumerate(lines)
                    if line.strip() == "[dependencies]"), None)
    if section is None:
        return text.rstrip() + "\n\n[dependencies]\n\n" + dependency + "\n"
    end = next((i for i in range(section + 1, len(lines))
                if lines[i].strip().startswith("[") and lines[i].strip().endswith("]")),
               len(lines))
    existing = [line.strip() for line in lines[section + 1:end]
                if "=" in line and line.split("=", 1)[0].strip() == key]
    def normalized(value):
        return re.sub(r'"(?:\\.|[^"\\])*"|\s+',
                      lambda match: match[0] if match[0].startswith('"') else "", value)
    if len(existing) > 1 or (existing and normalized(existing[0]) != normalized(dependency)):
        raise ValueError("Existing GDExtension dependency differs from the external-Core setup")
    if existing:
        return text
    lines.insert(end, dependency)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def checked_stat(value, directory=False):
    if stat.S_ISLNK(value.st_mode) or getattr(value, "st_file_attributes", 0) & 0x400:
        raise ValueError("Output links and reparse points are not allowed")
    if directory:
        if not stat.S_ISDIR(value.st_mode):
            raise ValueError("Output ancestor is not a directory")
    elif not stat.S_ISREG(value.st_mode) or value.st_nlink != 1:
        raise ValueError("Output must be a regular file without hard links")


class OutputDirectory:
    """Pin output directories against link swaps for the duration of installation."""
    def __init__(self, path, parent=None):
        self.path = path
        self.fd = None
        self.handle = None
        checked_stat(path.lstat(), directory=True)
        if parent is not None and path.resolve().parent != parent.path.resolve():
            raise ValueError("Output escapes the addon root")
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            self.kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
                wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
            self.kernel.CreateFileW.restype = wintypes.HANDLE
            self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
            # Excluding delete sharing prevents a directory rename/junction swap.
            handle = self.kernel.CreateFileW(str(path), 0x80, 3, None, 3, 0x02200000, None)
            if handle == wintypes.HANDLE(-1).value:
                raise ctypes.WinError(ctypes.get_last_error())
            self.handle = handle
            try:
                checked_stat(path.lstat(), directory=True)
                if parent is not None and path.resolve().parent != parent.path.resolve():
                    raise ValueError("Output escapes the addon root")
            except BaseException:
                self.close()
                raise
        else:
            self.fd = os.open(path.name if parent else path,
                              os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                              dir_fd=parent.fd if parent else None)

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None
        if self.handle is not None:
            self.kernel.CloseHandle(self.handle)
            self.handle = None

    def validate(self, name, missing=False):
        try:
            value = os.stat(name if self.fd is not None else self.path / name,
                            dir_fd=self.fd, follow_symlinks=False)
        except FileNotFoundError:
            if missing:
                return None
            raise
        checked_stat(value)
        return value

    def read(self, name, missing=False):
        before = self.validate(name, missing)
        if before is None:
            return None
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(name if self.fd is not None else self.path / name, flags, dir_fd=self.fd)
        with os.fdopen(fd, "rb") as stream:
            current = os.fstat(stream.fileno())
            checked_stat(current)
            if (before.st_dev, before.st_ino) != (current.st_dev, current.st_ino):
                raise ValueError("Output changed while being opened")
            return stream.read()

    def stage(self, data=None, source=None, expected=None):
        name = ".core-install-" + secrets.token_hex(16)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0)
        fd = os.open(name if self.fd is not None else self.path / name, flags, 0o644, dir_fd=self.fd)
        try:
            with os.fdopen(fd, "wb") as output:
                if source is not None:
                    with source.open("rb") as input_stream:
                        shutil.copyfileobj(input_stream, output)
                else:
                    output.write(data)
                output.flush()
                os.fsync(output.fileno())
            if expected and hashlib.sha256(self.read(name)).hexdigest() != expected:
                raise ValueError("Copied Cubism Core failed SHA-256 verification")
            return name
        except BaseException:
            self.remove(name)
            raise

    def replace(self, source, destination):
        self.validate(source)
        self.validate(destination, missing=True)
        if self.fd is not None:
            os.replace(source, destination, src_dir_fd=self.fd, dst_dir_fd=self.fd)
        else:
            os.replace(self.path / source, self.path / destination)

    def remove(self, name):
        try:
            os.unlink(name if self.fd is not None else self.path / name, dir_fd=self.fd)
        except FileNotFoundError:
            pass


def install_files(addon, source, expected, filename, update_descriptor):
    addon = Path(os.path.abspath(addon))
    with ExitStack() as stack:
        if os.name == "nt":
            # Path-based Windows replacements need every ancestor held against rename.
            for ancestor in reversed(addon.parents):
                pinned = OutputDirectory(ancestor)
                stack.callback(pinned.close)
        root = OutputDirectory(addon)
        stack.callback(root.close)
        binaries = OutputDirectory(addon / "bin", root)
        stack.callback(binaries.close)
        descriptor = "gd_cubism.gdextension"
        original = root.read(descriptor)
        previous = binaries.read(filename, missing=True)
        updated = update_descriptor(original.decode("utf-8")).encode("utf-8")
        changes = []
        temporary = []
        try:
            core_temp = binaries.stage(source=source, expected=expected)
            temporary.append((binaries, core_temp))
            changes.append((binaries, filename, core_temp, previous))
            if updated != original:
                descriptor_temp = root.stage(data=updated)
                temporary.append((root, descriptor_temp))
                changes.append((root, descriptor, descriptor_temp, original))
            backups = []
            for directory, name, staged, old in changes:
                backup = directory.stage(data=old) if old is not None else None
                if backup:
                    temporary.append((directory, backup))
                backups.append((directory, name, staged, backup))
            replaced = []
            try:
                for directory, name, staged, backup in backups:
                    directory.replace(staged, name)
                    replaced.append((directory, name, backup))
            except BaseException:
                for directory, name, backup in reversed(replaced):
                    if backup is None:
                        directory.remove(name)
                    else:
                        directory.replace(backup, name)
                raise
        finally:
            for directory, name in temporary:
                directory.remove(name)
    return addon / "bin" / filename
