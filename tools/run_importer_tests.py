#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise explicit editor import and record stock compound-suffix discovery."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True, help="Private fixture with declared motions and expressions, such as Haru")
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--template", type=Path, help="Matching template for editor-class isolation checks")
    parser.add_argument("--export-mode", choices=["debug", "release"], default="debug", help="Export mode matching the supplied template")
    parser.add_argument("--dependencies", action="store_true", help="Exercise dependency changes and failed-import recovery")
    parser.add_argument("--graphics", choices=["gl_compatibility", "forward_plus"], help="Graphics backend for live texture reimport checks")
    args = parser.parse_args()
    if args.dependencies and not args.graphics:
        parser.error("Dependency checks require --graphics: the headless renderer does not replace texture pixels")
    engine = os.environ["REDOT_BIN"]
    version = subprocess.check_output([engine, "--version"], text=True, timeout=10).strip()
    if version != json.loads((ROOT / "DEPENDENCIES.json").read_text())["redot"]["version"]:
        parser.error("REDOT_BIN does not match the pinned Redot version")
    if args.template and subprocess.check_output([str(args.template.resolve()), "--version"], text=True, timeout=10).strip() != version:
        parser.error("Template version does not match REDOT_BIN")
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="editor-import-", dir=args.output.resolve()))
    project = run / "project"
    addon = project / "addons/gd_cubism"
    (addon / "bin").mkdir(parents=True)
    (addon / "bin" / args.library.name).write_bytes(args.library.read_bytes())
    library_hash = hashlib.sha256((addon / "bin" / args.library.name).read_bytes()).hexdigest()
    for path in (ROOT / "demo/addons/gd_cubism/res").rglob("*"):
        if path.is_file() and path.suffix not in {".import", ".uid"}:
            target = addon / "res" / path.relative_to(ROOT / "demo/addons/gd_cubism/res")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
    feature = "windows" if os.name == "nt" else "linux"
    (addon / "gd_cubism.gdextension").write_text(
        '[configuration]\nentry_symbol="gd_cubism_library_init"\n'
        'compatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n'
        f'[libraries]\n{feature}.x86_64="res://addons/gd_cubism/bin/{args.library.name}"\n'
        '[icons]\nCubismModelResource="res://addons/gd_cubism/res/icons/cubism_model_resource.svg"\n'
        'GDCubismUserModel="res://addons/gd_cubism/res/icons/cubism_model_resource.svg"\n')
    (project / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Cubism editor import checks"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    # Byte copies also support model sources on shared VM filesystems.
    for path in args.model.parent.rglob("*"):
        if path.is_file() and ".godot" not in path.parts and path.suffix != ".import":
            target = project / "model" / path.relative_to(args.model.parent)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
    model = "res://model/" + args.model.name
    (project / "fixture.json").write_text(json.dumps({"model": model}))
    (project / "hero.json").write_text("{}")
    (project / "not_model3.json.backup").write_text("{}")
    # Install editor-only script after scanning, so runtime projects never parse it.
    env = dict(os.environ)
    for key in ("CONFIG", "DATA", "CACHE"):
        env[f"XDG_{key}_HOME"] = str(run / key.lower())
    checks = []

    def execute(name, switches, marker=None, executable=None, graphics=False, exported=False):
        command = [str(executable or engine)]
        if not exported:
            command += ["--path", str(project)]
        if graphics:
            command += ["--rendering-method", args.graphics, "--audio-driver", "Dummy"]
            if os.name != "nt":
                command += ["--display-driver", "x11"]
        else:
            command += ["--headless"]
        try:
            result = subprocess.run([*command, *switches],
                                    cwd=run, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
            log, code = result.stdout, result.returncode
        except subprocess.TimeoutExpired as exc:
            log = exc.stdout or ""
            if isinstance(log, bytes):
                log = log.decode("utf-8", errors="replace")
            log, code = log + "\n" + str(exc), 124
        (run / (name + ".log")).write_text(log)
        diagnostics = log
        if name == "import-limit":
            diagnostics = re.sub(
                r"EXPECTED_IMPORT_LIMIT_FAILURE_BEGIN.*?EXPECTED_IMPORT_LIMIT_FAILURE_END",
                lambda match: match[0].replace("ERROR: Cubism import failed:", "EXPECTED_IMPORT_LIMIT_FAILURE:").replace(
                    f"ERROR: Error importing '{model}'.", "EXPECTED_ENGINE_IMPORT_LIMIT_FAILURE"),
                log, flags=re.DOTALL)
        if name == "texture-policy":
            diagnostics = re.sub(
                r"EXPECTED_TEXTURE_FAILURE_BEGIN.*?EXPECTED_TEXTURE_FAILURE_END",
                lambda match: match[0].replace("ERROR: Cubism texture import failed:", "EXPECTED_TEXTURE_IMPORT_FAILURE:"),
                log, flags=re.DOTALL)
        if args.dependencies and name == "dependency-changes":
            diagnostics = re.sub(
                r"EXPECTED_DEPENDENCY_FAILURE_BEGIN.*?EXPECTED_DEPENDENCY_FAILURE_END",
                lambda match: match[0].replace("ERROR: Cubism import failed:", "EXPECTED_IMPORT_FAILURE:").replace(
                    f"ERROR: Error importing '{model}'.", "EXPECTED_ENGINE_IMPORT_FAILURE"),
                log, flags=re.DOTALL)
        ok = code == 0 and not re.search(r"SCRIPT ERROR|ERROR:|WARNING:|crashed", diagnostics)
        ok = ok and (marker is None or marker in log)
        if graphics:
            ok = ok and f"CUBISM_DEPENDENCY_GRAPHICS={args.graphics}" in log
        checks.append({"test": name, "status": "PASS" if ok else "FAIL", "exit_code": code})
        print(name, checks[-1]["status"], flush=True)
        if not ok:
            print(log)
        return ok

    ok = execute("fresh-import", ["--editor", "--import", "--quit-after", "1000"])
    automatic = (project / "model" / (args.model.name + ".import")).exists()
    negatives = not any((project / name).exists() for name in ("hero.json.import", "not_model3.json.backup.import"))
    checks.append({"test": "ordinary-files-unclaimed", "status": "PASS" if negatives else "FAIL"})
    ok = ok and negatives
    if ok:
        driver = project / "addons/import_test"
        driver.mkdir()
        editor_script = driver / "checks.gd"
        editor_script.write_bytes((ROOT / "tests/editor/editor_import_checks.gd").read_bytes())
        (driver / "plugin.cfg").write_text('[plugin]\nname="Importer Test"\ndescription="Test driver"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
        project_config = (project / "project.godot").read_text()
        (project / "project.godot").write_text(project_config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/import_test/plugin.cfg")\n')
        ok = execute("explicit-import", ["--editor", "--quit-after", "1000"], "CUBISM_EDITOR_IMPORT_PASS")
        (project / "project.godot").write_text(project_config)
        editor_script.unlink()
        (driver / "plugin.cfg").unlink()
    if ok:
        editor_script.write_bytes((ROOT / "tests/editor/texture_policy_checks.gd").read_bytes())
        (driver / "plugin.cfg").write_text('[plugin]\nname="Texture Policy Test"\ndescription="Test driver"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
        (project / "project.godot").write_text(project_config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/import_test/plugin.cfg")\n')
        ok = execute("texture-policy", ["--editor", "--quit-after", "10000"], "CUBISM_TEXTURE_POLICY_PASS")
        (project / "project.godot").write_text(project_config)
        editor_script.unlink()
        (driver / "plugin.cfg").unlink()
    for phase, script, marker in (
            ("export-graph", "export_graph_checks.gd", "CUBISM_EXPORT_GRAPH_PASS"),
            ("export-validator", "export_validator_checks.gd", "CUBISM_EXPORT_VALIDATOR_PASS"),
            ("model-inspector", "model_inspector_checks.gd", "CUBISM_MODEL_INSPECTOR_PASS"),
            ("import-options", "import_options_checks.gd", "CUBISM_IMPORT_OPTIONS_PASS"),
            ("import-options-restart", "import_options_restart_checks.gd", "CUBISM_IMPORT_OPTIONS_RESTART_PASS"),
            ("import-options-without-cache", "import_options_restart_checks.gd", "CUBISM_IMPORT_OPTIONS_RESTART_PASS"),
            ("import-limit", "import_limit_checks.gd", "CUBISM_IMPORT_LIMIT_PASS")):
        if not ok:
            break
        switches = ["--editor", "--quit-after", "10000"]
        if phase == "import-options-without-cache":
            shutil.rmtree(project / ".godot")
            switches += ["--", "--cleanup-options"]
        editor_script.write_bytes((ROOT / "tests/editor" / script).read_bytes())
        (driver / "plugin.cfg").write_text('[plugin]\nname="Import Options Test"\ndescription="Test driver"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
        (project / "project.godot").write_text(project_config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/import_test/plugin.cfg")\n')
        ok = execute(phase, switches, marker)
        (project / "project.godot").write_text(project_config)
        editor_script.unlink()
        (driver / "plugin.cfg").unlink()
    if ok and args.dependencies:
        editor_script.write_bytes((ROOT / "tests/editor/dependency_tracker_checks.gd").read_bytes())
        (driver / "plugin.cfg").write_text('[plugin]\nname="Dependency Test"\ndescription="Test driver"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
        (project / "project.godot").write_text(project_config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/import_test/plugin.cfg")\n')
        ok = execute("dependency-changes", ["--editor", "--quit-after", "10000"], "CUBISM_DEPENDENCY_TRACKER_PASS", graphics=True)
        (project / "project.godot").write_text(project_config)
        editor_script.unlink()
        (driver / "plugin.cfg").unlink()
        if ok:
            # Preserve mtime to prove hashing, not only EditorFileSystem timestamps.
            manifest = json.loads((project / "model" / args.model.name).read_text())
            dependency = Path("model") / manifest["FileReferences"]["Physics"]
            raw = project / dependency
            for phase in ("dependency-restart", "dependency-without-cache"):
                stamp = raw.stat()
                raw.write_bytes(raw.read_bytes() + b"\n ")
                os.utime(raw, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                (project / "fixture.json").write_text(json.dumps({"model": model, "changed_dependency": "res://" + dependency.as_posix(), "expected_hash": hashlib.sha256(raw.read_bytes()).hexdigest()}))
                if phase == "dependency-without-cache":
                    shutil.rmtree(project / ".godot")
                editor_script.write_bytes((ROOT / "tests/editor/dependency_restart_checks.gd").read_bytes())
                (driver / "plugin.cfg").write_text('[plugin]\nname="Dependency Restart Test"\ndescription="Test driver"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
                (project / "project.godot").write_text(project_config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/import_test/plugin.cfg")\n')
                ok = execute(phase, ["--editor", "--quit-after", "10000"], "CUBISM_DEPENDENCY_RESTART_PASS")
                (project / "project.godot").write_text(project_config)
                editor_script.unlink()
                (driver / "plugin.cfg").unlink()
                if not ok:
                    break
    if ok:
        ok = execute("editor-restart", ["--editor", "--import", "--quit-after", "1000"])
    if ok:
        (project / "imported_resource_checks.gd").write_bytes((ROOT / "tests/native/project/imported_resource_checks.gd").read_bytes())
        ok = execute("runtime-resource", ["--script", "res://imported_resource_checks.gd", "--quit-after", "2"], "CUBISM_IMPORTED_RESOURCE_PASS")
    if ok and args.template:
        ok = execute("template-resource", ["--script", "res://imported_resource_checks.gd", "--quit-after", "2"], "CUBISM_IMPORTED_RESOURCE_PASS", args.template.resolve())
    if ok and args.template:
        (project / "texture_export_checks.gd").write_bytes((ROOT / "tests/native/project/texture_export_checks.gd").read_bytes())
        ok = execute("texture-export-prepare", ["--script", "res://texture_export_checks.gd", "--quit-after", "2", "--", "--prepare"], "CUBISM_TEXTURE_EXPORT_PREPARED")
        if ok:
            (project / "texture_export_scene.tscn").write_text('[gd_scene format=3]\n[node name="TextureTest" type="Node"]\n')
            (project / "project.godot").write_text(project_config.replace('[application]', '[application]\nrun/main_scene="res://texture_export_scene.tscn"'))
            platform = "Windows Desktop" if feature == "windows" else "Linux"
            template = json.dumps(str(args.template.resolve()))
            (project / "export_presets.cfg").write_text(
                f'[preset.0]\nname="Textures"\nplatform="{platform}"\nrunnable=true\nexport_filter="resources"\n'
                'export_files=PackedStringArray("res://imported-model.res", "res://texture_export_checks.gd", "res://imported_resource_checks.gd", "res://texture_export_scene.tscn")\n'
                'include_filter="texture-expected.json"\nexclude_filter="addons/import_test/*"\nexport_path=""\nscript_export_mode=2\n'
                f'[preset.0.options]\ncustom_template/debug={template}\ncustom_template/release={template}\n'
                'binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
            exported = run / "export"
            exported.mkdir()
            game = exported / ("texture_game.exe" if feature == "windows" else "texture_game")
            ok = execute("texture-export", [f"--export-{args.export_mode}", "Textures", str(game)])
            if ok:
                project.rename(run / "source-not-available")
                ok = execute("exported-textures", ["--script", "res://texture_export_checks.gd", "--quit-after", "2"], "CUBISM_TEXTURE_EXPORT_PASS", game, exported=True)
    if ok and args.template:
        ok = execute("exported-model", ["--script", "res://imported_resource_checks.gd", "--quit-after", "2"], "CUBISM_IMPORTED_RESOURCE_PASS", game, exported=True)
    report = {"status": "PASS" if ok else "FAIL", "automatic_discovery": automatic, "engine_version": version,
              "library_sha256": library_hash, "run": str(run), "checks": checks}
    (args.output / "importer-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
