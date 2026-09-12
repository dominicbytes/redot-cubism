#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
from pathlib import Path
import runpy
import sys

path = Path(__file__).resolve().parents[1] / 'demo/addons/gd_cubism/editor'
sys.path.insert(0, str(path))
runpy.run_path(str(path / 'checked_export.py'), run_name='__main__')
