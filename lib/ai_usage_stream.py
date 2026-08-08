#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Stream Claude Code and Codex quota windows for the Quickshell status bar."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import select
import shutil
import subprocess
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from stream_kit import (
    JsonObject,
    ThrottledValue,
    atomic_write_json,
    bounded_integer,
    bounded_percent,
    debug,
    run_stream,
)

MAX_INPUT_BYTES = 1_048_576
MAX_CACHE_BYTES = 65_536
MAX_RESET_TIMESTAMP = 4_102_444_800  # 2100-01-01 UTC
DEFAULT_STREAM_INTERVAL = 30.0
DEFAULT_CODEX_REFRESH_INTERVAL = 300.0
CLAUDE_CACHE_VERSION = 2
HISTORY_VERSION = 1
# The bar plots quota consumption over this trailing window.
HISTORY_SPAN_SECONDS = 6 * 3600
# Quota percentages are integers that move slowly, so unchanged readings are
# only re-recorded this often. The bar step-interpolates between samples.
HISTORY_MIN_INTERVAL = 300.0
# Bound on retained samples per provider; the span and interval above keep the
# real count far below it, so this only caps a pathological history file.
MAX_HISTORY_SAMPLES = 2_048
MAX_HISTORY_BYTES = 262_144
MIN_STREAM_INTERVAL = 5.0
MIN_CODEX_REFRESH_INTERVAL = 30.0
# The app-server can take a while to authenticate before it answers; past that
# a hung process is worth more than a stalled bar, so we cut it loose.
CODEX_EXCHANGE_TIMEOUT = 12.0
CODEX_SHUTDOWN_WAIT = 1.0
# JSON-RPC id of the request whose reply ends the exchange.
CODEX_RATE_LIMIT_REQUEST_ID = 1
CODEX_EXECUTABLE = "codex"
# The codex CLI installs through node/bun package managers, whose bin
# directories reach PATH via an interactive shell profile. The bar's stream
# inherits the login-session PATH instead, which usually lacks them, so it
# looks in the known install locations itself.
CODEX_SEARCH_GLOBS = (
    ".local/bin/codex",
    ".npm-global/bin/codex",
    ".bun/bin/codex",
    ".volta/bin/codex",
    ".local/share/pnpm/codex",
    ".nvm/versions/node/*/bin/codex",
)

CodexFetcher = Callable[[], "ProviderUsage | None"]


@dataclass(frozen=True)
class UsageWindow:
    used_percent: int
    resets_at: int
    window_minutes: int | None = None


@dataclass(frozen=True)
class ProviderUsage:
    primary: UsageWindow | None = None
    secondary: UsageWindow | None = None


def usage_window(
    raw: object,
    *,
    percent_key: str,
    reset_key: str,
    default_window_minutes: int | None = None,
) -> UsageWindow | None:
    if not isinstance(raw, Mapping):
        return None
    percent = bounded_percent(raw.get(percent_key))
    resets_at = bounded_integer(raw.get(reset_key), 1, MAX_RESET_TIMESTAMP)
    window_minutes = bounded_integer(raw.get("windowDurationMins"), 1, 525_600)
    if percent is None or resets_at is None:
        return None
    return UsageWindow(
        used_percent=percent,
        resets_at=resets_at,
        window_minutes=window_minutes or default_window_minutes,
    )


def parse_claude_status(data: object) -> ProviderUsage | None:
    if not isinstance(data, Mapping):
        return None
    limits = data.get("rate_limits")
    if not isinstance(limits, Mapping):
        return None
    primary = usage_window(
        limits.get("seven_day"),
        percent_key="used_percentage",
        reset_key="resets_at",
        default_window_minutes=10_080,
    )
    secondary = usage_window(
        limits.get("five_hour"),
        percent_key="used_percentage",
        reset_key="resets_at",
        default_window_minutes=300,
    )
    return ProviderUsage(primary=primary, secondary=secondary) if primary or secondary else None


