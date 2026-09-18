#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Bounded, reproducible, SDK-free fuzz gate for production Cubism parser APIs."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/fuzz"))
from corpus import DEFAULT_SEED, boundary_cases, cases, encoded  # noqa: E402
from supervision import (BOUNDARY_TIMEOUT, CAMPAIGN_TIMEOUT, LOG_LIMIT, MEMORY_LIMIT, PREFLIGHT_TIMEOUT,
                         REGULAR_TIMEOUT, RESULT_LIMIT, run_owned)  # noqa: E402


REGULAR_INPUT_LIMIT = 64 * 1024
BOUNDARY_INPUT_LIMIT = 8 * 1024 * 1024
DIAGNOSTIC_BYTES_LIMIT = 1024 * 1024
DIAGNOSTIC_COUNT_LIMIT = 32
ENGINE_DIAGNOSTIC = re.compile(r"(?:^|\n)(?:ERROR:|WARNING:|SCRIPT ERROR:)|CrashHandlerException|Program crashed", re.I)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(["git", "-c", f"safe.directory={ROOT}", "-C", str(ROOT), *args],
                                   text=True).strip()


def command_line():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list-cases", action="store_true", help="Print deterministic case IDs without launching Redot")
    parser.add_argument("--editor", type=Path, help="Pinned actual Redot editor binary (not console wrapper)")
    parser.add_argument("--editor-sha256", help="Expected SHA-256 of the editor binary")
    parser.add_argument("--library", type=Path, help="Private production addon DLL/SO; no SDK models are copied")
    parser.add_argument("--library-sha256", help="Expected SHA-256 of the library")
    parser.add_argument("--variant", choices=("debug", "release"))
    parser.add_argument("--source-ref", help="Expected clean 40-character source commit")
    parser.add_argument("--output", type=Path, help="New private output directory outside the source tree")
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=DEFAULT_SEED)
    parser.add_argument("--case", help="Run one case ID twice for replay")
    args = parser.parse_args()
    if not args.list_cases:
        for name in ("editor", "editor_sha256", "library", "library_sha256", "variant", "source_ref", "output"):
            if getattr(args, name) is None:
                parser.error(f"--{name.replace('_', '-')} is required")
    return args


def selected_cases(seed, case_id):
    result = cases(seed) + boundary_cases(seed)
    if case_id is not None:
        result = [item for item in result if item["id"] == case_id]
        if not result:
            raise ValueError(f"unknown case ID: {case_id}")
    return result


