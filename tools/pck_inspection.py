# SPDX-License-Identifier: MIT
"""Compatibility import for the inspector shipped with the addon."""
from pathlib import Path
import runpy

inspect_pack = runpy.run_path(str(Path(__file__).resolve().parents[1] / "demo/addons/gd_cubism/editor/pck_inspection.py"))["inspect_pack"]