def parse_codex_result(result: object) -> ProviderUsage | None:
    if not isinstance(result, Mapping):
        return None
    limits: object = result.get("rateLimits")
    by_id = result.get("rateLimitsByLimitId")
    if isinstance(by_id, Mapping) and isinstance(by_id.get("codex"), Mapping):
        limits = by_id["codex"]
    if not isinstance(limits, Mapping):
        return None
    primary = usage_window(
        limits.get("primary"),
        percent_key="usedPercent",
        reset_key="resetsAt",
    )
    secondary = usage_window(
        limits.get("secondary"),
        percent_key="usedPercent",
        reset_key="resetsAt",
    )
    return ProviderUsage(primary=primary, secondary=secondary) if primary or secondary else None


def parse_codex_messages(lines: Sequence[str]) -> ProviderUsage | None:
    for line in lines:
        if len(line) > MAX_INPUT_BYTES:
            continue
        try:
            message = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        if isinstance(message, Mapping) and message.get("id") == CODEX_RATE_LIMIT_REQUEST_ID:
            return parse_codex_result(message.get("result"))
    return None


def provider_payload(usage: ProviderUsage | None) -> JsonObject:
    def field(window: UsageWindow | None, name: str) -> object:
        return getattr(window, name) if window is not None else None

    return {
        "percent": field(usage.primary if usage else None, "used_percent"),
        "resetsAt": field(usage.primary if usage else None, "resets_at"),
        "windowMinutes": field(usage.primary if usage else None, "window_minutes"),
        "secondaryPercent": field(usage.secondary if usage else None, "used_percent"),
        "secondaryResetsAt": field(usage.secondary if usage else None, "resets_at"),
        "secondaryWindowMinutes": field(
            usage.secondary if usage else None, "window_minutes"
        ),
    }


def provider_from_payload(raw: object) -> ProviderUsage | None:
    if not isinstance(raw, Mapping):
        return None
    primary_raw = {
        "percent": raw.get("percent"),
        "resetsAt": raw.get("resetsAt"),
        "windowDurationMins": raw.get("windowMinutes"),
    }
    primary = usage_window(
        primary_raw,
        percent_key="percent",
        reset_key="resetsAt",
    )
    secondary_raw = {
        "percent": raw.get("secondaryPercent"),
        "resetsAt": raw.get("secondaryResetsAt"),
        "windowDurationMins": raw.get("secondaryWindowMinutes"),
    }
    secondary = usage_window(
        secondary_raw,
        percent_key="percent",
        reset_key="resetsAt",
    )
    return ProviderUsage(primary=primary, secondary=secondary) if primary or secondary else None


def migrate_claude_cache_v1(usage: ProviderUsage | None) -> ProviderUsage | None:
    """Convert the legacy remaining-percent, hourly-first cache contract."""

    def as_used(window: UsageWindow | None) -> UsageWindow | None:
        if window is None:
            return None
        return UsageWindow(
            used_percent=100 - window.used_percent,
            resets_at=window.resets_at,
            window_minutes=window.window_minutes,
        )

    if usage is None:
        return None
    primary = as_used(usage.secondary)
    secondary = as_used(usage.primary)
    return ProviderUsage(primary=primary, secondary=secondary) if primary or secondary else None


def default_claude_cache_path() -> Path:
    runtime_root = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if runtime_root:
        return Path(runtime_root) / "statusbar-ai-usage" / "claude.json"
    cache_root = os.environ.get("XDG_CACHE_HOME", "").strip()
    root = Path(cache_root) if cache_root else Path.home() / ".cache"
    return root / "statusbar-ai-usage" / "claude.json"


def write_claude_cache(
    usage: ProviderUsage,
    path: Path,
    *,
    observed_at: float | None = None,
) -> None:
    payload = {
        "version": CLAUDE_CACHE_VERSION,
        "observedAt": int(observed_at if observed_at is not None else time.time()),
        "usage": provider_payload(usage),
    }
    atomic_write_json(path, payload, prefix=".claude-usage-")


def capture_claude_status(
    text: str,
    path: Path,
    *,
    observed_at: float | None = None,
) -> bool:
    if len(text.encode("utf-8")) > MAX_INPUT_BYTES:
        return False
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return False
    usage = parse_claude_status(data)
    if usage is None:
        return False
    try:
        write_claude_cache(usage, path, observed_at=observed_at)
    except OSError:
        return False
    return True


def expire_provider(usage: ProviderUsage | None, now: float) -> ProviderUsage | None:
    if usage is None:
        return None
    primary = usage.primary if usage.primary and usage.primary.resets_at > now else None
    secondary = usage.secondary if usage.secondary and usage.secondary.resets_at > now else None
    return ProviderUsage(primary=primary, secondary=secondary) if primary or secondary else None


