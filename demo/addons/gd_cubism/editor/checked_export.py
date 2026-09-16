#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate, stage, inspect and run a Cubism export before replacing its output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile

from pck_inspection import inspect_pack

HERE = Path(__file__).resolve().parent
MANIFEST = 'cubism-export.json'
MAX_SNAPSHOT_FILES = 100000


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def binary_architecture(path):
    """Identify the supported native executable/library header independently."""
    with path.open('rb') as stream:
        header = stream.read(64)
        if header[:6] == b'\x7fELF\x02\x01' and len(header) == 64:
            return 'x86_64' if struct.unpack_from('<H', header, 18)[0] == 62 else 'unsupported'
        if header[:2] == b'MZ' and len(header) == 64:
            stream.seek(struct.unpack_from('<I', header, 60)[0])
            coff = stream.read(6)
            if coff[:4] == b'PE\0\0' and len(coff) == 6:
                return 'x86_64' if struct.unpack_from('<H', coff, 4)[0] == 0x8664 else 'unsupported'
    raise ValueError('Unsupported native binary: ' + str(path))


def promote(stage, output, previous):
    """Move one complete directory, retaining and restoring the previous build."""
    existed = output.exists()
    if output.is_symlink():
        raise ValueError('Output directory must not be a symlink')
    if existed:
        if not output.is_dir() or (any(output.iterdir()) and not (output / MANIFEST).is_file()):
            raise ValueError('Existing nonempty output is not a managed Cubism export')
        output.rename(previous)
    try:
        stage.rename(output)
    except OSError:
        if existed:
            previous.rename(output)
        raise


def execute(command, log, cwd, env, timeout, marker=None):
    kwargs = {'start_new_session': True} if os.name != 'nt' else {}
    with log.open('wb') as stream:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, **kwargs)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                process.kill()
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise ValueError('Timed out; see ' + str(log))
    text = log.read_text(errors='replace')
    if code != 0 or re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', text) or (marker and marker not in text):
        raise ValueError('Export check failed; see ' + str(log))
    return text


def check_sources(project, hashes):
    for name, digest in hashes.items():
        path = (project / name.removeprefix('res://')).resolve()
        if not name.startswith('res://') or not path.is_relative_to(project) or sha256(path) != digest:
            raise ValueError('Project input changed during checked export: ' + name)


def check_native_build(build, target, mode):
    for key, value in {'platform': target.lower(), 'arch': 'x86_64', 'target': 'template_' + mode}.items():
        if build.get(key) != value:
            raise ValueError('Exported native build ' + key + ' mismatch: expected ' + value + ', got ' + str(build.get(key)))


def stage_identity_editor(editor, probe, target):
    # A Windows parent editor may still hold the original executable open.
    # Removing a hard link to it then fails even after the probe exits.
    if target != 'Windows':
        try:
            os.link(editor, probe)
            return
        except OSError:
            pass
    shutil.copyfile(editor, probe)
    probe.chmod(editor.stat().st_mode)


def copy_project_snapshot(project, snapshot, excluded, output=None):
    """Give child editors their own extension path without copying generated output."""
    excluded = {path.resolve() for path in excluded}
    count = 0

    def fail_walk(error):
        raise error

    for root, directories, files in os.walk(project, onerror=fail_walk, followlinks=False):
        source = Path(root)
        destination = snapshot / source.relative_to(project)
        destination.mkdir(parents=True, exist_ok=True)
        for name in directories[:]:
            path = source / name
            generated = output is not None and source == output.parent and (
                name.startswith('.' + output.name + '.cubism-export-') or name.startswith('.cubism-project-'))
            if path in excluded or generated or (source == project and name in ('.git', '.godot')):
                directories.remove(name)
            elif path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
                raise ValueError('Directory link in checked-export source: ' + str(path))
        for name in files:
            path = source / name
            if path in excluded:
                continue
            resolved = path.resolve(strict=True) if path.is_symlink() else path
            if not resolved.is_relative_to(project):
                raise ValueError('File link escapes checked-export source: ' + str(path))
            if not resolved.is_file():
                raise ValueError('Unsupported checked-export source file: ' + str(path))
            count += 1
            if count > MAX_SNAPSHOT_FILES:
                raise ValueError('Checked-export source exceeds the file-count limit')
            shutil.copy2(resolved, destination / name)
    return count


