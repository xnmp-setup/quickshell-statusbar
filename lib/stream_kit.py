"""Shared toolkit for the statusbar stream scripts.

Both `hypr_status_stream.py` and `ai_usage_stream.py` are shaped the same
way: a pure domain core fed by an imperative shell that runs subprocesses,
reads files, throttles expensive refreshes, and prints one compact JSON
object per line on stdout. This module holds that shell so the shape is
written once.

Everything here is deliberately infrastructure — no statusbar domain
knowledge. Domain types (CPU samples, quota windows, workspaces) stay in
the stream modules that own them.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
import time
from collections import deque
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any, Generic, TypeVar

JsonObject = dict[str, Any]
CommandRunner = Callable[[Sequence[str]], str]

T = TypeVar("T")

COMMAND_TIMEOUT_SECONDS = 0.8


# --- untrusted-value coercion -------------------------------------------------


def bounded_percent(value: object) -> int | None:
    """Coerce an untrusted JSON value to an int percent in [0, 100]."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not math.isfinite(numeric):
        return None
    return int(max(0.0, min(100.0, numeric)) + 0.5)


def bounded_integer(value: object, minimum: int, maximum: int) -> int | None:
    """Coerce an untrusted JSON value to an int, or None outside [minimum, maximum]."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if not math.isfinite(numeric):
        return None
    integer = int(numeric)
    return integer if minimum <= integer <= maximum else None


# --- subprocess execution -----------------------------------------------------


def _debug(message: str) -> None:
    # stdout is the data channel; diagnostics are opt-in via STATUSBAR_DEBUG
    # so failures stay silent by default (matching historical behaviour).
    if os.environ.get("STATUSBAR_DEBUG"):
        print(f"stream: {message}", file=sys.stderr)


def run_command(
    command: Sequence[str], *, timeout: float = COMMAND_TIMEOUT_SECONDS
) -> str:
    """Run a command, returning its stdout, or "" on any failure."""
    try:
        return subprocess.run(
            command, check=False, capture_output=True, text=True, timeout=timeout
        ).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        _debug(f"{command[0] if command else '?'}: {error}")
        return ""


# --- durable JSON files -------------------------------------------------------


def atomic_write_json(path: Path, payload: object, *, prefix: str) -> None:
    """Write compact JSON to `path` atomically, private to the user (0600/0700)."""
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary_name = ""
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=prefix,
            delete=False,
        ) as temporary:
            temporary_name = temporary.name
            json.dump(payload, temporary, separators=(",", ":"))
            temporary.write("\n")
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    finally:
        if temporary_name:
            try:
                Path(temporary_name).unlink(missing_ok=True)
            except OSError:
                pass


# --- refresh throttling -------------------------------------------------------


class ThrottledValue(Generic[T]):
    """A cached value refreshed at most once per `interval` seconds.

    `refresh` returning None keeps the previous value. With
    `retry_failed=True` a None result also leaves the timer untouched, so
    the next `get` retries immediately; otherwise the failed attempt still
    consumes the interval (for refreshes too expensive to hammer).
    """

    def __init__(
        self,
        refresh: Callable[[], T | None],
        interval: float,
        *,
        initial: T,
        retry_failed: bool = False,
    ) -> None:
        self.refresh = refresh
        self.interval = interval
        self.value: T = initial
        self.retry_failed = retry_failed
        self.last_attempt = float("-inf")

    def get(self, now: float) -> T:
        if now - self.last_attempt < self.interval:
            return self.value
        fresh = self.refresh()
        if fresh is not None:
            self.value = fresh
            self.last_attempt = now
        elif not self.retry_failed:
            self.last_attempt = now
        return self.value


# --- trailing sample windows --------------------------------------------------


class TrailingWindow(Generic[T]):
    """Timestamped samples covering a trailing span.

    One sample older than the span is retained as the window's left edge,
    so a delta against `baseline()` always spans at least the full window
    once enough history exists.

    Timestamps must come from a monotonic clock: eviction is driven by the
    newest appended timestamp, so a clock that jumps backwards stops
    eviction until it catches up again.
    """

    def __init__(self, span: float) -> None:
        self.span = span
        self._samples: deque[tuple[float, T]] = deque()

    def append(self, timestamp: float, sample: T) -> None:
        self._samples.append((timestamp, sample))
        while (
            len(self._samples) > 1
            and self._samples[1][0] <= timestamp - self.span
        ):
            self._samples.popleft()

    def baseline(self) -> T | None:
        """The oldest sample, or None until a delta is meaningful (<2 samples)."""
        return self._samples[0][1] if len(self._samples) > 1 else None

    def __len__(self) -> int:
        return len(self._samples)


# --- JSON-lines stdout streaming ----------------------------------------------


def emit_line(payload: object) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def stream_json_lines(
    snapshot: Callable[[], object],
    interval: float,
    *,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
    emit: Callable[[object], None] = emit_line,
) -> None:
    """Emit one snapshot per `interval` seconds, absorbing snapshot latency."""
    while True:
        started = clock()
        emit(snapshot())
        sleep(max(0.0, interval - (clock() - started)))


def run_stream(snapshot: Callable[[], object], *, once: bool, interval: float) -> int:
    """CLI tail shared by the stream entry points: emit once or loop forever."""
    if once:
        print(json.dumps(snapshot(), separators=(",", ":")))
        return 0
    try:
        stream_json_lines(snapshot, interval)
    except BrokenPipeError:
        return 0
    except KeyboardInterrupt:
        return 130
    return 0
