# SPDX-License-Identifier: MIT
"""Narrow publication checks for local path bytes and commit identities."""
import re

# Reviewed generic examples already used by build documentation and path tests.
GENERIC_PATHS = {
    "c:" + "/file", "c:" + "/path/to", "c:" + "/path/to/",
    "c:" + "/tools/redot/redot.exe", "d:" + "/android/sdk",
    "d:" + "/sdk/cubismsdkfornative-5-r.5",
    "c:" + "/sdk/cubismsdkfornative-5-r.5",
    "c:" + "/hero.moc3", "c:" + "/escape.moc3",
    "c:" + "/program files (x86)/microsoft visual studio/2022/buildtools/common7/tools/launch-vsdevshell.ps1",
}
PATH_PATTERNS = (
    re.compile(r"(?<![A-Za-z0-9_])([A-Za-z]:[\\/]+[^\x00-\x20\x7f\"'<>|`;{}\[\]][^\x00-\x1f\x7f\"'<>|`;{}\[\]]*)(?=$|[\x00-\x20\"'<>|`;{}\[\]])"),
    re.compile(r"((?:/ho" r"me/|/?Users[\\/])[A-Za-z0-9_.-]+(?:[\\/][^\s\x00-\x1f\"'<>|`;,(){}\[\]]*)?)", re.I),
    re.compile(r"(?<![\\])(\\\\[A-Za-z0-9][A-Za-z0-9_.-]*\\(?!\\)[^\s\x00-\x1f\"'<>|`;,(){}\[\]]+)"),
    re.compile(r"(/m[n]t/[a-z]/[^\s\x00-\x1f\"'<>|`;,(){}\[\]]+)", re.I),
    re.compile(r"((?<![A-Za-z0-9_])App[D]ata[\\/][^\s\x00-\x1f\"'<>|`;,(){}\[\]]+)", re.I),
)
# Offset decoding of opposite-endian text can omit the first URI character.
URL = re.compile(r"(?:h?ttps?|r?es|u?id|u?ser)://[^\s\x00-\x1f\"'<>`]+", re.I)
IDENTITY = re.compile(
    r"(?<![a-z0-9])(?:co[d]ex|clau[d]e|chat[g]pt|[g]pt|[s]ol|"
    r"open[a]i|anthro[p]ic|copi[l]ot)(?![a-z0-9])", re.I)
LINE_START = r"(?:^|[\x00\r\n])[\t ]*"
TRAILER = re.compile(LINE_START + r"co-authored" + r"-by\s*:", re.I | re.M)
GENERATED = re.compile(LINE_START + r"generated" + r"\s+with\b[^\r\n]*", re.I | re.M)
AUTHOR = re.compile(r"(?:^|[\x00\r\n])[\t ]*(?:(?:author|committer)\s*:\s*)?([^<>\x00\r\n]{1,120}<[^<>\s\x00]+@[^<>\s\x00]+>)[\t ]*(?=$|[\x00\r\n])", re.I | re.M)


def decoded_texts(data):
    yield data.decode("latin-1")
    # Wide strings in native files need not start on an even byte.
    for encoding in ("utf-16le", "utf-16be"):
        for offset in (0, 1):
            if len(data) > offset:
                yield data[offset:len(data) - (len(data) - offset) % 2].decode(encoding, "replace")


def inspect_local_paths(data, native=False):
    for index, text in enumerate(decoded_texts(data)):
        text = URL.sub("", text)
        for pattern in PATH_PATTERNS:
            if index or native:
                # Mixed native bytes can decode to a letter before a wide path.
                pattern = re.compile(pattern.pattern.replace("(?<![A-Za-z0-9_])", ""), pattern.flags)
            for match in pattern.finditer(text):
                value = re.sub(r"[\\/]+", "/", match.group(1)).lower().strip().rstrip(".,;")
                if value in GENERIC_PATHS or value.startswith("c:/path/to/"):
                    continue
                return ["identifying local path bytes"]
    return []


def inspect_attribution(data, native=False):
    for index, text in enumerate(decoded_texts(data)):
        for pattern, problem in ((TRAILER, "prohibited contributor trailer"),
                                 (GENERATED, "prohibited automated generation credit")):
            if index or native:
                pattern = re.compile(pattern.pattern.removeprefix(LINE_START), pattern.flags)
            if pattern.search(text):
                return [problem]
        if any(IDENTITY.search(match.group(1)) for match in AUTHOR.finditer(text)):
            return ["prohibited automated contributor identity"]
    return []


def inspect_commit(author, committer, message):
    problems = inspect_local_paths((author + "\n" + committer + "\n" + message).encode("utf-8"))
    if IDENTITY.search(author) or IDENTITY.search(committer):
        problems.append("prohibited automated author or committer identity")
    problems.extend(inspect_attribution(message.encode("utf-8")))
    return problems
