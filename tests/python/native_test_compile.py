# SPDX-License-Identifier: MIT
"""Build commands for the small native checks on each supported host."""
import os
from pathlib import Path


def _compiler():
    configured = os.environ.get('CXX')
    if configured:
        return configured
    if os.name == 'nt':
        tools = os.environ.get('VCToolsInstallDir')
        if tools:
            candidate = Path(tools) / 'bin/Hostx64/x64/cl.exe'
            if candidate.is_file():
                return str(candidate)
        return 'cl'
    return 'c++'


def compiler_command(source: Path, output: Path, include: Path):
    compiler = _compiler()
    if os.name == 'nt':
        return [compiler, '/nologo', '/std:c++17', '/EHsc', '/O2', '/W4', '/WX',
                '/DNDEBUG', '/I', str(include), str(source),
                '/Fo:' + str(output.with_suffix('.obj')), '/Fe:' + str(output)]
    return [compiler, '-std=c++17', '-DNDEBUG', '-Wall', '-Wextra', '-Werror',
            '-I', str(include), str(source), '-o', str(output)]