def prepare_project(output, library, variant):
    project = output / f"project-{variant}"
    project.mkdir()
    files = git("ls-files", "-z", "--", "demo/addons/gd_cubism").split("\0")
    for relative in files:
        if not relative:
            continue
        destination = project / relative.removeprefix("demo/")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
    platform = "windows" if os.name == "nt" else "linux"
    extension = "dll" if os.name == "nt" else "so"
    expected_name = f"libgd_cubism.{platform}.{variant}.x86_64.{extension}"
    if library.name != expected_name:
        raise ValueError(f"library filename must be {expected_name}")
    destination = project / "addons/gd_cubism/bin" / expected_name
    destination.parent.mkdir(exist_ok=True)
    shutil.copy2(library, destination)
    descriptor = project / "addons/gd_cubism/gd_cubism.gdextension"
    source_descriptor = descriptor.read_text(encoding="utf-8")
    if variant == "release":
        debug_name = f"libgd_cubism.{platform}.debug.x86_64.{extension}"
        if source_descriptor.count(debug_name) != 1:
            raise RuntimeError("expected exactly one editor-debug descriptor mapping")
        descriptor.write_text(source_descriptor.replace(debug_name, expected_name), encoding="utf-8")
    (project / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="Cubism parser fuzz"\n\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    shutil.copy2(ROOT / "tests/fuzz/worker.gd", project / "fuzz_worker.gd")
    shutil.copy2(ROOT / "tests/fuzz/preflight.gd", project / "fuzz_preflight.gd")
    return project, {"tracked_addon_files": len([item for item in files if item]),
                     "descriptor_sha256": sha(descriptor), "library_sha256": sha(destination)}


def private_env(output, editor):
    profile = output / "profile"
    for name in ("appdata", "localappdata", "temp", "xdg_config", "xdg_cache", "xdg_data"):
        (profile / name).mkdir(parents=True, exist_ok=True)
    return dict(os.environ, APPDATA=str(profile / "appdata"), LOCALAPPDATA=str(profile / "localappdata"),
                TEMP=str(profile / "temp"), TMP=str(profile / "temp"),
                XDG_CONFIG_HOME=str(profile / "xdg_config"), XDG_CACHE_HOME=str(profile / "xdg_cache"),
                XDG_DATA_HOME=str(profile / "xdg_data"), PYTHONUTF8="1",
                REDOT_BIN=str(editor), GODOT_BIN=str(editor))


def validate_snapshot(case, snapshot):
    problems = []
    if not isinstance(snapshot, dict) or snapshot.get("target") != case["target"]:
        return ["missing or mismatched worker snapshot"]
    if snapshot.get("contract_errors"):
        problems.extend(snapshot["contract_errors"])
    diagnostics = snapshot.get("diagnostics")
    if not isinstance(diagnostics, list) or len(diagnostics) > DIAGNOSTIC_COUNT_LIMIT:
        problems.append("diagnostics count/schema")
    else:
        for item in diagnostics:
            if not isinstance(item, dict) or not isinstance(item.get("path"), str) or not isinstance(item.get("message"), str):
                problems.append("diagnostic path/message must be text")
                break
            if case["target"] == "options" and len(item["path"]) > 4096:
                problems.append("import-option diagnostic path exceeds 4096 characters")
        if len(encoded(diagnostics).encode("utf-8")) > DIAGNOSTIC_BYTES_LIMIT:
            problems.append("encoded diagnostics exceed 1 MiB")
    worker_bytes = snapshot.get("diagnostic_bytes")
    if not isinstance(worker_bytes, int) or worker_bytes > DIAGNOSTIC_BYTES_LIMIT:
        problems.append("worker diagnostic bytes exceed 1 MiB")
    if "expect_ok" in case and snapshot.get("ok") is not case["expect_ok"]:
        problems.append(f"expected ok={case['expect_ok']}")
    target = case["target"]
    if target in ("manifest", "path", "dedup") and snapshot.get("ok"):
        dependencies = snapshot.get("dependencies")
        if not isinstance(dependencies, list) or any(not isinstance(item, str) for item in dependencies):
            problems.append("dependencies are not text paths")
        elif dependencies != sorted(set(dependencies)):
            problems.append("dependencies are not sorted and unique")
        elif any(not item.startswith("res://") or ".." in item.split("/")[2:] for item in dependencies):
            problems.append("dependency escaped lexical project root")
        if not isinstance(snapshot.get("manifest"), dict) or not snapshot["manifest"]:
            problems.append("successful manifest missing normalized value")
    if target == "path" and snapshot.get("ok"):
        containment = snapshot.get("containment")
        if not isinstance(containment, list) or any(item.get("status") not in ("file", "missing") for item in containment):
            problems.append("resolved path failed physical containment")
    if target == "motion" and snapshot.get("ok") and not isinstance(snapshot.get("motion"), dict):
        problems.append("successful motion missing typed descriptor values")
    if target == "expression" and snapshot.get("ok") and not isinstance(snapshot.get("expression"), dict):
        problems.append("successful expression missing typed descriptor values")
    if target == "options":
        if snapshot.get("model_present") or snapshot.get("ok"):
            problems.append("missing-source options case reached a model")
        if snapshot.get("rejection_stage") != case["expect_stage"]:
            problems.append(f"expected options stage {case['expect_stage']}")
    if target == "read_utf8" and snapshot.get("ok") is False and snapshot.get("text") != "":
        problems.append("invalid UTF-8 returned decoded text")
    return problems


def run_case(case, replay, *, project, editor, env, output):
    name = f"{case['id']}-r{replay}"
    envelope = output / f"{name}.case.json"
    ready = output / f"{name}.ready"
    result = output / f"{name}.result.json"
    log = output / f"{name}.log"
    if ready.exists() or result.exists() or log.exists():
        raise RuntimeError(f"case output already exists: {name}")
    body = encoded(case).encode("utf-8")
    limit = BOUNDARY_INPUT_LIMIT if case["category"] == "boundary" else REGULAR_INPUT_LIMIT
    if len(body) > limit:
        raise ValueError(f"{case['id']} exceeds {limit}-byte input transport bound")
    envelope.write_bytes(body)
    bytes_path = project / "fuzz_bytes.txt"
    if "binary_hex" in case:
        bytes_path.write_bytes(bytes.fromhex(case["binary_hex"]))
    elif bytes_path.exists():
        bytes_path.unlink()
    command = [str(editor), "--headless", "--path", str(project), "--script", "res://fuzz_worker.gd",
               "--quit-after", "2", "--", str(ready), str(envelope), str(result)]
    timeout = BOUNDARY_TIMEOUT if case["category"] == "boundary" else REGULAR_TIMEOUT
    print(f"FUZZ_START {name} target={case['target']} category={case['category']}", flush=True)
    stats = run_owned(command, cwd=project, env=env, log_path=log, result_path=result,
                      ready_path=ready, stop_path=output / "STOP.requested", timeout=timeout,
                      on_start=lambda pid: print(f"FUZZ_CHILD {name} pid={pid}", flush=True))
    print(f"FUZZ_END {name} pid={stats['pid']} exit={stats['exit_code']} violation={stats['violation']}", flush=True)
    with log.open("rb") as captured:
        raw_log = captured.read(LOG_LIMIT + 1)
    text = raw_log.decode("utf-8", errors="replace")
    problems = []
    if stats["violation"]:
        problems.append(stats["violation"])
    if stats["exit_code"] != 0:
        problems.append(f"child exit {stats['exit_code']}")
    if ENGINE_DIAGNOSTIC.search(text):
        problems.append("engine warning/error/crash diagnostic")
    if log.stat().st_size > LOG_LIMIT:
        problems.append("engine log exceeds cap")
    if "FUZZ_WORKER_DONE" not in text:
        problems.append("worker completion marker absent")
    snapshot = None
    if not result.exists() or result.stat().st_size > RESULT_LIMIT:
        problems.append("worker result missing/oversize")
    else:
        try:
            snapshot = json.loads(result.read_text(encoding="utf-8"))
            problems.extend(validate_snapshot(case, snapshot))
        except (ValueError, UnicodeError) as exc:
            problems.append(f"worker result cannot be decoded: {exc}")
    canonical = encoded(snapshot) if snapshot is not None else ""
    log_size = log.stat().st_size
    result_size = result.stat().st_size if result.exists() else None
    return {"case": case["id"], "replay": replay, "command": command, "case_sha256": sha(envelope),
            "log": log.name, "log_bytes": log_size,
            "log_sha256": sha(log) if log_size <= LOG_LIMIT else None,
            "result": result.name if result.exists() else None, "result_bytes": result_size,
            "result_sha256": sha(result) if result_size is not None and result_size <= RESULT_LIMIT else None,
            "canonical_sha256": hashlib.sha256(canonical.encode("utf-8")).hexdigest() if snapshot is not None else None,
            "problems": problems, "stats": stats}


def main():
    args = command_line()
    selected = selected_cases(args.seed, args.case)
    if args.list_cases:
        for case in selected:
            print(case["id"], case["target"], case["category"])
        return 0
    editor, library, output = args.editor.resolve(), args.library.resolve(), args.output.resolve()
    if os.name == "nt" and editor.name.endswith(".console.exe"):
        raise ValueError("use the actual editor.exe, not its console wrapper")
    if output == ROOT or ROOT in output.parents:
        raise ValueError("private output must be outside the source checkout")
    if output.exists() and any(output.iterdir()):
        raise ValueError("output must be new or empty")
    if not re.fullmatch(r"[0-9a-f]{40}", args.source_ref):
        raise ValueError("--source-ref must be a full lowercase SHA")
    if git("rev-parse", "HEAD") != args.source_ref or git("status", "--porcelain"):
        raise RuntimeError("fuzz source checkout must be clean at the requested commit")
    if sha(editor) != args.editor_sha256.lower() or sha(library) != args.library_sha256.lower():
        raise ValueError("editor or library SHA-256 differs from its pin")
    output.mkdir(parents=True, exist_ok=True)
    project, payload = prepare_project(output, library, args.variant)
    env = private_env(output, editor)
    started = time.monotonic()
    deadline = started + CAMPAIGN_TIMEOUT
    selected_manifest = [{"id": case["id"], "target": case["target"], "category": case["category"],
                          "input_sha256": hashlib.sha256(encoded(case).encode("utf-8")).hexdigest(),
                          "input_bytes": len(encoded(case).encode("utf-8"))} for case in selected]
    report = {"source_ref": args.source_ref, "editor": str(editor), "editor_sha256": sha(editor),
              "library": str(library), "library_sha256": sha(library), "variant": args.variant,
              "seed": args.seed, "cases_selected": len(selected), "replays_per_case": 2,
              "selected_manifest": selected_manifest,
              "selected_manifest_sha256": hashlib.sha256(encoded(selected_manifest).encode("utf-8")).hexdigest(),
              "budgets": {"regular_input_bytes": REGULAR_INPUT_LIMIT, "boundary_input_bytes": BOUNDARY_INPUT_LIMIT,
                          "memory_bytes": MEMORY_LIMIT, "regular_timeout_seconds": REGULAR_TIMEOUT,
                          "boundary_timeout_seconds": BOUNDARY_TIMEOUT, "preflight_timeout_seconds": PREFLIGHT_TIMEOUT,
                          "campaign_timeout_seconds": CAMPAIGN_TIMEOUT,
                          "log_bytes": LOG_LIMIT, "result_bytes": RESULT_LIMIT,
                          "diagnostics_count": DIAGNOSTIC_COUNT_LIMIT,
                          "diagnostic_bytes": DIAGNOSTIC_BYTES_LIMIT},
              "payload": payload, "worker_sha256": sha(ROOT / "tests/fuzz/worker.gd"),
              "preflight_sha256": sha(ROOT / "tests/fuzz/preflight.gd"),
              "corpus_sha256": sha(ROOT / "tests/fuzz/corpus.py"),
              "supervision_sha256": sha(ROOT / "tests/fuzz/supervision.py"),
              "runner_sha256": sha(Path(__file__)), "cases": [], "status": "RUNNING"}
    report_path = output / "fuzz-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    def reserve(seconds):
        if time.monotonic() + seconds > deadline:
            raise RuntimeError("campaign wall-clock budget exhausted before child launch")

    try:
        # The setup-only version command exits too quickly for reliable Job
        # assignment; it still uses the same parent-owned capped output pipe.
        version_log = output / "editor-version.log"
        reserve(REGULAR_TIMEOUT)
        version = run_owned([str(editor), "--version"], cwd=project, env=env,
                            log_path=version_log, stop_path=output / "STOP.requested",
                            timeout=REGULAR_TIMEOUT, job_required=False)
        version_text = version_log.read_text(encoding="utf-8", errors="replace")
        report["editor_version"] = version_text.strip()
        report["version_process"] = version
        if version["exit_code"] != 0 or version["violation"] or "26.2.stable.official.4f5b14aba" not in version_text:
            raise RuntimeError("pinned editor version check failed")
        preflight = [
            ("editor-import", [str(editor), "--headless", "--path", str(project), "--editor", "--import",
                               "--quit-after", "1000"], PREFLIGHT_TIMEOUT, None),
            ("native-classes", [str(editor), "--headless", "--path", str(project), "--script",
                                "res://fuzz_preflight.gd", "--quit-after", "2"], REGULAR_TIMEOUT,
             "FUZZ_PREFLIGHT_PASS"),
        ]
        report["preflight"] = []
        for name, command, timeout, marker in preflight:
            reserve(timeout)
            log = output / f"preflight-{name}.log"
            stats = run_owned(command, cwd=project, env=env, log_path=log,
                              stop_path=output / "STOP.requested", timeout=timeout,
                              on_start=lambda pid: print(f"FUZZ_PREFLIGHT_CHILD {name} pid={pid}", flush=True))
            captured = log.read_bytes()[:LOG_LIMIT + 1].decode("utf-8", errors="replace")
            phase = {"name": name, "command": command, "log": log.name,
                     "log_sha256": sha(log) if log.stat().st_size <= LOG_LIMIT else None,
                     "log_bytes": log.stat().st_size, "stats": stats}
            report["preflight"].append(phase)
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            if stats["violation"] or stats["exit_code"] != 0 or log.stat().st_size > LOG_LIMIT \
                    or ENGINE_DIAGNOSTIC.search(captured) or (marker is not None and marker not in captured):
                raise RuntimeError(f"preflight {name} failed")
        for case in selected:
            if (output / "STOP.requested").exists():
                raise RuntimeError("stop requested")
            if time.monotonic() - started > CAMPAIGN_TIMEOUT:
                raise RuntimeError("campaign wall-clock limit reached")
            entry = {"id": case["id"], "target": case["target"], "category": case["category"],
                     "observations": [], "problems": []}
            report["cases"].append(entry)
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            for replay in (1, 2):
                reserve(BOUNDARY_TIMEOUT if case["category"] == "boundary" else REGULAR_TIMEOUT)
                observation = run_case(case, replay, project=project, editor=editor, env=env, output=output)
                entry["observations"].append(observation)
                report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
                if observation["stats"]["violation"] == "stop_requested":
                    raise RuntimeError("stop requested")
            observations = entry["observations"]
            problems = [problem for observation in observations for problem in observation["problems"]]
            if observations[0]["canonical_sha256"] != observations[1]["canonical_sha256"]:
                problems.append("same-input canonical result is nondeterministic")
            entry["problems"] = problems
            report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            if problems:
                (output / "failure-case.json").write_text(encoded(case), encoding="utf-8")
                report["status"] = "FAIL"
                report["failure_case"] = case["id"]
                break
        else:
            report["status"] = "PASS"
    except (KeyboardInterrupt, OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        report["status"] = "ABORTED"
        report["error"] = repr(exc)
    report["elapsed_seconds"] = round(time.monotonic() - started, 3)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"FUZZ_{report['status']} cases={len(report['cases'])} report={report_path}", flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