def read_claude_cache(path: Path, *, now: float | None = None) -> ProviderUsage | None:
    try:
        if path.stat().st_size > MAX_CACHE_BYTES:
            return None
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return None
    if not isinstance(raw, Mapping):
        return None
    usage = provider_from_payload(raw.get("usage"))
    if raw.get("version") == 1:
        usage = migrate_claude_cache_v1(usage)
    elif raw.get("version") != CLAUDE_CACHE_VERSION:
        return None
    return expire_provider(usage, now if now is not None else time.time())


Sample = list[int | None]


def default_history_path() -> Path:
    """Quota history outlives a reboot, so it lives in the cache, not runtime."""
    cache_root = os.environ.get("XDG_CACHE_HOME", "").strip()
    root = Path(cache_root) if cache_root else Path.home() / ".cache"
    return root / "statusbar-ai-usage" / "history.json"


def sanitize_sample(raw: object) -> Sample | None:
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)) or len(raw) != 3:
        return None
    at = bounded_integer(raw[0], 1, MAX_RESET_TIMESTAMP)
    if at is None:
        return None
    primary = bounded_percent(raw[1])
    if primary is None:
        return None
    secondary = bounded_percent(raw[2]) if raw[2] is not None else None
    return [at, primary, secondary]


def sanitize_samples(raw: object) -> list[Sample]:
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)):
        return []
    samples = [
        sample
        for sample in (sanitize_sample(entry) for entry in raw[-MAX_HISTORY_SAMPLES:])
        if sample is not None
    ]
    # Ascending, strictly increasing timestamps keep the plot monotonic in time
    # even if a file was hand-edited or two writers interleaved.
    ordered: list[Sample] = []
    for sample in sorted(samples, key=lambda entry: entry[0] or 0):
        if ordered and ordered[-1][0] == sample[0]:
            ordered[-1] = sample
        else:
            ordered.append(sample)
    return ordered


def prune_samples(
    samples: Sequence[Sample],
    now: float,
    *,
    span: float = HISTORY_SPAN_SECONDS,
) -> list[Sample]:
    """Trim to the plotted window, keeping one older sample as its left edge.

    Without that carried-over sample a series whose value has not changed for
    hours would have nothing to draw at the start of the window.

    Samples dated after `now` are discarded: nothing can be measured in the
    future, and keeping one would wedge the series forever, since every real
    reading that followed would look older than the newest sample on file.
    """
    cutoff = now - span
    dated = [sample for sample in samples if (sample[0] or 0) <= now]
    inside = [sample for sample in dated if (sample[0] or 0) >= cutoff]
    outside = [sample for sample in dated if (sample[0] or 0) < cutoff]
    kept = ([outside[-1]] if outside else []) + inside
    return kept[-MAX_HISTORY_SAMPLES:]


def append_sample(
    samples: Sequence[Sample],
    payload: Mapping[str, object],
    now: float,
    *,
    span: float = HISTORY_SPAN_SECONDS,
    min_interval: float = HISTORY_MIN_INTERVAL,
) -> list[Sample]:
    """Record a reading, skipping unchanged ones inside the coalescing window."""
    primary = bounded_percent(payload.get("percent"))
    at = bounded_integer(now, 1, MAX_RESET_TIMESTAMP)
    existing = prune_samples(samples, now, span=span)
    if primary is None or at is None:
        return existing
    secondary = bounded_percent(payload.get("secondaryPercent"))
    last = existing[-1] if existing else None
    if last is not None:
        if at <= (last[0] or 0):
            return existing
        unchanged = last[1] == primary and last[2] == secondary
        if unchanged and at - (last[0] or 0) < min_interval:
            return existing
    return prune_samples([*existing, [at, primary, secondary]], now, span=span)


def read_history(path: Path) -> dict[str, list[Sample]]:
    try:
        if path.stat().st_size > MAX_HISTORY_BYTES:
            return {}
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return {}
    if not isinstance(raw, Mapping) or raw.get("version") != HISTORY_VERSION:
        return {}
    providers = raw.get("providers")
    if not isinstance(providers, Mapping):
        return {}
    return {
        str(name): sanitize_samples(samples) for name, samples in providers.items()
    }


