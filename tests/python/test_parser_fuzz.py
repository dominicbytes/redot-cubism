# SPDX-License-Identifier: MIT
"""Pure-Python checks of fuzz corpus, replay, contracts and child supervision."""

import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests/fuzz"))
sys.path.insert(0, str(ROOT / "tools"))
from corpus import TARGETS, _nodes, boundary_cases, cases  # noqa: E402
from run_parser_fuzz import validate_snapshot  # noqa: E402
import supervision  # noqa: E402


class CorpusChecks(unittest.TestCase):
    def test_regular_corpus_is_replayable_and_covers_each_target(self):
        first = cases()
        self.assertEqual(first, cases())
        self.assertEqual(len(first), 96)
        self.assertEqual(len({case["id"] for case in first}), 96)
        for target in TARGETS:
            self.assertEqual(sum(case["target"] == target for case in first), 16)
        self.assertNotEqual(first, cases(17))
        self.assertTrue({"truncation", "random_utf8", "deep_nesting", "numeric_extreme",
                         "duplicate_keys", "unicode_normalization", "path_separator_traversal",
                         "duplicate_dependencies", "typed_or_long_keys"} <= {case["category"] for case in first})
        for case in first:
            self.assertLessEqual(len(json.dumps(case, ensure_ascii=False).encode("utf-8")), 64 * 1024)

    def test_explicit_boundaries_are_exact(self):
        selected = boundary_cases()
        self.assertEqual(len(selected), 12)
        self.assertEqual([len(case["payload"].encode("utf-8")) for case in selected[:2]],
                         [4 * 1024 * 1024 - 1, 4 * 1024 * 1024 + 1])
        self.assertEqual([len(json.loads(case["payload"])["Future"]) for case in selected[2:4]], [4096, 4097])
        self.assertEqual([_nodes(json.loads(case["payload"])) for case in selected[6:8]], [65536, 65537])
        for case, depth in zip(selected[4:6], (31, 32)):
            value = json.loads(case["payload"])["Future"]
            for _ in range(depth):
                value = value[0] if isinstance(value, list) else value["child"]
            self.assertEqual(value, "leaf")
        counts = []
        for case in selected[8:10]:
            files = json.loads(case["payload"])["FileReferences"]
            counts.append(1 + len(files["Textures"]) + sum(len(group) for group in files["Motions"].values()))
        self.assertEqual(counts, [4096, 4097])
        self.assertEqual(bytes.fromhex(selected[-2]["binary_hex"]), b'{"x":"\xc3"}')
        self.assertEqual(selected[-1]["target"], "options")
        self.assertEqual(len(selected[-1]["entries"][0][1]), 2 * 1024 * 1024)

    def test_public_fixtures_and_minimal_positive_controls(self):
        selected = cases()
        self.assertEqual(selected[1]["payload"], (ROOT / "tests/abi/project/hero.model3.json").read_text())
        self.assertEqual(selected[2]["payload"], (ROOT / "tests/abi/project/ordinary.json").read_text())
        self.assertTrue(all(selected[index]["expect_ok"] for index in (0, 16, 32, 48)))
        self.assertTrue(all(case["expect_ok"] for case in selected if case["target"] == "dedup"))
        options = [case for case in selected if case["target"] == "options"]
        self.assertEqual(options[1]["entries"], [["string", "rendering/mask_quality", 0, "int"]])
        self.assertEqual(options[2]["entries"], [["string_name", "rendering/mask_quality", 2, "int"]])
        self.assertEqual(options[4]["entries"], [["string", "rendering/mask_quality", 1e100]])


