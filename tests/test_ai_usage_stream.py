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

MODULE_PATH = Path(__file__).parents[1] / "lib/ai_usage_stream.py"
sys.path.insert(0, str(MODULE_PATH.parent))

SPEC = importlib.util.spec_from_file_location("ai_usage_stream", MODULE_PATH)
assert SPEC and SPEC.loader
usage = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = usage
SPEC.loader.exec_module(usage)

NOW = 1_800_000_000


class ParsingTest(unittest.TestCase):
    def test_claude_uses_weekly_consumed_quota_as_primary(self) -> None:
        parsed = usage.parse_claude_status(
            {
                "rate_limits": {
                    "five_hour": {
                        "used_percentage": 23.5,
                        "resets_at": NOW + 300,
                    },
                    "seven_day": {
                        "used_percentage": 41.2,
                        "resets_at": NOW + 86_400,
                    },
                }
            }
        )
        self.assertEqual(parsed.primary, usage.UsageWindow(41, NOW + 86_400, 10_080))
        self.assertEqual(
            parsed.secondary, usage.UsageWindow(24, NOW + 300, 300)
        )

    def test_codex_ignores_notifications_and_prefers_named_codex_bucket(self) -> None:
        lines = [
            json.dumps({"id": 0, "result": {"userAgent": "test"}}),
            json.dumps({"method": "remoteControl/status/changed", "params": {}}),
            json.dumps(
                {
                    "id": 1,
                    "result": {
                        "rateLimits": None,
                        "rateLimitsByLimitId": {
                            "codex": {
                                "primary": {
                                    "usedPercent": 65,
                                    "windowDurationMins": 10_080,
                                    "resetsAt": NOW + 600,
                                },
                                "secondary": None,
                            }
                        },
                    },
                }
            ),
        ]
        parsed = usage.parse_codex_messages(lines)
        self.assertEqual(parsed.primary, usage.UsageWindow(65, NOW + 600, 10_080))
        self.assertIsNone(parsed.secondary)

    def test_malformed_null_and_huge_values_are_rejected_or_bounded(self) -> None:
        self.assertIsNone(usage.parse_claude_status(None))
        self.assertIsNone(usage.parse_codex_messages(["not json", "x" * 1_048_577]))
        parsed = usage.parse_codex_result(
            {
                "rateLimits": {
                    "primary": {
                        "usedPercent": 90_000,
                        "resetsAt": usage.MAX_RESET_TIMESTAMP + 1,
                    }
                }
            }
        )
        self.assertIsNone(parsed)


