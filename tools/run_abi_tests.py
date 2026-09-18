#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""SDK-free Redot ABI/import regression; not a Cubism runtime substitute."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--template", type=Path, help="Exact matching export template; also runs export and clean launch")
    parser.add_argument("--export-mode", choices=["debug", "release"], default="debug")
    args = parser.parse_args()
    if sys.platform not in {"linux", "win32"}:
        parser.error("The initial ABI gate targets Linux and Windows only")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    binary = os.environ.get("REDOT_BIN", "")
    library = Path(os.environ.get("CUBISM_ABI_LIBRARY", ""))
    if not Path(binary).is_file() or not library.is_file():
        parser.error("Set REDOT_BIN and CUBISM_ABI_LIBRARY to the verified editor and built ABI test library")
    pins = json.loads((ROOT / "DEPENDENCIES.json").read_text())
    version = subprocess.check_output([binary, "--version"], text=True, timeout=10).strip()
    if version != pins["redot"]["version"]:
        parser.error(f"Unexpected Redot version: {version}")
    run_root = Path(tempfile.mkdtemp(prefix="abi-", dir=args.output))
    project = run_root / "project"
    source = ROOT / "tests/abi/project"
    # Copy fixture bytes, not host ownership/xattrs or generated import state.
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        if path.is_file() and ".godot" not in relative.parts and path.suffix not in {".import", ".uid"}:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
    destination = project / "bin" / library.name
    destination.parent.mkdir()
    shutil.copyfile(library, destination)
    feature = "windows" if sys.platform == "win32" else "linux"
    (project / "cubism_abi.gdextension").write_text(
        '[configuration]\nentry_symbol="redot_cubism_abi_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n'
        f'[libraries]\n{feature}.x86_64="res://bin/{library.name}"\n')
    env = dict(os.environ)
    for name in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{name}_HOME"] = str(run_root / name.lower())
    checks = []

    def run(name, switches, markers, executable=None, from_export=False):
        command = [executable or binary, "--headless"]
        if not from_export:
            command += ["--path", str(project)]
        command += switches
        try:
            result = subprocess.run(command, cwd=run_root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            text, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired as exc:
            text, code = str(exc), 124
        (run_root / f"{name}.log").write_text(text)
        bad = bool(re.search(r"SCRIPT ERROR|ERROR:|WARNING:|Aborted|Segmentation fault", text))
        passed = code == 0 and not bad and all(marker in text for marker in markers)
        checks.append({"test": name, "exit_code": code, "status": "PASS" if passed else "FAIL", "log": f"{run_root.name}/{name}.log"})
        print(f"{name}: {checks[-1]['status']}")
        if not passed:
            print(text)
        return passed

    success = run("fresh-import", ["--editor", "--import", "--quit-after", "1000"], ["CUBISM_ABI_EDITOR_ENTER", "CUBISM_ABI_EDITOR_EXIT", "CUBISM_ABI_IMPORTED:"])
    if success:
        success = run("runtime", ["--quit-after", "120"], ["CUBISM_ABI_PASS"])
    if success:
        success = run("editor-restart", ["--editor", "--import", "--quit-after", "1000"], ["CUBISM_ABI_EDITOR_ENTER", "CUBISM_ABI_EDITOR_EXIT"])
    if success:
        success = run("runtime-after-restart", ["--quit-after", "120"], ["CUBISM_ABI_PASS"])
    if success:
        before = re.findall(r"CUBISM_ABI_UID:(\d+)", (run_root / "runtime.log").read_text())
        after = re.findall(r"CUBISM_ABI_UID:(\d+)", (run_root / "runtime-after-restart.log").read_text())
        success = bool(before) and before == after
        checks.append({"test": "uid-restart", "status": "PASS" if success else "FAIL"})
    exported = False
    if success and args.template:
        template = args.template.resolve()
        template_version = subprocess.check_output([str(template), "--version"], text=True, timeout=10).strip()
        if template_version != version:
            raise ValueError(f"Template version mismatch: {template_version}")
        export_dir = run_root / "export"
        export_dir.mkdir()
        game = export_dir / ("abi.exe" if feature == "windows" else "abi.x86_64")
        config = ('[preset.0]\nname="ABI"\nplatform="' + ('Windows Desktop' if feature == 'windows' else 'Linux') +
                  '"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter=""\nexclude_filter="addons/import_probe/*"\n'
                  'export_path=""\nscript_export_mode=2\n[preset.0.options]\n'
                  f'custom_template/debug={json.dumps(str(template))}\ncustom_template/release={json.dumps(str(template))}\n'
                  'binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
        (project / "export_presets.cfg").write_text(config)
        # API spike only: a synthetic required-file check precedes invoking export.
        # PR 9 replaces this with the real reachable model dependency validator.
        required = project / "probe.raw"
        def export_probe():
            if not required.is_file():
                raise ValueError("Missing required raw export fixture")
            return run("export", [f"--export-{args.export_mode}", "ABI", str(game)], ["CUBISM_ABI_EXPORT_INJECTED"])

        content = required.read_bytes()
        required.unlink()
        try:
            export_probe()
            rejected = False
        except ValueError:
            rejected = not game.exists()
        checks.append({"test": "missing-input-before-export", "status": "PASS" if rejected else "FAIL"})
        required.write_bytes(content)
        success = rejected and export_probe()
        if success:
            # Deny source-tree fallback: move the entire project before the launch.
            project.rename(run_root / "source-not-available")
            success = run("exported-runtime", ["--quit-after", "120"], ["CUBISM_ABI_PASS"], str(game), True)
            exported = success
    report = {"status": "PASS" if success else "FAIL", "engine_version": version,
              "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(), "checks": checks,
              "cubism_model_tested": False, "export_template_tested": exported, "graphics_tested": False}
    if exported:
        report["template_sha256"] = hashlib.sha256(args.template.read_bytes()).hexdigest()
        report["exported_files"] = {p.relative_to(export_dir).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in export_dir.rglob("*") if p.is_file()}
    (args.output / "abi-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return int(not success)


if __name__ == "__main__":
    sys.exit(main())
