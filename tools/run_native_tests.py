#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Run private real-model native smoke checks; never package fixtures publicly."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from build_inputs import sha256

ROOT = Path(__file__).resolve().parents[1]


def copy_bytes(source, destination):
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        if path.is_file() and ".godot" not in relative.parts and path.suffix not in {".import", ".uid"}:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="Private output directory")
    parser.add_argument("--model", type=Path, required=True, help="Lawfully provisioned model3.json with motions and expressions")
    parser.add_argument("--expression", required=True, help="Declared expression known to change the fixture's default pose")
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--template", type=Path)
    parser.add_argument("--export-mode", choices=["debug", "release"], default="debug")
    parser.add_argument("--graphics", choices=["gl_compatibility", "forward_plus"], help="Also render and capture on the selected real graphics backend")
    parser.add_argument("--sanitizer-runtime", type=Path, help="Headless ASan Redot built from the pinned engine source")
    parser.add_argument("--sanitizer-library", type=Path, help="Matching addon built with sanitize=address")
    args = parser.parse_args()
    binary = os.environ.get("REDOT_BIN", "")
    if not Path(binary).is_file() or not args.library.is_file() or not args.model.is_file():
        parser.error("Set REDOT_BIN and supply existing library/model files")
    pins = json.loads((ROOT / "DEPENDENCIES.json").read_text())
    version = subprocess.check_output([binary, "--version"], text=True, timeout=10).strip()
    if version != pins["redot"]["version"]:
        parser.error(f"Unexpected Redot version: {version}")
    if bool(args.sanitizer_runtime) != bool(args.sanitizer_library):
        parser.error("Supply both sanitizer runtime and library")
    if args.sanitizer_runtime:
        sanitizer_version = subprocess.check_output([str(args.sanitizer_runtime), "--version"], text=True, timeout=10).strip()
        if sanitizer_version != version.replace(".official.", ".cubism_asan.") or not args.sanitizer_library.is_file():
            parser.error("Sanitizer inputs must match the pinned Redot source and addon")
    refs = json.loads(args.model.read_text())["FileReferences"]
    group = next(iter(refs["Motions"]))
    motion = json.loads((args.model.parent / refs["Motions"][group][0]["File"]).read_text())
    duration = motion["Meta"]["Duration"]
    if not 0 < duration < 60 or not refs.get("Expressions"):
        parser.error("Fixture must have a bounded motion and at least one expression")
    if args.expression not in {expression["Name"] for expression in refs["Expressions"]}:
        parser.error("Expression must be declared by the fixture model")
    args.output.mkdir(parents=True, exist_ok=True)
    run_root = Path(tempfile.mkdtemp(prefix="native-", dir=args.output.resolve()))
    project = run_root / "project"
    copy_bytes(ROOT / "tests/native/project", project)
    copy_bytes(args.model.parent, project / "fixture")
    copy_bytes(ROOT / "demo/addons/gd_cubism/res", project / "addons/gd_cubism/res")
    library_path = project / "addons/gd_cubism/bin" / args.library.name
    library_path.parent.mkdir(parents=True)
    library_path.write_bytes(args.library.read_bytes())
    feature = "windows" if sys.platform == "win32" else "linux"
    (project / "addons/gd_cubism/gd_cubism.gdextension").write_text(
        '[configuration]\nentry_symbol="gd_cubism_library_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n'
        f'[libraries]\n{feature}.x86_64="res://addons/gd_cubism/bin/{args.library.name}"\n')
    (project / "fixture.json").write_text(json.dumps({"model": "res://fixture/" + args.model.name,
        "motion_group": group, "motion_duration": duration, "expression": args.expression}))
    (project / "FIXTURE_NOTICE.txt").write_text("This content uses sample data owned and copyrighted by Live2D Inc.\n")
    env = dict(os.environ)
    for name in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{name}_HOME"] = str(run_root / name.lower())
    checks = []

    def run(name, switches, marker=None, executable=None, graphics=False):
        command = [str(executable or binary)]
        if graphics:
            command += ["--rendering-method", args.graphics]
            if feature == "linux":
                command += ["--display-driver", "x11"]
        else:
            command += ["--headless"]
        if executable is None:
            command += ["--path", str(project)]
        command += switches
        try:
            result = subprocess.run(command, cwd=run_root, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300 if name.endswith("-asan") else 60)
            output, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired as exc:
            output, code = str(exc), 124
        (run_root / f"{name}.log").write_text(output)
        diagnostic_output = output
        if "deltas" in name:
            # This deliberate negative input has one documented debug diagnostic.
            diagnostic_output = diagnostic_output.replace("WARNING: Negative Cubism delta ignored.", "EXPECTED_NEGATIVE_DELTA_WARNING", 1)
        passed = code == 0 and not re.search(r"SCRIPT ERROR|ERROR:|WARNING:|Aborted|Segmentation fault|ERROR: AddressSanitizer|LeakSanitizer", diagnostic_output) and (marker is None or marker in output)
        if graphics and passed:
            actual = re.search(r"^CUBISM_NATIVE_GRAPHICS:(.+)$", output, re.M)
            passed = bool(actual) and json.loads(actual.group(1))["renderer"] == args.graphics
        if passed and "[CSM][I]CubismFramework::StartUp()" in output:
            passed = output.count("[CSM][I]CubismFramework::Initialize() is complete.") == 1 and output.count("[CSM][I]CubismFramework::Dispose() is complete.") == 1
        checks.append({"test": name, "exit_code": code, "status": "PASS" if passed else "FAIL", "log": f"{run_root.name}/{name}.log"})
        print(f"{name}: {checks[-1]['status']}", flush=True)
        if not passed:
            print(output, flush=True)
        return passed

    success = run("fresh-import", ["--editor", "--import", "--quit-after", "1000"], "CUBISM_NATIVE_EDITOR_REGISTERED")
    if success:
        success = run("editor-restart", ["--editor", "--import", "--quit-after", "1000"], "CUBISM_NATIVE_EDITOR_PASS")
    if success:
        success = run("empty-runtime", ["--script", "res://empty_runtime.gd", "--quit-after", "2"], "CUBISM_EMPTY_PASS")
    if success:
        success = run("runtime", ["--quit-after", "120"], "CUBISM_NATIVE_PASS")
    if success:
        success = run("native-processing", ["--fixed-fps", "60", "--quit-after", "600", "--", "--process-checks"], "CUBISM_PROCESS_PASS")
    if success:
        success = run("lifecycle", ["--fixed-fps", "60", "--quit-after", "600", "--", "--lifecycle-checks"], "CUBISM_LIFECYCLE_PASS")
    if success:
        success = run("loading-removal", ["--quit-after", "120", "--", "--loading-checks"], "CUBISM_LOADING_PASS")
    if success:
        success = run("handles", ["--quit-after", "600", "--", "--handle-checks"], "CUBISM_HANDLE_PASS")
    if success:
        success = run("deltas", ["--quit-after", "600", "--", "--delta-checks"], "CUBISM_DELTA_PASS")
    sanitizer_tested = False
    if success and args.sanitizer_runtime:
        library_path.write_bytes(args.sanitizer_library.read_bytes())
        previous_asan = env.get("ASAN_OPTIONS")
        env["ASAN_OPTIONS"] = "detect_leaks=1:abort_on_error=1"
        try:
            success = run("lifecycle-asan", ["--rendering-driver", "dummy", "--path", str(project), "--fixed-fps", "60", "--quit-after", "10000", "--", "--lifecycle-checks", "--cycles=250"], "CUBISM_LIFECYCLE_PASS cycles=250", args.sanitizer_runtime)
            if success:
                success = run("handles-asan", ["--rendering-driver", "dummy", "--path", str(project), "--quit-after", "600", "--", "--handle-checks"], "CUBISM_HANDLE_PASS", args.sanitizer_runtime)
            if success:
                success = run("loading-removal-asan", ["--rendering-driver", "dummy", "--path", str(project), "--quit-after", "120", "--", "--loading-checks"], "CUBISM_LOADING_PASS", args.sanitizer_runtime)
            sanitizer_tested = success
        finally:
            library_path.write_bytes(args.library.read_bytes())
            if previous_asan is None:
                del env["ASAN_OPTIONS"]
            else:
                env["ASAN_OPTIONS"] = previous_asan
    graphics_tested = False
    if success and args.graphics:
        success = run("graphics", ["--quit-after", "120", "--", f"--capture={run_root / 'model.png'}"], "CUBISM_NATIVE_GRAPHICS:", graphics=True)
        graphics_tested = success and (run_root / "model.png").is_file()
        success = success and graphics_tested
    exported = False
    if success and args.template:
        template = args.template.resolve()
        if subprocess.check_output([str(template), "--version"], text=True, timeout=10).strip() != version:
            raise ValueError("Export template version mismatch")
        export_dir = run_root / "export"
        export_dir.mkdir()
        game = export_dir / ("native.exe" if feature == "windows" else "native.x86_64")
        (project / "export_presets.cfg").write_text(
            '[preset.0]\nname="Native"\nplatform="' + ('Windows Desktop' if feature == 'windows' else 'Linux') +
            '"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter="fixture/*,FIXTURE_NOTICE.txt"\nexclude_filter="addons/editor_probe/*"\n'
            'export_path=""\nscript_export_mode=2\n[preset.0.options]\n'
            f'custom_template/debug={json.dumps(str(template))}\ncustom_template/release={json.dumps(str(template))}\n'
            'binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
        success = run("export", [f"--export-{args.export_mode}", "Native", str(game)])
        if success:
            project.rename(run_root / "source-not-available")
            success = run("exported-empty-runtime", ["--script", "res://empty_runtime.gd", "--quit-after", "2"], "CUBISM_EMPTY_PASS", game)
        if success:
            success = run("exported-runtime", ["--quit-after", "120"], "CUBISM_NATIVE_PASS", game)
            for label, flag, marker in [("native-processing", "--process-checks", "CUBISM_PROCESS_PASS"), ("lifecycle", "--lifecycle-checks", "CUBISM_LIFECYCLE_PASS"), ("loading-removal", "--loading-checks", "CUBISM_LOADING_PASS"), ("handles", "--handle-checks", "CUBISM_HANDLE_PASS"), ("deltas", "--delta-checks", "CUBISM_DELTA_PASS")]:
                if success:
                    success = run("exported-" + label, ["--fixed-fps", "60", "--quit-after", "600", "--", flag], marker, game)
            if success and args.graphics:
                success = run("exported-graphics", ["--quit-after", "120", "--", f"--capture={run_root / 'exported-model.png'}"], "CUBISM_NATIVE_GRAPHICS:", game, graphics=True)
                success = success and (run_root / "exported-model.png").is_file()
            exported = success
    report = {"status": "PASS" if success else "FAIL", "engine_version": version, "library_sha256": sha256(args.library),
              "fixture_manifest_sha256": sha256(args.model), "fixture_moc_sha256": sha256(args.model.parent / refs["Moc"]),
              "checks": checks, "real_model_tested": any(c["test"] == "runtime" and c["status"] == "PASS" for c in checks),
              "export_template_tested": exported, "graphics_tested": graphics_tested}
    if args.sanitizer_runtime:
        report["sanitizer"] = {"tested": sanitizer_tested, "runtime_version": sanitizer_version,
            "runtime_sha256": sha256(args.sanitizer_runtime), "library_sha256": sha256(args.sanitizer_library),
            "cycles": 250, "coverage": "instrumented engine, addon and public Framework; proprietary Core is not instrumented"}
    if graphics_tested:
        report["graphics_backend"] = args.graphics
        report["capture_sha256"] = sha256(run_root / "model.png")
        for label in ("graphics", "exported-graphics"):
            log = run_root / f"{label}.log"
            if log.is_file():
                window_cycles = re.search(r"^CUBISM_WINDOW_CYCLES:(.+)$", log.read_text(), re.M)
                if window_cycles:
                    report[label + "_window_cycles"] = json.loads(window_cycles.group(1))
    if exported:
        report["template_sha256"] = sha256(args.template)
        report["exported_files"] = {p.relative_to(export_dir).as_posix(): sha256(p) for p in export_dir.rglob("*") if p.is_file()}
    (args.output / "native-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return int(not success)


if __name__ == "__main__":
    sys.exit(main())