class ContractChecks(unittest.TestCase):
    def test_rejects_nontext_diagnostic_path_and_oversize_diagnostics(self):
        case = {"target": "options", "expect_stage": "options"}
        snapshot = {"target": "options", "ok": False, "model_present": False,
                    "rejection_stage": "options", "diagnostic_bytes": 8,
                    "diagnostics": [{"path": 42, "message": "bad"}],
                    "contract_errors": ["diagnostic path is not text"]}
        self.assertTrue(any("path" in problem for problem in validate_snapshot(case, snapshot)))
        snapshot["diagnostics"] = [{"path": "x" * (1024 * 1024), "message": "bad"}]
        snapshot["diagnostic_bytes"] = 1024 * 1024 + 1
        self.assertTrue(any("1 MiB" in problem for problem in validate_snapshot(case, snapshot)))
        snapshot["diagnostics"] = [{"path": "x" * 4097, "message": "bad"}]
        snapshot["diagnostic_bytes"] = 4126
        self.assertTrue(any("4096 characters" in problem for problem in validate_snapshot(case, snapshot)))
        snapshot["target"] = "manifest"
        snapshot["contract_errors"] = []
        self.assertEqual(validate_snapshot({"target": "manifest"}, snapshot), [])

    def test_dependency_and_stage_invariants(self):
        manifest = {"target": "dedup", "ok": True, "manifest": {"Version": 3},
                    "dependencies": ["res://a.png", "res://a.png"], "diagnostics": [],
                    "diagnostic_bytes": 2, "contract_errors": []}
        self.assertIn("dependencies are not sorted and unique", validate_snapshot({"target": "dedup"}, manifest))
        options = {"target": "options", "ok": False, "model_present": False,
                   "rejection_stage": "options", "diagnostics": [], "diagnostic_bytes": 2,
                   "contract_errors": []}
        self.assertIn("expected options stage source_missing", validate_snapshot(
            {"target": "options", "expect_stage": "source_missing"}, options))


class SupervisionChecks(unittest.TestCase):
    def test_ready_gate_is_created_only_after_owner_attach(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            ready = root / "ready"
            events = []

            class FakeProcess:
                pid = 12345

                def __init__(self, output=b""):
                    self.stdout = io.BytesIO(output)

                def poll(self):
                    return 0

                def wait(self, timeout=None):
                    return 0

            class FakeOwner:
                actual_limits = {"memory_bytes": supervision.MEMORY_LIMIT}
                assigned = True

                def attach(self, process):
                    self.assert_not_ready()
                    events.append("attached")

                def assert_not_ready(self):
                    if ready.exists():
                        raise AssertionError("worker released before resource limits")

                def peak_bytes(self, process):
                    return 0

                def peak_job_bytes(self):
                    return 0

                def stop(self, process):
                    pass

                def close(self):
                    events.append("closed")

            with patch.object(supervision, "ProcessOwner", FakeOwner), \
                    patch.object(supervision.subprocess, "Popen", return_value=FakeProcess()):
                result = supervision.run_owned(["fake"], cwd=root, env={}, log_path=root / "log",
                                               ready_path=ready)
            self.assertEqual(result["exit_code"], 0)
            self.assertTrue(ready.is_file())
            self.assertEqual(events, ["attached", "closed"])

    def test_parent_log_writer_caps_a_burst_and_stop_prevents_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)

            class FakeProcess:
                pid = 12345

                def __init__(self):
                    self.stdout = io.BytesIO(b"x" * (2 * 1024 * 1024))

                def poll(self):
                    return 0

                def wait(self, timeout=None):
                    return 0

            class FakeOwner:
                actual_limits = {"memory_bytes": supervision.MEMORY_LIMIT}
                assigned = True

                def attach(self, process):
                    pass

                def peak_bytes(self, process):
                    return 0

                def peak_job_bytes(self):
                    return 0

                def stop(self, process):
                    pass

                def close(self):
                    pass

            with patch.object(supervision, "ProcessOwner", FakeOwner), \
                    patch.object(supervision.subprocess, "Popen", return_value=FakeProcess()):
                result = supervision.run_owned(["fake"], cwd=root, env={}, log_path=root / "log")
            self.assertEqual(result["violation"], "log_limit")
            self.assertEqual((root / "log").stat().st_size, supervision.LOG_LIMIT)
            stop = root / "STOP.requested"
            stop.touch()
            with patch.object(supervision.subprocess, "Popen", side_effect=AssertionError("launched")):
                with self.assertRaisesRegex(RuntimeError, "stop requested"):
                    supervision.run_owned(["fake"], cwd=root, env={}, log_path=root / "other", stop_path=stop)


if __name__ == "__main__":
    unittest.main()