def write_history(path: Path, providers: Mapping[str, Sequence[Sample]]) -> None:
    payload = {
        "version": HISTORY_VERSION,
        "providers": {name: list(samples) for name, samples in providers.items()},
    }
    atomic_write_json(path, payload, prefix=".usage-history-")


def codex_requests() -> list[JsonObject]:
    return [
        {
            "method": "initialize",
            "id": 0,
            "params": {
                "clientInfo": {
                    "name": "quickshell_statusbar",
                    "title": "Quickshell Status Bar",
                    "version": "1.0.0",
                }
            },
        },
        {"method": "initialized", "params": {}},
        {"method": "account/rateLimits/read", "id": 1},
    ]


def completes_exchange(line: str) -> bool:
    """True once a line carries the reply we asked for; anything else is noise.

    The app-server interleaves notifications and other replies, so the reader
    keeps going until it sees this — never merely until it sees output.
    """
    try:
        message = json.loads(line)
    except (json.JSONDecodeError, TypeError):
        return False
    return (
        isinstance(message, Mapping)
        and message.get("id") == CODEX_RATE_LIMIT_REQUEST_ID
    )


def read_lines_until(
    descriptor: int,
    deadline: float,
    *,
    is_complete: Callable[[str], bool] = completes_exchange,
    clock: Callable[[], float] = time.monotonic,
) -> list[str]:
    """Collect whole lines from `descriptor` until completion, EOF or `deadline`.

    Reads the raw descriptor rather than a buffered reader: `select` only sees
    the kernel's pipe, so a reply already sitting in a reader's buffer would
    otherwise look like silence and stall until the deadline.
    """
    lines: list[str] = []
    pending = ""
    while clock() < deadline:
        try:
            ready, _, _ = select.select(
                [descriptor], [], [], max(0.0, deadline - clock())
            )
            if not ready:
                break
            chunk = os.read(descriptor, 65_536)
        except (OSError, ValueError):
            break  # a dying pipe still yields the lines read so far
        if not chunk:  # EOF: the server exited
            break
        pending += chunk.decode("utf-8", "replace")
        *complete, pending = pending.split("\n")
        lines.extend(complete)
        if any(is_complete(line) for line in complete):
            break
        # An unterminated line this long is not a JSON-RPC reply; drop it
        # rather than growing the buffer without bound.
        if len(pending) > MAX_INPUT_BYTES:
            pending = ""
    # A reply flushed without a trailing newline is still a reply.
    if pending:
        lines.append(pending)
    return lines


def version_ordering_key(path: Path) -> tuple[int, ...]:
    """Rank sibling installs by the version in their directory: v9 below v25."""
    return tuple(int(number) for number in re.findall(r"\d+", path.parent.parent.name))


def codex_candidates(home: Path) -> list[Path]:
    """Known install locations for the codex CLI, newest version first."""
    return [
        match
        for pattern in CODEX_SEARCH_GLOBS
        for match in sorted(home.glob(pattern), key=version_ordering_key, reverse=True)
    ]


def resolve_codex_executable(
    *,
    environ: Mapping[str, str] = os.environ,
    home: Path | None = None,
    which: Callable[[str], str | None] | None = None,
) -> str:
    """CODEX_BIN, else PATH, else a known install directory, else the bare name.

    Returning the bare name when nothing resolves is deliberate: it fails the
    same way a missing binary already does, and the caller treats that as "no
    reading this cycle" rather than an error.
    """
    override = environ.get("CODEX_BIN")
    if override:
        return override
    lookup = which or (lambda name: shutil.which(name, path=environ.get("PATH")))
    on_path = lookup(CODEX_EXECUTABLE)
    if on_path:
        return on_path
    root = home if home is not None else Path(environ.get("HOME", "~")).expanduser()
    for candidate in codex_candidates(root):
        if os.access(candidate, os.X_OK):
            return str(candidate)
    debug("codex: not on PATH nor in any known install directory")
    return CODEX_EXECUTABLE


