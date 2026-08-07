#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Pin the producer side of the Python→QML JSON contract to a shared fixture.

tests/fixtures/stream_contract.json is asserted from both ends: this file
proves the Python streams emit exactly the fixture's structure, and
tests/tst_statusbar.qml proves StatusSanitizer.js accepts the same fixture
without dropping or renaming anything. Together they pin the wire contract;
neither side can drift alone without a test failing.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).parents[1]
sys.path.insert(0, str(REPO / "lib"))

FIXTURE = json.loads((REPO / "tests/fixtures/stream_contract.json").read_text())


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, REPO / f"lib/{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


status = load("hypr_status_stream")
usage = load("ai_usage_stream")

# Emitted only when a terminal client is matched to a live terminal window;
# the QML sanitizer ignores them, so the fixture omits them.
OPTIONAL_CLIENT_KEYS = {"weztermWindowId", "weztermGuiPid", "ghosttyWindowId"}


class HyprSnapshotContractTest(unittest.TestCase):
    def snapshot_from_empty_host(self) -> dict:
        with tempfile.TemporaryDirectory() as root:
            collector = status.StatusCollector(
                proc_root=Path(root) / "proc",
                sys_root=Path(root) / "sys",
                runner=lambda command: "",
                clock=lambda: 100.0,
                theme_path=Path(root) / "theme.lua",
                runtime_root=Path(root),
            )
            return collector.snapshot()

    def test_snapshot_emits_exactly_the_fixture_top_level_and_metric_keys(self) -> None:
        snapshot = self.snapshot_from_empty_host()
        self.assertEqual(set(snapshot), set(FIXTURE["hypr"]))
        self.assertEqual(set(snapshot["metrics"]), set(FIXTURE["hypr"]["metrics"]))

    def test_palette_emits_exactly_the_fixture_keys(self) -> None:
        snapshot = self.snapshot_from_empty_host()
        self.assertEqual(set(snapshot["palette"]), set(FIXTURE["hypr"]["palette"]))

    def test_workspaces_emit_exactly_the_fixture_structure(self) -> None:
        counts = status.agent_counts_by_tty(
            [
                status.AgentProcess("claude", "/dev/pts/2"),
                status.AgentProcess("codex", "/dev/pts/5"),
            ]
        )
        rows = [
            {"window_id": 1, "tab_id": 2, "tty_name": "/dev/pts/2", "title": "claude | task"},
            {"window_id": 1, "tab_id": 5, "tty_name": "/dev/pts/5", "title": "codex | repo"},
        ]
        built = status.build_workspaces(
            [
                {
                    "mapped": True,
                    "hidden": False,
                    "address": "0x1",
                    "class": "org.wezfurlong.wezterm",
                    "title": "[1/2] codex | repo",
                    "workspace": {"id": 1, "name": "dev"},
                    "monitor": 0,
                }
            ],
            [{"id": 0, "name": "DP-2", "activeWorkspace": {"id": 1}}],
            status.wezterm_windows(rows, counts),
        )
        fixture_workspace = FIXTURE["hypr"]["workspaces"][0]
        fixture_client = fixture_workspace["clients"][0]

        self.assertEqual(len(built), 1)
        workspace = built[0]
        self.assertEqual(set(workspace), set(fixture_workspace))
        client = workspace["clients"][0]
        self.assertEqual(set(client) - OPTIONAL_CLIENT_KEYS, set(fixture_client))
        self.assertEqual(
            [set(activity) for activity in client["activities"]],
            [set(activity) for activity in fixture_client["activities"]],
        )
        # Values the fixture pins exactly (icon is machine-dependent).
        for key in ("address", "class", "terminal", "label", "title",
                    "tabs", "claude", "codex", "activities"):
            self.assertEqual(client[key], fixture_client[key], key)
        for key in ("id", "name", "monitor", "claude", "codex"):
            self.assertEqual(workspace[key], fixture_workspace[key], key)


class UsageSnapshotContractTest(unittest.TestCase):
    def test_provider_payload_plus_history_matches_fixture_keys(self) -> None:
        for provider in ("claude", "codex"):
            payload_keys = set(usage.provider_payload(None)) | {"history"}
            self.assertEqual(payload_keys, set(FIXTURE["usage"][provider]))

    def test_populated_payload_matches_fixture_values(self) -> None:
        claude = FIXTURE["usage"]["claude"]
        payload = usage.provider_payload(
            usage.ProviderUsage(
                primary=usage.UsageWindow(
                    used_percent=claude["percent"],
                    resets_at=claude["resetsAt"],
                    window_minutes=claude["windowMinutes"],
                ),
                secondary=usage.UsageWindow(
                    used_percent=claude["secondaryPercent"],
                    resets_at=claude["secondaryResetsAt"],
                    window_minutes=claude["secondaryWindowMinutes"],
                ),
            )
        )
        self.assertEqual(payload, {key: claude[key] for key in payload})

    def test_fixture_history_samples_are_already_canonical(self) -> None:
        for provider in ("claude", "codex"):
            samples = FIXTURE["usage"][provider]["history"]
            self.assertEqual(usage.sanitize_samples(samples), samples)

    def test_snapshot_emits_exactly_the_fixture_providers(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            collector = usage.UsageCollector(
                claude_cache_path=Path(root) / "claude.json",
                codex_fetcher=lambda: None,
                wall_clock=lambda: 1_800_000_000.0,
                monotonic_clock=lambda: 0.0,
                history_path=Path(root) / "history.json",
            )
            snapshot = collector.snapshot()
        self.assertEqual(set(snapshot), set(FIXTURE["usage"]))
        for provider in ("claude", "codex"):
            self.assertEqual(set(snapshot[provider]), set(FIXTURE["usage"][provider]))


if __name__ == "__main__":
    unittest.main()