class CacheTest(unittest.TestCase):
    def payload(self, primary_reset: int, secondary_reset: int) -> str:
        return json.dumps(
            {
                "rate_limits": {
                    "five_hour": {
                        "used_percentage": 18,
                        "resets_at": primary_reset,
                    },
                    "seven_day": {
                        "used_percentage": 52,
                        "resets_at": secondary_reset,
                    },
                }
            }
        )

    def test_capture_is_atomic_private_and_expired_windows_disappear(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested/claude.json"
            self.assertTrue(
                usage.capture_claude_status(
                    self.payload(NOW + 60, NOW + 600), path, observed_at=NOW
                )
            )
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(path.read_text())["version"], 2)
            current = usage.read_claude_cache(path, now=NOW)
            self.assertEqual(current.primary.used_percent, 52)
            self.assertEqual(current.primary.window_minutes, 10_080)
            self.assertEqual(current.secondary.used_percent, 18)
            after_hourly_reset = usage.read_claude_cache(path, now=NOW + 61)
            self.assertEqual(after_hourly_reset.primary.used_percent, 52)
            self.assertIsNone(after_hourly_reset.secondary)
            self.assertIsNone(usage.read_claude_cache(path, now=NOW + 601))

    def test_legacy_cache_is_migrated_to_weekly_consumed_quota(self) -> None:
        legacy = {
            "version": 1,
            "observedAt": NOW,
            "usage": {
                "percent": 89,
                "resetsAt": NOW + 60,
                "windowMinutes": 300,
                "secondaryPercent": 60,
                "secondaryResetsAt": NOW + 600,
                "secondaryWindowMinutes": 10_080,
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "claude.json"
            path.write_text(json.dumps(legacy))
            current = usage.read_claude_cache(path, now=NOW)
            self.assertEqual(current.primary, usage.UsageWindow(40, NOW + 600, 10_080))
            self.assertEqual(current.secondary, usage.UsageWindow(11, NOW + 60, 300))

    def test_absent_rate_limits_do_not_overwrite_last_good_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "claude.json"
            self.assertTrue(
                usage.capture_claude_status(
                    self.payload(NOW + 60, NOW + 600), path, observed_at=NOW
                )
            )
            before = path.read_text()
            self.assertFalse(usage.capture_claude_status("{}", path, observed_at=NOW))
            self.assertEqual(path.read_text(), before)


class CollectorTest(unittest.TestCase):
    def test_transient_codex_failure_retains_last_good_until_its_reset(self) -> None:
        fetched = iter(
            [
                usage.ProviderUsage(
                    primary=usage.UsageWindow(65, NOW + 600, 10_080)
                ),
                None,
            ]
        )
        clocks = {"wall": float(NOW), "mono": 0.0}
        with tempfile.TemporaryDirectory() as directory:
            collector = usage.UsageCollector(
                claude_cache_path=Path(directory) / "missing.json",
                codex_fetcher=lambda: next(fetched),
                wall_clock=lambda: clocks["wall"],
                monotonic_clock=lambda: clocks["mono"],
                codex_refresh_interval=300,
                history_path=Path(directory) / "history.json",
            )
            self.assertEqual(collector.snapshot()["codex"]["percent"], 65)
            clocks.update(wall=NOW + 301, mono=301)
            self.assertEqual(collector.snapshot()["codex"]["percent"], 65)
            clocks.update(wall=NOW + 601, mono=302)
            self.assertIsNone(collector.snapshot()["codex"]["percent"])

    def test_history_survives_a_restart_and_carries_the_window_edge(self) -> None:
        clocks = {"wall": float(NOW)}
        with tempfile.TemporaryDirectory() as directory:
            history_path = Path(directory) / "history.json"

            def collect() -> object:
                return usage.UsageCollector(
                    claude_cache_path=Path(directory) / "missing.json",
                    codex_fetcher=lambda: usage.ProviderUsage(
                        primary=usage.UsageWindow(
                            int(clocks["wall"] - NOW) // 3600, NOW + 86_400, 300
                        )
                    ),
                    wall_clock=lambda: clocks["wall"],
                    monotonic_clock=lambda: clocks["wall"] - NOW,
                    codex_refresh_interval=0,
                    history_path=history_path,
                )

            collector = collect()
            for hour in range(9):
                clocks["wall"] = NOW + hour * 3600
                collector.snapshot()

            # A fresh process picks the history back up from disk.
            history = collect().snapshot()["codex"]["history"]
            self.assertEqual([sample[1] for sample in history], [1, 2, 3, 4, 5, 6, 7, 8])
            # The reading that was current when the window opened is kept as
            # its left edge, even though it was taken before the window.
            self.assertLess(history[0][0], clocks["wall"] - usage.HISTORY_SPAN_SECONDS)

    def test_unchanged_readings_are_coalesced_but_changes_are_not(self) -> None:
        samples: list[usage.Sample] = []
        for offset in (0, 60, 120, 400):
            samples = usage.append_sample(samples, {"percent": 40}, NOW + offset)
        # Inside the coalescing window an unchanged reading adds nothing.
        self.assertEqual([sample[0] for sample in samples], [NOW, NOW + 400])
        # A change is always recorded immediately.
        samples = usage.append_sample(samples, {"percent": 41}, NOW + 401)
        self.assertEqual(samples[-1], [NOW + 401, 41, None])
        # A reading with no percentage is not a data point.
        self.assertEqual(usage.append_sample(samples, {"percent": None}, NOW + 500), samples)
        # If the clock rewinds, the readings now sitting in the future are
        # dropped and recording continues from the corrected time.
        self.assertEqual(
            usage.append_sample(samples, {"percent": 90}, NOW + 1),
            [[NOW, 40, None], [NOW + 1, 90, None]],
        )

    def test_future_dated_samples_never_wedge_the_series(self) -> None:
        # A clock jump or a stale file can leave readings dated ahead of now.
        # They must not survive, or every later reading looks like the past.
        samples: list[usage.Sample] = [[NOW + 86_400, 90, None]]
        samples = usage.append_sample(samples, {"percent": 40}, NOW)
        self.assertEqual(samples, [[NOW, 40, None]])

    def test_corrupt_history_is_discarded_rather_than_plotted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.json"
            path.write_text("{not json")
            self.assertEqual(usage.read_history(path), {})
            path.write_text(json.dumps({"version": 99, "providers": {"claude": []}}))
            self.assertEqual(usage.read_history(path), {})
            path.write_text(
                json.dumps(
                    {
                        "version": usage.HISTORY_VERSION,
                        "providers": {
                            "claude": [
                                [NOW + 60, 5, 6],
                                [NOW, 4, None],
                                "junk",
                                [NOW + 120, 400, None],
                                [None, 7, 8],
                                [NOW + 180, 9],
                            ]
                        },
                    }
                )
            )
            # Malformed rows drop out; the rest is ordered oldest first and
            # bounded to a real percentage.
            self.assertEqual(
                usage.read_history(path)["claude"],
                [[NOW, 4, None], [NOW + 60, 5, 6], [NOW + 120, 100, None]],
            )

    def test_app_server_request_sequence_is_initialized_before_rate_limit_read(self) -> None:
        requests = usage.codex_requests()
        self.assertEqual(requests[0]["method"], "initialize")
        self.assertEqual(requests[1], {"method": "initialized", "params": {}})
        self.assertEqual(requests[2]["method"], "account/rateLimits/read")


PROVIDER_KEYS = {
    "percent",
    "resetsAt",
    "windowMinutes",
    "secondaryPercent",
    "secondaryResetsAt",
    "secondaryWindowMinutes",
    "history",
}


class CommandLineTest(unittest.TestCase):
    def capture(self, text: str, path: Path) -> int:
        return usage.main(
            ["--capture-claude", "--claude-cache", str(path)],
            stdin_text=lambda: text,
        )

    def test_capture_writes_the_cache_and_reports_success(self) -> None:
        status = json.dumps(
            {
                "rate_limits": {
                    "five_hour": {"used_percentage": 18, "resets_at": NOW + 60},
                    "seven_day": {"used_percentage": 52, "resets_at": NOW + 600},
                }
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache/claude.json"
            self.assertEqual(self.capture(status, path), 0)
            self.assertEqual(json.loads(path.read_text())["usage"]["percent"], 52)

    def test_capture_rejects_malformed_and_oversized_input_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "claude.json"
            self.assertEqual(self.capture("{not json", path), 1)
            self.assertEqual(self.capture("null", path), 1)
            self.assertEqual(
                self.capture("x" * (usage.MAX_INPUT_BYTES + 1), path), 1
            )
            self.assertFalse(path.exists())

    def stub_collector(self, directory: str, **overrides: object):
        def factory(**kwargs: object) -> object:
            return usage.UsageCollector(
                claude_cache_path=Path(directory) / "missing.json",
                codex_fetcher=lambda: usage.ProviderUsage(
                    primary=usage.UsageWindow(65, NOW + 600, 10_080)
                ),
                wall_clock=lambda: float(NOW),
                monotonic_clock=lambda: 0.0,
                history_path=Path(directory) / "history.json",
                **overrides,
            )

        return factory

    def test_once_prints_a_single_line_with_both_providers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = usage.main(
                    ["--once"], collector_factory=self.stub_collector(directory)
                )
        self.assertEqual(code, 0)
        lines = stdout.getvalue().splitlines()
        self.assertEqual(len(lines), 1)
        snapshot = json.loads(lines[0])
        self.assertEqual(set(snapshot), {"claude", "codex"})
        for provider in snapshot.values():
            self.assertEqual(set(provider), PROVIDER_KEYS)
        self.assertEqual(snapshot["codex"]["percent"], 65)

    def test_intervals_are_clamped_to_their_floors(self) -> None:
        calls: dict[str, object] = {}

        def factory(**kwargs: object) -> object:
            calls["codex_refresh_interval"] = kwargs["codex_refresh_interval"]
            cache_path = Path(kwargs["claude_cache_path"])
            return usage.UsageCollector(
                claude_cache_path=cache_path,
                codex_fetcher=lambda: None,
                # Keep the collector away from the developer's real history.
                history_path=cache_path.with_name("history.json"),
            )

        def stream(snapshot: object, *, once: bool, interval: float) -> int:
            calls.update(once=once, interval=interval)
            return 0

        with tempfile.TemporaryDirectory() as directory:
            cache = str(Path(directory) / "claude.json")
            usage.main(
                ["--interval", "0.1", "--codex-refresh-interval", "1", "--claude-cache", cache],
                collector_factory=factory,
                stream=stream,
            )
            self.assertEqual(calls["interval"], usage.MIN_STREAM_INTERVAL)
            self.assertEqual(
                calls["codex_refresh_interval"], usage.MIN_CODEX_REFRESH_INTERVAL
            )
            self.assertFalse(calls["once"])

            usage.main(
                ["--interval", "45", "--codex-refresh-interval", "900", "--claude-cache", cache],
                collector_factory=factory,
                stream=stream,
            )
            # Values above the floor are passed through untouched.
            self.assertEqual(calls["interval"], 45.0)
            self.assertEqual(calls["codex_refresh_interval"], 900.0)


def write_fake_codex(directory: Path, name: str, body: str) -> Path:
    script = directory / name
    script.write_text(f"#!{sys.executable}\nimport signal, sys, time\n{body}\n")
    script.chmod(script.stat().st_mode | stat.S_IXUSR)
    return script


REPLY = json.dumps(
    {
        "id": 1,
        "result": {
            "rateLimits": {
                "primary": {
                    "usedPercent": 42,
                    "windowDurationMins": 10_080,
                    "resetsAt": NOW + 600,
                }
            }
        },
    }
)


class CodexTransportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def test_reply_ends_the_exchange_even_while_the_server_keeps_running(self) -> None:
        script = write_fake_codex(
            self.root,
            "codex-happy",
            "print('{\"method\":\"noise\",\"params\":{}}', flush=True)\n"
            f"print({REPLY!r}, flush=True)\n"
            "time.sleep(30)\n",
        )
        previous = os.environ.get("CODEX_BIN")
        os.environ["CODEX_BIN"] = str(script)
        try:
            parsed = usage.fetch_codex_usage()
        finally:
            if previous is None:
                del os.environ["CODEX_BIN"]
            else:
                os.environ["CODEX_BIN"] = previous
        self.assertEqual(parsed.primary, usage.UsageWindow(42, NOW + 600, 10_080))

    def test_a_server_that_never_answers_is_timed_out_and_shut_down(self) -> None:
        marker = self.root / "terminated"
        script = write_fake_codex(
            self.root,
            "codex-mute",
            f"signal.signal(signal.SIGTERM, lambda *_: (open({str(marker)!r}, 'w').close(), sys.exit(0)))\n"
            "print('partial', flush=True)\n"
            "time.sleep(30)\n",
        )
        # Generous deadline: the fake server is a whole interpreter that must
        # start and print before it; a tight one flakes on cold machines.
        lines = usage.run_codex_app_server(
            usage.codex_requests(), timeout=5.0, command=[str(script)]
        )
        # Whatever arrived before the deadline is still returned...
        self.assertEqual(lines, ["partial"])
        self.assertIsNone(usage.parse_codex_messages(lines))
        # ...and the process is not left behind.
        self.assertTrue(marker.exists())

    def test_a_reply_without_a_trailing_newline_is_still_parsed(self) -> None:
        # A server that flushes the reply and dies before the newline reaches
        # the pipe must still count as an answer (regression: the line-split
        # loop used to drop the unterminated remainder on EOF).
        script = write_fake_codex(
            self.root,
            "codex-noeol",
            f"sys.stdout.write({REPLY!r})\n"
            "sys.stdout.flush()\n",
        )
        lines = usage.run_codex_app_server(
            usage.codex_requests(), timeout=5.0, command=[str(script)]
        )
        parsed = usage.parse_codex_messages(lines)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.primary, usage.UsageWindow(42, NOW + 600, 10_080))

    def test_garbage_output_yields_no_usage(self) -> None:
        script = write_fake_codex(
            self.root,
            "codex-garbage",
            "print('not json', flush=True)\n"
            "print('[1,2,3]', flush=True)\n"
            "print('{\"id\":0,\"result\":{}}', flush=True)\n",
        )
        lines = usage.run_codex_app_server(
            usage.codex_requests(), timeout=5.0, command=[str(script)]
        )
        self.assertEqual(len(lines), 3)
        self.assertIsNone(usage.parse_codex_messages(lines))

    def test_an_oversized_unterminated_line_does_not_hide_the_reply(self) -> None:
        script = write_fake_codex(
            self.root,
            "codex-flood",
            "sys.stdout.write('x' * 2_000_000)\n"
            "sys.stdout.flush()\n"
            f"print('\\n' + {REPLY!r}, flush=True)\n"
            "time.sleep(30)\n",
        )
        lines = usage.run_codex_app_server(
            usage.codex_requests(), timeout=5.0, command=[str(script)]
        )
        parsed = usage.parse_codex_messages(lines)
        self.assertEqual(parsed.primary, usage.UsageWindow(42, NOW + 600, 10_080))

    def test_a_missing_executable_is_not_an_error(self) -> None:
        self.assertEqual(
            usage.run_codex_app_server(
                usage.codex_requests(), command=[str(self.root / "nope")]
            ),
            [],
        )

    def test_only_the_rate_limit_reply_completes_the_exchange(self) -> None:
        self.assertTrue(usage.completes_exchange(REPLY))
        self.assertFalse(usage.completes_exchange('{"id":0,"result":{}}'))
        self.assertFalse(usage.completes_exchange("not json"))
        self.assertFalse(usage.completes_exchange("[1]"))


if __name__ == "__main__":
    unittest.main()