def run_codex_app_server(
    requests: Sequence[Mapping[str, object]],
    *,
    timeout: float = CODEX_EXCHANGE_TIMEOUT,
    command: Sequence[str] | None = None,
    is_complete: Callable[[str], bool] = completes_exchange,
) -> list[str]:
    """Write `requests` to a codex app-server and read lines until it answers."""
    argv = list(command or (resolve_codex_executable(), "app-server"))
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except OSError:
        return []
    lines: list[str] = []
    try:
        if process.stdin is None or process.stdout is None:
            return []
        for request in requests:
            process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
        process.stdin.flush()
        lines = read_lines_until(
            process.stdout.fileno(),
            time.monotonic() + timeout,
            is_complete=is_complete,
        )
    except (OSError, ValueError):
        pass
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=CODEX_SHUTDOWN_WAIT)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=CODEX_SHUTDOWN_WAIT)
        for pipe in (process.stdin, process.stdout):
            if pipe is not None:
                with contextlib.suppress(OSError):
                    pipe.close()
    return lines


def fetch_codex_usage() -> ProviderUsage | None:
    fetched = parse_codex_messages(run_codex_app_server(codex_requests()))
    if fetched is None:
        debug("codex: no rate-limit reply this cycle")
    return fetched


class UsageCollector:
    def __init__(
        self,
        *,
        claude_cache_path: Path | None = None,
        codex_fetcher: CodexFetcher = fetch_codex_usage,
        wall_clock: Callable[[], float] = time.time,
        monotonic_clock: Callable[[], float] = time.monotonic,
        codex_refresh_interval: float = DEFAULT_CODEX_REFRESH_INTERVAL,
        history_path: Path | None = None,
    ) -> None:
        self.claude_cache_path = claude_cache_path or default_claude_cache_path()
        self.history_path = history_path or default_history_path()
        self.wall_clock = wall_clock
        self.monotonic_clock = monotonic_clock
        self.codex_refresh_interval = codex_refresh_interval
        # Spawning the app-server is expensive, so a failed fetch still spends
        # the interval; the last good reading covers the gap until it expires.
        self.codex = ThrottledValue[ProviderUsage | None](
            codex_fetcher, codex_refresh_interval, initial=None, retry_failed=False
        )
        self.history = read_history(self.history_path)

    def snapshot(self) -> JsonObject:
        cached_codex = self.codex.get(self.monotonic_clock())
        now = self.wall_clock()
        payloads = {
            "claude": provider_payload(read_claude_cache(self.claude_cache_path, now=now)),
            "codex": provider_payload(expire_provider(cached_codex, now)),
        }
        self.record_history(payloads, now)
        return {
            name: {**payload, "history": self.history.get(name, [])}
            for name, payload in payloads.items()
        }

    def record_history(self, payloads: Mapping[str, JsonObject], now: float) -> None:
        updated = {
            name: append_sample(self.history.get(name, []), payload, now)
            for name, payload in payloads.items()
        }
        if updated == self.history:
            return
        self.history = updated
        # A history file the bar cannot write is a cosmetic loss, never a
        # reason to stop streaming live quota numbers.
        try:
            write_history(self.history_path, self.history)
        except OSError:
            pass


CollectorFactory = Callable[..., UsageCollector]
StreamRunner = Callable[..., int]


def main(
    argv: Sequence[str] | None = None,
    *,
    stdin_text: Callable[[], str] = lambda: sys.stdin.read(MAX_INPUT_BYTES + 1),
    collector_factory: CollectorFactory = UsageCollector,
    stream: StreamRunner = run_stream,
) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-claude", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--interval", type=float, default=DEFAULT_STREAM_INTERVAL)
    parser.add_argument(
        "--codex-refresh-interval",
        type=float,
        default=DEFAULT_CODEX_REFRESH_INTERVAL,
    )
    parser.add_argument("--claude-cache", type=Path, default=None)
    args = parser.parse_args(argv)
    cache_path = args.claude_cache or default_claude_cache_path()
    if args.capture_claude:
        return 0 if capture_claude_status(stdin_text(), cache_path) else 1

    collector = collector_factory(
        claude_cache_path=cache_path,
        codex_refresh_interval=max(
            MIN_CODEX_REFRESH_INTERVAL, args.codex_refresh_interval
        ),
    )
    return stream(
        collector.snapshot,
        once=args.once,
        interval=max(MIN_STREAM_INTERVAL, args.interval),
    )


if __name__ == "__main__":
    sys.exit(main())
