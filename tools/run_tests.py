#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Run the selected implemented suite. Missing required gates never pass."""
import argparse
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

from run_desktop_tests import check_report, export_stages, sha256
from run_benchmarks import SCENARIOS

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", required=True, choices=["public", "abi", "native-smoke", "licensed-desktop", "editor", "visual", "export", "benchmark"])
    parser.add_argument("--output", type=Path, default=Path(os.environ.get("TEST_OUTPUT_DIR", ROOT / ".local-build/test-results")))
    parser.add_argument("--template", type=Path, help="Matching template for ABI or native smoke")
    parser.add_argument("--export-mode", choices=["debug", "release"], default="debug")
    parser.add_argument("--model", type=Path, help="Private model3.json for native smoke")
    parser.add_argument("--expression", help="Known non-neutral fixture expression for native smoke")
    parser.add_argument("--mask-compositions", type=Path, help="Private expected mask-source compositions for native smoke")
    parser.add_argument("--draw-order-oracle", type=Path, help="Private Core-derived dynamic drawable orders")
    parser.add_argument("--normal-blend-overlap", action="store_true", help="Enable overlap oracle for a verified normal-blend fixture")
    parser.add_argument("--fallback-mode", action="append", default=[], choices=["canvas_group", "subviewport"], help="Explicit composition experiment")
    parser.add_argument("--graphics", choices=["gl_compatibility", "forward_plus"], help="Render private native smoke captures")
    parser.add_argument("--library", type=Path, help="Built addon library for native smoke")
    parser.add_argument("--native-report", type=Path, help="Passing native report with its prepared project for editor tests")
    parser.add_argument("--importer-report", type=Path, help="Passing importer report with its prepared project for export tests")
    parser.add_argument("--other-library", type=Path, help="Opposite build variant for export rejection tests")
    parser.add_argument("--sanitizer-runtime", type=Path)
    parser.add_argument("--sanitizer-library", type=Path)
    parser.add_argument("--benchmark-project", type=Path, help="Prepared private project for all eight benchmarks")
    parser.add_argument("--runner-id", default="", help="Stable dedicated benchmark machine label")
    parser.add_argument("--baseline", type=Path, help="Reviewed benchmark report from the same dedicated runner")
    parser.add_argument("--relative-threshold", type=float, help="Reviewed nonnegative benchmark regression fraction")
    parser.add_argument("--mask-resource", help="Project-local imported resource with at least eight mask compositions")
    parser.add_argument("--motion", default="Cue/0")
    parser.add_argument("--resource", default="res://imported-model.res")
    parser.add_argument("--visual-fixtures", type=Path, help="Private SDK visual reference manifest")
    parser.add_argument("--visual-project", type=Path, help="Prepared project for visual reference models")
    parser.add_argument("--visual-limits", type=Path, help="Reviewed limits for the exact visual fixtures and adapter")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    child_reports = []
    if args.suite == "licensed-desktop":
        from run_licensed_tests import main as licensed_main
        return licensed_main(["--output", str(args.output)])
    elif args.suite == "public":
        commands = [[sys.executable, "-m", "unittest", "discover", "-s", "tests/python", "-v"],
                    [sys.executable, "tools/check_restricted_files.py"], ["git", "diff", "--check"]]
    elif args.suite == "abi":
        commands = [[sys.executable, "tools/run_abi_tests.py", "--output", str(args.output)]]
        if args.template:
            commands[0] += ["--template", str(args.template), "--export-mode", args.export_mode]
    elif args.suite == "native-smoke":
        if not args.model or not args.library or not args.expression:
            parser.error("native-smoke requires --model, --library and --expression")
        commands = [[sys.executable, "tools/run_native_tests.py", "--output", str(args.output),
                     "--model", str(args.model.resolve()), "--library", str(args.library.resolve()), "--expression", args.expression]]
        if args.graphics:
            commands[0] += ["--graphics", args.graphics]
        if args.mask_compositions:
            commands[0] += ["--mask-compositions", str(args.mask_compositions.resolve())]
        if args.draw_order_oracle:
            commands[0] += ["--draw-order-oracle", str(args.draw_order_oracle.resolve())]
        if args.normal_blend_overlap:
            commands[0] += ["--normal-blend-overlap"]
        for mode in args.fallback_mode:
            commands[0] += ["--fallback-mode", mode]
        if args.template:
            commands[0] += ["--template", str(args.template.resolve()), "--export-mode", args.export_mode]
        if args.sanitizer_runtime and args.sanitizer_library:
            commands[0] += ["--sanitizer-runtime", str(args.sanitizer_runtime.resolve()), "--sanitizer-library", str(args.sanitizer_library.resolve())]
        elif args.sanitizer_runtime or args.sanitizer_library:
            parser.error("Supply both sanitizer runtime and library")
    elif args.suite in ("editor", "export"):
        required = ("library", "native_report") if args.suite == "editor" else ("library", "importer_report", "other_library", "template")
        for name in required:
            path = getattr(args, name)
            if not path or not path.is_file():
                parser.error(args.suite + " requires an existing --" + name.replace("_", "-"))
            setattr(args, name, path.resolve())
        library_hash = sha256(args.library)
        engine_version = json.loads((ROOT / "DEPENDENCIES.json").read_text())["redot"]["version"]
        prepared_report = args.native_report if args.suite == "editor" else args.importer_report
        try:
            prepared = check_report(prepared_report, library_hash, engine_version)
            if prepared.get("library_sha256") != library_hash or prepared.get("engine_version") != engine_version:
                raise ValueError("Prepared fixture must identify the selected library and pinned engine")
        except (OSError, ValueError) as error:
            parser.error(str(error))
        args.output = Path(tempfile.mkdtemp(prefix=args.suite + "-", dir=args.output.resolve()))
        if args.suite == "editor":
            stages = [("editor", "run_editor_tests.py", ["--native-report", str(args.native_report),
                       "--library", str(args.library)], "editor-report.json")]
        else:
            stages = export_stages(args.library, args.template, args.export_mode, args.importer_report,
                                   args.output / "legacy-bridge/legacy-bridge-report.json", args.other_library)
        commands = []
        for name, tool, switches, filename in stages:
            output = args.output / name
            output.mkdir()
            commands.append([sys.executable, str(ROOT / "tools" / tool), *switches, "--output", str(output)])
            child_reports.append(output / filename)
        print("Suite output: " + str(args.output), flush=True)
    elif args.suite == "benchmark":
        if not args.benchmark_project or not args.library or not args.mask_resource or not args.expression:
            parser.error("benchmark requires --benchmark-project, --library, --mask-resource and --expression")
        if not args.library.is_file() or not (args.benchmark_project / "project.godot").is_file():
            parser.error("benchmark requires an existing library and prepared project.godot")
        if bool(args.baseline) != (args.relative_threshold is not None):
            parser.error("Supply --baseline and --relative-threshold together")
        if args.baseline:
            if not args.baseline.is_file() or not args.runner_id.strip():
                parser.error("Baseline comparison requires an existing --baseline and a nonempty --runner-id")
            if not math.isfinite(args.relative_threshold) or args.relative_threshold < 0:
                parser.error("Relative threshold must be finite and nonnegative")
        library_hash = sha256(args.library)
        engine_version = json.loads((ROOT / "DEPENDENCIES.json").read_text())["redot"]["version"]
        args.output = Path(tempfile.mkdtemp(prefix="benchmark-", dir=args.output.resolve()))
        child_reports = [args.output / "benchmark-report.json"]
        commands = [[sys.executable, "tools/run_benchmarks.py", "--project", str(args.benchmark_project),
                     "--library", str(args.library), "--mask-resource", args.mask_resource,
                     "--resource", args.resource, "--motion", args.motion, "--expression", args.expression,
                     "--runner-id", args.runner_id, "--output", str(args.output)]]
        if args.baseline:
            commands[0] += ["--baseline", str(args.baseline.resolve()), "--relative-threshold", str(args.relative_threshold)]
        print("Suite output: " + str(args.output), flush=True)
    elif args.suite == "visual":
        if not args.visual_project or not args.library or not args.visual_fixtures or not args.visual_limits:
            parser.error("visual requires --visual-project, --library, --visual-fixtures and --visual-limits")
        commands = [[sys.executable, "tools/run_visual_tests.py", "--project", str(args.visual_project),
                     "--library", str(args.library), "--fixtures", str(args.visual_fixtures),
                     "--limits", str(args.visual_limits), "--output", str(args.output)]]
        if args.graphics:
            commands[0] += ["--graphics", args.graphics]
    else:
        print(f"BLOCKED: {args.suite} is not qualified at this stage. It requires the matched SDK, fixture and target runner.", file=sys.stderr)
        return 2
    results = []
    report = {"suite": args.suite, "status": "RUNNING", "checks": results, "release_qualified": False,
              "cubism_model_tests_selected": args.suite in ("native-smoke", "benchmark", "visual", "editor", "export")}
    if child_reports:
        report.update(library_sha256=library_hash, engine_version=engine_version, run=str(args.output))
    destination = args.output / f"{args.suite}.json"
    destination.write_text(json.dumps(report, indent=2) + "\n")
    for index, command in enumerate(commands):
        start = time.monotonic()
        log = ""
        timeout = 2500 if args.suite == "benchmark" else (1800 if child_reports else (900 if args.sanitizer_runtime or args.suite == "visual" else 300))
        try:
            process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=os.name != "nt")
            try:
                log, _ = process.communicate(timeout=timeout)
                code = process.returncode
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, timeout=30)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                log, _ = process.communicate(timeout=30)
                code = 124
                log += "\nTest command exceeded the wall-clock limit.\n"
            if not code and child_reports:
                child = check_report(child_reports[index], library_hash, engine_version)
                if args.suite == "editor" and child.get("graphics") is not True:
                    raise ValueError("Editor suite requires a graphical run")
                if args.suite == "benchmark":
                    if args.baseline:
                        from run_licensed_tests import validate_result
                        validate_result(child_reports[index], "benchmark", library_hash, engine_version)
                    elif (child.get("qualification") != "MEASURED_ONLY" or
                          child.get("library_sha256") != library_hash or
                          child.get("identity", {}).get("engine_version") != engine_version or
                          set(child.get("scenarios", {})) != set(SCENARIOS)):
                        raise ValueError("Expected all eight measured scenarios with matching library and engine")
                    report["qualification"] = child["qualification"]
        except (OSError, ValueError, TypeError, AttributeError, subprocess.TimeoutExpired) as error:
            code = 1
            log += "\n" + str(error) + "\n"
        path = args.output / f"{args.suite}-{index}.log"
        path.write_text(log)
        results.append({"command": command, "exit_code": code, "elapsed_seconds": round(time.monotonic() - start, 3), "log": path.name})
        if child_reports:
            results[-1]["report"] = str(child_reports[index])
        report["status"] = "FAIL" if code else "RUNNING"
        destination.write_text(json.dumps(report, indent=2) + "\n")
        print(log, end="" if log.endswith("\n") else "\n")
        if code:
            break
    status = "FAIL" if any(r["exit_code"] for r in results) else "PASS"
    report["status"] = status
    destination.write_text(json.dumps(report, indent=2) + "\n")
    return int(status != "PASS")


if __name__ == "__main__":
    sys.exit(main())
