#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "lib/stream_kit.py"
SPEC = importlib.util.spec_from_file_location("stream_kit", MODULE_PATH)
assert SPEC and SPEC.loader
kit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = kit
SPEC.loader.exec_module(kit)


class BoundedValueTest(unittest.TestCase):
    def test_percent_clamps_and_rounds_numeric_input(self) -> None:
        self.assertEqual(kit.bounded_percent(150), 100)
        self.assertEqual(kit.bounded_percent(-3), 0)
        self.assertEqual(kit.bounded_percent(49.5), 50)
        self.assertEqual(kit.bounded_percent(0), 0)

    def test_percent_rejects_non_numeric_bool_and_non_finite(self) -> None:
        for value in (True, False, "50", None, [], float("nan"), float("inf")):
            self.assertIsNone(kit.bounded_percent(value))

    def test_integer_enforces_bounds_and_rejects_junk(self) -> None:
        self.assertEqual(kit.bounded_integer(5, 1, 10), 5)
        self.assertIsNone(kit.bounded_integer(0, 1, 10))
        self.assertIsNone(kit.bounded_integer(11, 1, 10))
        for value in (True, "5", None, float("nan"), float("-inf")):
            self.assertIsNone(kit.bounded_integer(value, 0, 100))

    def test_integer_truncates_fractional_input(self) -> None:
        self.assertEqual(kit.bounded_integer(9.9, 1, 10), 9)


class RunCommandTest(unittest.TestCase):
    def test_returns_stdout_of_successful_command(self) -> None:
        self.assertEqual(kit.run_command(["echo", "hi"]).strip(), "hi")

    def test_returns_empty_string_when_command_is_missing(self) -> None:
        self.assertEqual(kit.run_command(["/nonexistent/definitely-not-here"]), "")

    def test_returns_empty_string_on_timeout(self) -> None:
        self.assertEqual(kit.run_command(["sleep", "5"], timeout=0.05), "")


class AtomicWriteJsonTest(unittest.TestCase):
    def test_writes_compact_json_with_private_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "state" / "cache.json"
            kit.atomic_write_json(path, {"a": 1, "b": [1, 2]}, prefix=".t-")
            text = path.read_text(encoding="utf-8")
            self.assertEqual(text, '{"a":1,"b":[1,2]}\n')
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)

    def test_replaces_existing_file_and_leaves_no_temporaries(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "cache.json"
            kit.atomic_write_json(path, {"v": 1}, prefix=".t-")
            kit.atomic_write_json(path, {"v": 2}, prefix=".t-")
            self.assertEqual(json.loads(path.read_text()), {"v": 2})
            self.assertEqual(sorted(entry.name for entry in Path(root).iterdir()),
                             ["cache.json"])

    def test_unserializable_payload_raises_and_leaves_target_intact(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "cache.json"
            kit.atomic_write_json(path, {"v": 1}, prefix=".t-")
            with self.assertRaises(TypeError):
                kit.atomic_write_json(path, {"v": object()}, prefix=".t-")
            self.assertEqual(json.loads(path.read_text()), {"v": 1})
            self.assertEqual([entry.name for entry in Path(root).iterdir()],
                             ["cache.json"])


class ThrottledValueTest(unittest.TestCase):
    def test_refreshes_immediately_on_first_get(self) -> None:
        value = kit.ThrottledValue(lambda: "fresh", 5.0, initial="stale")
        self.assertEqual(value.get(0.0), "fresh")

    def test_returns_cached_value_inside_interval(self) -> None:
        calls: list[int] = []

        def refresh() -> str:
            calls.append(1)
            return f"v{len(calls)}"

        value = kit.ThrottledValue(refresh, 5.0, initial="")
        self.assertEqual(value.get(0.0), "v1")
        self.assertEqual(value.get(4.9), "v1")
        self.assertEqual(value.get(5.0), "v2")
        self.assertEqual(len(calls), 2)

    def test_failed_refresh_keeps_last_good_value(self) -> None:
        results = iter(["good", None, None])
        value = kit.ThrottledValue(lambda: next(results), 5.0, initial="")
        self.assertEqual(value.get(0.0), "good")
        self.assertEqual(value.get(10.0), "good")

    def test_failed_refresh_consumes_interval_by_default(self) -> None:
        results = iter([None, "late"])
        value = kit.ThrottledValue(lambda: next(results), 5.0, initial="none-yet")
        self.assertEqual(value.get(0.0), "none-yet")
        # Attempt at t=0 counted: no retry until t=5.
        self.assertEqual(value.get(3.0), "none-yet")
        self.assertEqual(value.get(5.0), "late")

    def test_failed_refresh_retries_immediately_when_asked(self) -> None:
        results = iter([None, "second-try"])
        value = kit.ThrottledValue(
            lambda: next(results), 5.0, initial="", retry_failed=True
        )
        self.assertEqual(value.get(0.0), "")
        self.assertEqual(value.get(0.1), "second-try")


class TrailingWindowTest(unittest.TestCase):
    def test_baseline_needs_two_samples(self) -> None:
        window = kit.TrailingWindow(30.0)
        self.assertIsNone(window.baseline())
        window.append(0.0, "a")
        self.assertIsNone(window.baseline())
        window.append(1.0, "b")
        self.assertEqual(window.baseline(), "a")

    def test_keeps_one_sample_older_than_span_as_left_edge(self) -> None:
        window = kit.TrailingWindow(30.0)
        for second in range(0, 40):
            window.append(float(second), second)
        # The left edge sits exactly at the cutoff: a delta against the
        # baseline always spans the full window.
        self.assertEqual(window.baseline(), 9)
        window.append(40.0, 40)
        self.assertEqual(window.baseline(), 10)

    def test_single_stale_sample_is_never_evicted(self) -> None:
        window = kit.TrailingWindow(30.0)
        window.append(0.0, "old")
        window.append(1000.0, "new")
        self.assertEqual(window.baseline(), "old")
        self.assertEqual(len(window), 2)


class StreamingTest(unittest.TestCase):
    def test_stream_paces_emissions_to_the_interval(self) -> None:
        ticks = iter([0.0, 0.3, 1.0, 1.0, 2.0, 2.9])
        emitted: list[object] = []
        sleeps: list[float] = []

        def sleep(seconds: float) -> None:
            sleeps.append(seconds)
            if len(sleeps) == 3:
                raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            kit.stream_json_lines(
                lambda: {"n": len(emitted)},
                1.0,
                clock=lambda: next(ticks),
                sleep=sleep,
                emit=emitted.append,
            )
        self.assertEqual(emitted, [{"n": 0}, {"n": 1}, {"n": 2}])
        # Snapshot latency is absorbed by shortening the sleep.
        for actual, expected in zip(sleeps, [0.7, 1.0, 0.1], strict=True):
            self.assertAlmostEqual(actual, expected)

    def test_run_stream_once_prints_single_compact_line(self) -> None:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = kit.run_stream(lambda: {"a": 1}, once=True, interval=1.0)
        self.assertEqual(code, 0)
        self.assertEqual(buffer.getvalue(), '{"a":1}\n')

    def test_run_stream_maps_shutdown_exceptions_to_exit_codes(self) -> None:
        def broken() -> object:
            raise BrokenPipeError

        def interrupted() -> object:
            raise KeyboardInterrupt

        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(kit.run_stream(broken, once=False, interval=0.01), 0)
            self.assertEqual(
                kit.run_stream(interrupted, once=False, interval=0.01), 130
            )


if __name__ == "__main__":
    unittest.main()
