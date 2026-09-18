#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Test physical project containment with real, task-owned symlinks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    engine = os.environ["REDOT_BIN"]
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="physical-path-", dir=args.output.resolve()))
    project = run / "project"
    addon = project / "addons/gd_cubism"
    (addon / "bin").mkdir(parents=True)
    (addon / "bin" / args.library.name).write_bytes(args.library.read_bytes())
    feature = "windows" if os.name == "nt" else "linux"
    (addon / "gd_cubism.gdextension").write_text(
        '[configuration]\nentry_symbol="gd_cubism_library_init"\n'
        'compatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n'
        f'[libraries]\n{feature}.x86_64="res://addons/gd_cubism/bin/{args.library.name}"\n')
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Cubism physical path checks"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    (project / "path_checks.gd").write_bytes((ROOT / "tests/native/project/path_checks.gd").read_bytes())
    (project / "json_read_checks.gd").write_bytes((ROOT / "tests/native/project/json_read_checks.gd").read_bytes())
    env = dict(os.environ)
    for name in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{name}_HOME"] = str(run / name.lower())

    def execute(name, switches, marker=None):
        command = [engine, "--headless", "--path", str(project), *switches]
        result = subprocess.run(command, env=env, cwd=run, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, timeout=60)
        (run / f"{name}.log").write_text(result.stdout)
        passed = result.returncode == 0 and not re.search(r"SCRIPT ERROR|ERROR:|WARNING:|crashed", result.stdout)
        passed = passed and (marker is None or marker in result.stdout)
        print(name, "PASS" if passed else "FAIL", flush=True)
        if not passed:
            print(result.stdout)
        return passed

    ok = execute("import", ["--editor", "--import", "--quit-after", "1000"])
    if ok:
        # Build links only after import: these fixtures test native filesystem
        # resolution, not EditorFileSystem's handling of symlinked directories.
        paths = project / "paths"
        paths.mkdir()
        (paths / "inside.txt").write_text("inside")
        (paths / "内部.txt").write_text("unicode")
        outside = run / "outside"
        outside.mkdir()
        (outside / "outside.txt").write_text("outside")
        sibling = run / "project-other"
        sibling.mkdir()
        (sibling / "sibling.txt").write_text("sibling")
        (paths / "inside-link.txt").symlink_to("inside.txt")
        (paths / "outside-link.txt").symlink_to(outside / "outside.txt")
        (paths / "outside-directory").symlink_to(outside, target_is_directory=True)
        (paths / "sibling-link.txt").symlink_to(sibling / "sibling.txt")
        (paths / "dangling-link.txt").symlink_to(outside / "missing.txt")
        (paths / "loop.txt").symlink_to("loop.txt")
        sources = paths / "json"
        sources.mkdir()
        fixtures = {
            "unicode": '{"text":"内部😀"}'.encode(),
            "bom": b"\xef\xbb\xbf{}",
            "double-bom": b"\xef\xbb\xbf\xef\xbb\xbf{}",
            "empty": b"",
            "exact-limit": b" " * (4 * 1024 * 1024),
            "too-large": b" " * (4 * 1024 * 1024 + 1),
            "nul": b'{"text":"a\x00b"}',
            "overlong": b"\xc0\xaf",
            "overlong-three": b"\xe0\x80\xaf",
            "overlong-four": b"\xf0\x80\x80\xaf",
            "surrogate": b"\xed\xa0\x80",
            "too-high": b"\xf4\x90\x80\x80",
            "bad-leader": b"\xff",
            "stray-continuation": b"\x80",
            "truncated": b"\xf0\x9f\x98",
            "bad-continuation": b"\xe2ab",
        }
        for name, content in fixtures.items():
            (sources / (name + ".json")).write_bytes(content)
        ok = execute("paths", ["--script", "res://path_checks.gd", "--quit-after", "2"],
                     "CUBISM_PATH_CHECKS cases=18 failures=0")
        if ok:
            ok = execute("json-reads", ["--script", "res://json_read_checks.gd", "--quit-after", "2"],
                         "CUBISM_JSON_READ_PASS")
    report = {"status": "PASS" if ok else "FAIL", "run": str(run),
              "library_sha256": hashlib.sha256((addon / "bin" / args.library.name).read_bytes()).hexdigest(),
              "script_sha256": hashlib.sha256((project / "path_checks.gd").read_bytes()).hexdigest(),
              "json_read_script_sha256": hashlib.sha256((project / "json_read_checks.gd").read_bytes()).hexdigest(),
              "engine_version": subprocess.check_output([engine, "--version"], text=True, timeout=10).strip(),
              "coverage": "physical filesystem only; not exported virtual resources or concurrent file replacement"}
    (args.output / "physical-path-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
