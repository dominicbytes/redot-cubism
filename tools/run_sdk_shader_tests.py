#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare Redot fragment output with the installed SDK's unmodified OpenGL shaders.

Linux requires a working X11/EGL desktop GL context and a C++17 compiler with
EGL/GL headers and libraries. Results stay in the required persistent output
directory, which must permit native execution. No SDK code or model is bundled.
This is fragment/blend parity, not full model or clipping-geometry qualification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, default=os.environ.get("CUBISM_SDK_ROOT"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.sdk_root:
        parser.error("Supply --sdk-root or CUBISM_SDK_ROOT for the licensed local SDK")
    engine = os.environ["REDOT_BIN"]
    version = subprocess.check_output([engine, "--version"], text=True, timeout=10).strip()
    if version != json.loads((ROOT / "DEPENDENCIES.json").read_text())["redot"]["version"]:
        parser.error("REDOT_BIN does not match the pinned Redot version")
    shaders = args.sdk_root.resolve() / "Framework/src/Rendering/OpenGL/Shaders/Standard"
    sdk_files = [shaders / ("FragShaderSrc" + mask + alpha + ".frag")
                 for mask in ("", "Mask", "MaskInverted")
                 for alpha in ("", "PremultipliedAlpha")]
    if not all(path.is_file() for path in sdk_files):
        parser.error("SDK Standard OpenGL shaders are missing")
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="sdk-shaders-", dir=args.output.resolve()))
    project = run / "project"
    target = project / "addons/gd_cubism/res/shader"
    target.mkdir(parents=True)
    source_files = list((ROOT / "demo/addons/gd_cubism/res/shader").glob("*.gdshader"))
    for path in source_files:
        (target / path.name).write_bytes(path.read_bytes())
    driver = ROOT / "tests/native/project/sdk_shader_checks.gd"
    reference = ROOT / "tests/native/sdk_shader_reference.cpp"
    (project / "checks.gd").write_bytes(driver.read_bytes())
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="SDK shader comparison"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    environment = dict(os.environ, EGL_PLATFORM="x11")
    for key in ("CONFIG", "DATA", "CACHE"):
        environment[f"XDG_{key}_HOME"] = str(run / key.lower())
    report = {"status": "FAIL", "run": str(run), "engine_version": version,
              "sdk_shaders": {path.name: digest(path) for path in sdk_files},
              "sources": {str(path.relative_to(ROOT)): digest(path) for path in [*source_files, driver, reference, Path(__file__).resolve()]},
              "checks": []}

    def execute(name, command, stdout_file=None):
        try:
            result = subprocess.run(command, cwd=run, env=environment,
                                    capture_output=True, text=True, timeout=180)
            stdout, stderr, code = result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired as error:
            stdout = error.stdout or b""
            stderr = error.stderr or b""
            if isinstance(stdout, bytes): stdout = stdout.decode("utf-8", errors="replace")
            if isinstance(stderr, bytes): stderr = stderr.decode("utf-8", errors="replace")
            stderr += "\nTimed out after 180 seconds."
            code = 124
        except OSError as error:
            stdout, stderr, code = "", str(error), 1
        (run / (name + ".log")).write_text(stdout + stderr if stdout_file is None else stderr)
        if stdout_file: stdout_file.write_text(stdout)
        ok = code == 0 and not re.search(r"SCRIPT ERROR|ERROR:|WARNING:|crashed", stdout + stderr)
        if name == "redot": ok = ok and "CUBISM_SDK_SHADER_PASS" in stdout
        report["checks"].append({"test": name, "command": command, "exit_code": code, "status": "PASS" if ok else "FAIL"})
        print(name, report["checks"][-1]["status"], flush=True)
        return ok

    ok = execute("compile", [*shlex.split(os.environ.get("CXX", "g++")), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                             str(reference), "-lEGL", "-lGL", "-o", str(run / "reference")])
    if ok:
        ok = execute("sdk", [str(run / "reference"), str(shaders)], run / "cases.json")
    if ok:
        cases = json.loads((run / "cases.json").read_text())["cases"]
        ok = len(cases) == 2016 and {case["premultiplied"] for case in cases} == {False, True}
        report["reference_cases"] = len(cases)
    if ok:
        ok = execute("redot", [engine, "--path", str(project), "--display-driver", "x11", "--rendering-method", "gl_compatibility",
                               "--audio-driver", "Dummy", "--script", "res://checks.gd", "--quit-after", "10000", "--", str(run / "cases.json")])
    if ok:
        pixels = json.loads((run / "redot-shader-report.json").read_text())
        report["pixels"] = pixels
        ok = pixels["cases"] == 2016 and pixels["failed_cases"] == 0 and pixels["maximum_channel_error"] <= 2
    report["status"] = "PASS" if ok else "FAIL"
    (run / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(run / "report.json")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