def checked_export(args):
    project = args.project.resolve(strict=True)
    output = args.output.absolute()
    if output.is_symlink():
        raise ValueError('Output must not be a symlink')
    output = output.resolve()
    if output == project or project.is_relative_to(output):
        raise ValueError('Output cannot replace the project or an ancestor directory')
    if not (project / 'project.godot').is_file():
        raise ValueError('Missing project.godot')
    if args.name in ('', '.', '..') or any(c in args.name for c in '/\\:'):
        raise ValueError('Executable name must be a single filename')
    output.parent.mkdir(parents=True, exist_ok=True)
    lock = output.parent / ('.' + output.name + '.cubism-export.lock')
    lock_fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    private = None
    committed = None
    try:
        os.write(lock_fd, str(os.getpid()).encode())
        work = Path(tempfile.mkdtemp(prefix='.' + output.name + '.cubism-export-', dir=output.parent))
        args.work = work
        (work / '.gdignore').write_text('')
        stage = work / 'build'
        stage.mkdir()
        env = dict(os.environ)
        for kind in ('CONFIG', 'DATA', 'CACHE'):
            path = work / kind.lower()
            path.mkdir()
            env['XDG_' + kind + '_HOME'] = str(path)
        (work / 'cache/fontconfig').mkdir()
        version = execute([args.redot_bin, '--version'], work / 'version.log', work, env, 10).strip()
        private = Path(tempfile.mkdtemp(prefix='.cubism-project-', dir=output.parent))
        (private / '.gdignore').write_text('')
        snapshot = private / 'project'
        count = copy_project_snapshot(project, snapshot, (output, work, private), output=output)
        (work / 'source-project.json').write_text(json.dumps({
            'source': str(project), 'snapshot': str(snapshot), 'copied_files': count,
            'project_sha256': sha256(project / 'project.godot'),
            'presets_sha256': sha256(project / 'export_presets.cfg')}, indent=2) + '\n')
        preflight_file = work / 'preflight.json'
        execute([args.redot_bin, '--headless', '--editor', '--path', str(snapshot), '--quit-after', '10000', '--',
                 '--cubism-preflight', args.preset, str(preflight_file)],
                work / 'preflight.log', work, env, args.timeout, 'CUBISM_EXPORT_PREFLIGHT_PASS')
        preflight = json.loads(preflight_file.read_text())
        if not preflight['ok'] or version != preflight['build']['redot_version']:
            raise ValueError('Preflight failed or editor does not match the native addon')
        preset = preflight['preset']
        target = {'Linux': 'Linux', 'Windows Desktop': 'Windows'}.get(preset['platform'])
        if target != platform.system() or preset['architecture'] != 'x86_64':
            raise ValueError('Checked export needs an x86_64 runner on the target desktop OS')
        if preset['embedded_pck'] or preset['encrypted_pck'] or preset['encrypted_directory']:
            raise ValueError('Checked inspection currently requires an unencrypted, standalone PCK')
        hashes = {'res://project.godot': preset['project_hash'], 'res://export_presets.cfg': preset['presets_hash']}
        hashes.update(preflight['raw_hashes'])
        # Freeze the selected source files as well as the validated raw payload.
        for name in preflight['files']:
            path = (snapshot / name.removeprefix('res://')).resolve()
            if not name.startswith('res://') or not path.is_relative_to(snapshot):
                raise ValueError('Selected export input escapes the project: ' + name)
            hashes.setdefault(name, sha256(path))
        check_sources(snapshot, hashes)
        check_sources(project, hashes)
        name = args.name + ('.exe' if target == 'Windows' and not args.name.lower().endswith('.exe') else '')
        game = stage / name
        execute([args.redot_bin, '--headless', '--path', str(snapshot), '--export-' + args.mode, args.preset, str(game)],
                work / 'export.log', work, env, args.timeout)
        check_sources(snapshot, hashes)
        check_sources(project, hashes)
        if binary_architecture(game) != preset['architecture']:
            raise ValueError('Exported executable architecture mismatch')
        template_version = execute([str(game), '--version'], work / 'template-version.log', stage, env, 10).strip()
        if template_version != version:
            raise ValueError('Exported template version does not match the pinned editor')
        archive = inspect_pack(game.with_suffix('.pck'))
        if archive['engine_version'][:2] != [26, 2]:
            raise ValueError('Exported PCK engine version mismatch')
        for name, digest in preflight['raw_hashes'].items():
            if archive['files'].get(name.removeprefix('res://'), {}).get('sha256') != digest:
                raise ValueError('Exported PCK is missing validated bytes: ' + name)
        if any(p.startswith('addons/gd_cubism/editor/') for p in archive['files']):
            raise ValueError('Editor-only Cubism helpers were included in the game')
        (work / 'archive.json').write_text(json.dumps(archive, indent=2) + '\n')
        # A debug native library can abort in a release template even without
        # constructing a model. Inspect the packaged extension with the matched
        # editor (which supports both addon variants) before launching the game.
        identity_file = work / 'native-identity.json'
        # Exported extension paths resolve beside the executable, so the probe
        # editor must reside beside the staged game, not at its installed path.
        editor = Path(shutil.which(args.redot_bin) or args.redot_bin).resolve(strict=True)
        probe = stage / ('.cubism-identity-editor.exe' if target == 'Windows' else '.cubism-identity-editor')
        if probe.exists():
            raise ValueError('Reserved identity-probe filename is already present in the staged export')
        try:
            stage_identity_editor(editor, probe, target)
            execute([str(probe), '--headless', '--main-pack', str(game.with_suffix('.pck')),
                     '--script', str(HERE / 'export_identity.gd'), '--quit-after', '2', '--', str(identity_file)],
                    work / 'native-identity.log', stage, env, args.timeout, 'CUBISM_EXPORT_IDENTITY_PASS')
        finally:
            probe.unlink(missing_ok=True)
        if preflight['models'] > 0:
            check_native_build(json.loads(identity_file.read_text()), target, args.mode)
        smoke_file = work / 'smoke.json'
        execute([str(game), '--headless', '--script', str(HERE / 'export_smoke.gd'), '--quit-after', '10000', '--',
                 str(preflight_file), str(smoke_file)], work / 'smoke.log', stage, env, args.timeout, 'CUBISM_EXPORTED_SMOKE_PASS')
        smoke = json.loads(smoke_file.read_text())
        if not smoke['ok'] or smoke['models'] != preflight['models']:
            raise ValueError('Exported model smoke failed')
        native = {}
        for path in stage.rglob('*'):
            if path.is_symlink():
                raise ValueError('Unexpected symlink in exported artifacts: ' + str(path))
            if path.is_file() and path.suffix.lower() in ('.so', '.dll'):
                if binary_architecture(path) != preset['architecture']:
                    raise ValueError('Exported library architecture mismatch: ' + str(path))
                native[path.relative_to(stage).as_posix()] = sha256(path)
        if preflight['models'] > 0 and not any('gd_cubism' in name for name in native):
            raise ValueError('Missing exported Cubism native library')
        # This also prevents a later all-resources export from selecting builds
        # when the requested output is a subdirectory of the source project.
        (stage / '.gdignore').write_text('')
        manifest = {'schema': 1, 'status': 'PASS', 'preset': args.preset, 'mode': args.mode,
                    'executable': game.name, 'editor_version': version, 'build': smoke['build'],
                    'models': smoke['models'], 'motions': smoke['motions'], 'expressions': smoke['expressions'],
                    'native_libraries': native,
                    'files': {p.relative_to(stage).as_posix(): sha256(p) for p in stage.rglob('*') if p.is_file()}}
        (stage / MANIFEST).write_text(json.dumps(manifest, indent=2) + '\n')
        check_sources(project, hashes)
        shutil.rmtree(private)
        private = None
        promote(stage, output, work / 'previous')
        committed = {'status': 'PASS', 'output': str(output), 'work': str(work), 'manifest': str(output / MANIFEST)}
        return committed
    finally:
        try:
            if private is not None:
                if private.resolve(strict=True).parent != output.parent or not private.name.startswith('.cubism-project-'):
                    raise ValueError('Refusing to remove an unexpected checked-export snapshot path')
                shutil.rmtree(private)
        finally:
            cleanup_errors = []
            try:
                os.close(lock_fd)
            except OSError as error:
                cleanup_errors.append('close: ' + str(error))
            try:
                lock.unlink()
            except OSError as error:
                cleanup_errors.append('remove: ' + str(error))
            if cleanup_errors:
                warning = ('Export lock cleanup failed at ' + str(lock) + ': ' + '; '.join(cleanup_errors)
                           + '. After this process exits, remove the lock if it remains before exporting again.')
                args.cleanup_warning = warning
                if committed is not None:
                    committed['cleanup_warning'] = warning
                elif sys.exc_info()[0] is None:
                    raise OSError(warning)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--preset', required=True)
    parser.add_argument('--output', type=Path, required=True, help='Directory containing the complete promoted build')
    parser.add_argument('--name', default='game', help='Executable filename')
    parser.add_argument('--mode', choices=['debug', 'release'], default='release')
    parser.add_argument('--redot-bin', default=os.environ.get('REDOT_BIN'))
    parser.add_argument('--timeout', type=int, default=180, help='Wall-clock timeout per engine phase')
    parser.add_argument('--report', type=Path, help='Optional final status JSON for editor/CI callers')
    args = parser.parse_args()
    if not args.redot_bin or args.timeout < 1:
        parser.error('Set REDOT_BIN or --redot-bin and a positive timeout')
    try:
        result = checked_export(args)
    except (OSError, ValueError, KeyError, TypeError) as error:
        result = {'status': 'FAIL', 'error': str(error), 'work': str(getattr(args, 'work', ''))}
        if getattr(args, 'cleanup_warning', None):
            result['cleanup_warning'] = args.cleanup_warning
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
