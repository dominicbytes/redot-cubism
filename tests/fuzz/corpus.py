# SPDX-License-Identifier: MIT
"""Small deterministic, SDK-free inputs for the production parser fuzz gate."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SEED = 0x20_10_C0_B1_5A
TARGETS = ("manifest", "motion", "expression", "path", "dedup", "options")


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def noise(seed, label, length=16):
    alphabet = ("A", "é", "e\u0301", "文", "😀", "Ω", "ß", "\u200d", "中")
    result = []
    for index in range(length):
        digest = hashlib.sha256(f"{seed}:{label}:{index}".encode("ascii")).digest()
        result.append(alphabet[digest[0] % len(alphabet)])
    return "".join(result)


def mutate_json(seed, label, text, replace=False):
    """Insert/replace valid random UTF-8 at a seed-selected JSON byte position."""
    digest = hashlib.sha256(f"{seed}:{label}:offset".encode("ascii")).digest()
    offset = int.from_bytes(digest[:4], "big") % len(text)
    value = noise(seed, label, 8)
    return text[:offset] + value + text[offset + int(replace):]


def nested(depth):
    value = "leaf"
    for index in range(depth):
        value = [value] if index % 2 else {"child": value}
    return value


def manifest(**changes):
    value = {"Version": 3, "FileReferences": {"Moc": "Hero.moc3", "Textures": ["face.png"]}}
    value.update(changes)
    return value


def motion(**changes):
    value = {"Version": 3,
             "Meta": {"Duration": 4, "Fps": 30, "Loop": True, "CurveCount": 1,
                      "TotalSegmentCount": 4, "TotalPointCount": 7, "UserDataCount": 1},
             "Curves": [{"Target": "Parameter", "Id": "Param口",
                         "Segments": [0, 0, 0, 1, 1, 1, 1.25, 0.5, 1.75, 0.25, 2, 0, 2, 3, 1, 3, 4, 0]}],
             "UserData": [{"Time": 2, "Value": "合図"}]}
    value.update(changes)
    return value


def expression(**changes):
    value = {"Type": "Live2D Expression", "Parameters": [{"Id": "Param口", "Value": 0.75}]}
    value.update(changes)
    return value


def cases(seed=DEFAULT_SEED):
    """Return exactly 16 replayable cases per target, in stable order."""
    result = []

    def add(target, category, payload=None, entries=None):
        index = sum(item["target"] == target for item in result)
        case = {"id": f"{target}-{index:02d}", "target": target,
                "category": category, "seed": seed}
        if entries is not None:
            case["entries"] = entries
        else:
            case["payload"] = payload if isinstance(payload, str) else encoded(payload)
        result.append(case)

    public_model = (ROOT / "tests/abi/project/hero.model3.json").read_text(encoding="utf-8")
    public_json = (ROOT / "tests/abi/project/ordinary.json").read_text(encoding="utf-8")
    add("manifest", "canonical_public_test", manifest())
    add("manifest", "public_fixture", public_model)
    add("manifest", "public_fixture", public_json)
    base = encoded(manifest())
    for cut in (1, len(base) // 2):
        add("manifest", "truncation", base[:cut])
    for i in range(2):
        add("manifest", "random_utf8", mutate_json(seed, f"manifest-{i}", base, replace=bool(i)))
    for depth in (30, 36):
        add("manifest", "deep_nesting", manifest(Future=nested(depth)))
    for number in (1e100, -1e100):
        add("manifest", "numeric_extreme", manifest(Layout={"Width": number}))
    add("manifest", "duplicate_keys", '{"Version":3,"Version":4,"FileReferences":{"Moc":"Hero.moc3","Textures":[]}}')
    add("manifest", "duplicate_keys", '{"Version":3,"FileReferences":{"Moc":"Hero.moc3","Moc":"Other.moc3","Textures":[]}}')
    for name in ("é", "e\u0301"):
        value = manifest(); value["FileReferences"]["Moc"] = name + ".moc3"
        add("manifest", "unicode_normalization", value)
    value = manifest(); value["FileReferences"]["Moc"] = "../../escape.moc3"
    add("manifest", "path_traversal", value)

    add("motion", "canonical_public_test", motion())
    base = encoded(motion())
    for cut in (1, len(base) // 2):
        add("motion", "truncation", base[:cut])
    for i in range(2):
        add("motion", "random_utf8", mutate_json(seed, f"motion-{i}", base, replace=bool(i)))
    for depth in (30, 36):
        add("motion", "deep_nesting", motion(Future=nested(depth)))
    for number in (1e100, -1e100, 1e-100):
        value = motion(); value["Meta"]["Duration"] = number
        add("motion", "numeric_extreme", value)
    add("motion", "duplicate_keys", base.replace('"Version":3', '"Version":3,"Version":4', 1))
    add("motion", "duplicate_keys", base.replace('"Duration":4', '"Duration":4,"Duration":0', 1))
    for name in ("é", "e\u0301"):
        value = motion(); value["UserData"][0]["Value"] = name
        add("motion", "unicode_normalization", value)
    for segments in ([], [0, 1, 9, 2, 3]):
        value = motion(); value["Curves"][0]["Segments"] = segments
        add("motion", "malformed_segments", value)

    add("expression", "canonical_public_test", expression())
    base = encoded(expression())
    for cut in (1, len(base) // 2):
        add("expression", "truncation", base[:cut])
    for i in range(2):
        add("expression", "random_utf8", mutate_json(seed, f"expression-{i}", base, replace=bool(i)))
    for depth in (30, 36):
        add("expression", "deep_nesting", expression(Future=nested(depth)))
    for number in (1e100, -1e100, 1e-100):
        value = expression(); value["Parameters"][0]["Value"] = number
        add("expression", "numeric_extreme", value)
    add("expression", "duplicate_keys", base.replace('"Type":"Live2D Expression"', '"Type":"Wrong","Type":"Live2D Expression"', 1))
    add("expression", "duplicate_keys", base.replace('"Value":0.75', '"Value":0.75,"Value":1', 1))
    for name in ("é", "e\u0301"):
        value = expression(); value["Parameters"][0]["Id"] = name
        add("expression", "unicode_normalization", value)
    for blend in ("Screen", 42):
        value = expression(); value["Parameters"][0]["Blend"] = blend
        add("expression", "invalid_blend", value)

    paths = ("Hero.moc3", "sub/../Hero.moc3", "sub\\..\\Hero.moc3", "../../Hero.moc3",
             "..\\..\\Hero.moc3", "/Hero.moc3", "C:\\Hero.moc3", "\\\\server\\Hero.moc3",
             "res://Hero.moc3", "https://host/Hero.moc3", "a//b.moc3", "a/./b.moc3",
             "é.moc3", "e\u0301.moc3", "bad\nname.moc3", "x" * 4096 + ".moc3")
    for path in paths:
        value = manifest(); value["FileReferences"]["Moc"] = path
        add("path", "path_separator_traversal", value)

    for i in range(16):
        name = noise(seed, f"dedup-{i}", 4).replace("\u200d", "A")
        value = manifest()
        value["FileReferences"]["Textures"] = ([f"textures/{name}.png"] * (i % 5 + 1)
                                                  + [f"textures/{i}.png", f"textures/{name}.png"])
        add("dedup", "duplicate_dependencies", value)

    option_sets = [
        [],
        [["string", "rendering/mask_quality", 0, "int"]],
        [["string_name", "rendering/mask_quality", 2, "int"]],
        [["string", "rendering/mask_quality", 3, "int"]],
        [["string", "rendering/mask_quality", 1e100]],
        [["string", "validation/strict_optional_files", 1, "int"]],
        [["string", "motions/import_manifest_motions", []]],
        [["string", "expressions/import", {"child": nested(8)}]],
        [["string", "motions/convert_to_redot_animation", True]],
        [["string", "unknown/" + noise(seed, "option-utf", 32), False]],
        [["string", "x" * 8192, True]],
        [["string_name", "x" * 8192, True]],
        [["int", 42, True]],
        [["bool", True, False]],
        [["string", f"unknown/{i:02d}", False] for i in range(33)],
        [["string", "e\u0301/option", True], ["string", "é/option", False]],
    ]
    for index, entries in enumerate(option_sets):
        add("options", "typed_or_long_keys" if index >= 9 else "option_values", entries=entries)

    for case in result:
        if case["id"] in {"manifest-00", "motion-00", "expression-00", "path-00"} or case["target"] == "dedup":
            case["expect_ok"] = True
        if case["id"] in {"manifest-01", "manifest-02", "path-03", "path-04"}:
            case["expect_ok"] = False
        if case["target"] == "options":
            case["expect_stage"] = "source_missing" if int(case["id"][-2:]) < 3 else "options"
    assert len(result) == 96 and all(sum(item["target"] == target for item in result) == 16 for target in TARGETS)
    return result


def _nodes(value):
    if isinstance(value, dict):
        return 1 + sum(_nodes(key) + _nodes(item) for key, item in value.items())
    if isinstance(value, list):
        return 1 + sum(_nodes(item) for item in value)
    return 1


def _json_at_byte_limit(length):
    prefix = '{"FileReferences":{"Moc":"Hero.moc3","Textures":["face.png"]},"Future":['
    suffix = '],"Version":3}'
    remaining = length - len(prefix) - len(suffix)
    full = (remaining - 3) // 4099
    full_cost = full * 4098 + max(0, full - 1)
    last_length = remaining - full_cost - 3
    assert 0 <= last_length <= 4096
    chunks = ['"' + 'x' * 4096 + '"'] * full + ['"' + 'x' * last_length + '"']
    result = prefix + ','.join(chunks) + suffix
    assert len(result.encode('utf-8')) == length
    return result


def boundary_cases(seed=DEFAULT_SEED):
    """Eleven explicit boundaries beyond the <=64 KiB mutation corpus."""
    result = []

    def add(name, payload=None, expect_ok=None, binary_hex=None):
        case = {"id": "boundary-" + name, "target": "read_utf8" if binary_hex else "manifest",
                "category": "boundary", "seed": seed, "expect_ok": expect_ok}
        if binary_hex is not None:
            case["binary_hex"] = binary_hex
        else:
            case["payload"] = payload if isinstance(payload, str) else encoded(payload)
        result.append(case)

    for length, okay in ((4 * 1024 * 1024 - 1, True), (4 * 1024 * 1024 + 1, False)):
        add(f"json-bytes-{length}", _json_at_byte_limit(length), okay)
    for length, okay in ((4096, True), (4097, False)):
        add(f"string-chars-{length}", manifest(Future="x" * length), okay)
    for depth, okay in ((31, True), (32, False)):
        add(f"depth-{depth + 1}", manifest(Future=nested(depth)), okay)
    baseline_nodes = _nodes(manifest(Future=[]))
    for extra, okay in ((0, True), (1, False)):
        count = 65536 - baseline_nodes + extra
        add(f"nodes-{65536 + extra}", manifest(Future=[0] * count), okay)
    for references, okay in ((4096, True), (4097, False)):
        # One MOC plus 4095/4096 repeated motion references; all file paths
        # are short and dependency dedup stays cheap at this count boundary.
        remaining = references - 1
        groups = {}
        for index in range(8):
            take = min(512, remaining)
            groups[f"G{index}"] = [{"File": "same.motion3.json"}] * take
            remaining -= take
        assert remaining == 0
        value = manifest(); value["FileReferences"]["Textures"] = []
        value["FileReferences"]["Motions"] = groups
        add(f"references-{references}", value, okay)
    add("malformed-utf8-read", expect_ok=False, binary_hex='7b2278223a22c3227d')
    assert len(result) == 11
    return result
