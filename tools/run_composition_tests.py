#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare flat and ordered viewport composition with direct Cubism shaders.

Requires the pinned Redot editor and real GL graphics, but no SDK or model.
This is a feasibility regression, not public rendering_mode qualification.
"""
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
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", type=int, default=64, help="Square target size, 2–256; stock GL screen copies require both dimensions above 40")
    args = parser.parse_args()
    if not 2 <= args.size <= 256:
        parser.error("Target size must be between 2 and 256")
    engine = os.environ["REDOT_BIN"]
    version = subprocess.check_output([engine, "--version"], text=True, timeout=10).strip()
    if version != json.loads((ROOT / "DEPENDENCIES.json").read_text())["redot"]["version"]:
        parser.error("REDOT_BIN does not match the pinned version")
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="composition-", dir=args.output.resolve()))
    project = run / "project"
    shaders = project / "addons/gd_cubism/res/shader"
    shaders.mkdir(parents=True)
    sources = list((ROOT / "demo/addons/gd_cubism/res/shader").glob("*.gdshader"))
    for path in sources:
        (shaders / path.name).write_bytes(path.read_bytes())
    driver = ROOT / "tests/native/project/renderer_composition_checks.gd"
    (project / "checks.gd").write_bytes(driver.read_bytes())
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Cubism composition regression"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    environment = dict(os.environ)
    for key in ("CONFIG", "DATA", "CACHE"):
        environment[f"XDG_{key}_HOME"] = str(run / key.lower())
    command = [engine, "--path", str(project), "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy"]
    if os.name != "nt": command += ["--display-driver", "x11"]
    command += ["--script", "res://checks.gd", "--quit-after", "10000", "--", str(run / "pixels.json"), str(args.size)]
    try:
        result = subprocess.run(command, cwd=run, env=environment, capture_output=True, text=True, timeout=180)
        log, code = result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired as error:
        log = (error.stdout or b"").decode("utf-8", errors="replace") + (error.stderr or b"").decode("utf-8", errors="replace")
        log += "\nTimed out after 180 seconds."
        code = 124
    (run / "run.log").write_text(log)
    ok = code == 0 and "FALLBACK_COMPOSITION cases=75 ordered_failures=0" in log
    ok = ok and not re.search(r"SCRIPT ERROR|ERROR:|WARNING:|crashed", log)
    pixels = json.loads((run / "pixels.json").read_text()) if (run / "pixels.json").exists() else {}
    ok = ok and len(pixels.get("cases", [])) == 75 and pixels.get("flat_failures", 0) > 0
    report = {"status": "PASS" if ok else "FAIL", "exit_code": code, "run": str(run), "engine_version": version,
              "command": command, "pixels": pixels,
              "source_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in [*sources, driver, Path(__file__).resolve()]}}
    (run / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(log)
    print(run / "report.json")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
