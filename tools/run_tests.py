#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Run the selected implemented suite. Missing required gates never pass."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

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
    parser.add_argument("--sanitizer-runtime", type=Path)
    parser.add_argument("--sanitizer-library", type=Path)
    parser.add_argument("--benchmark-project", type=Path, help="Prepared private project for all eight benchmarks")
    parser.add_argument("--mask-resource", help="Project-local imported resource with at least eight mask compositions")
    parser.add_argument("--motion", default="Cue/0")
    parser.add_argument("--resource", default="res://imported-model.res")
    parser.add_argument("--visual-fixtures", type=Path, help="Private SDK visual reference manifest")
    parser.add_argument("--visual-project", type=Path, help="Prepared project for visual reference models")
    parser.add_argument("--visual-limits", type=Path, help="Reviewed limits for the exact visual fixtures and adapter")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.suite == "public":
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
    elif args.suite == "benchmark":
        if not args.benchmark_project or not args.library or not args.mask_resource or not args.expression:
            parser.error("benchmark requires --benchmark-project, --library, --mask-resource and --expression")
        commands = [[sys.executable, "tools/run_benchmarks.py", "--project", str(args.benchmark_project),
                     "--library", str(args.library), "--mask-resource", args.mask_resource,
                     "--resource", args.resource, "--motion", args.motion, "--expression", args.expression,
                     "--output", str(args.output)]]
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
    for index, command in enumerate(commands):
        start = time.monotonic()
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=2500 if args.suite == "benchmark" else (900 if args.sanitizer_runtime or args.suite == "visual" else 300))
            code, log = result.returncode, result.stdout
        except subprocess.TimeoutExpired:
            code, log = 124, "Test command exceeded the wall-clock limit."
        path = args.output / f"{args.suite}-{index}.log"
        path.write_text(log)
        results.append({"command": command, "exit_code": code, "elapsed_seconds": round(time.monotonic() - start, 3), "log": path.name})
        print(log, end="" if log.endswith("\n") else "\n")
        if code:
            break
    status = "FAIL" if any(r["exit_code"] for r in results) else "PASS"
    (args.output / f"{args.suite}.json").write_text(json.dumps({"suite": args.suite, "status": status, "checks": results, "cubism_model_tests_selected": args.suite in ("native-smoke", "benchmark", "visual")}, indent=2) + "\n")
    return int(status != "PASS")


if __name__ == "__main__":
    sys.exit(main())
