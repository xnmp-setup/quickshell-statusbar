#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Emit one compact JSON status snapshot per second for the Quickshell bar."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from collections import defaultdict
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from ghostty_status import (
    GhosttyDiscovery,
    GhosttyWindow,
    assign_ghostty_windows,
    is_ghostty_class,
    strip_invisible_metadata,
)
from stream_kit import (
    CommandRunner,
    JsonObject,
    ThrottledValue,
    TrailingWindow,
    run_command,
    run_stream,
)

PathReader = Callable[[Path], str]


@dataclass(frozen=True)
class CpuTimes:
    total: int
    idle: int


@dataclass(frozen=True)
class DiskCounters:
    reads: int
    writes: int
    busy_ms: int


@dataclass(frozen=True)
class DiskSample:
    timestamp: float
    counters: Mapping[str, DiskCounters]


@dataclass(frozen=True)
class AgentProcess:
    kind: str
    tty: str


@dataclass(frozen=True)
class BatteryStatus:
    is_laptop: bool
    percent: int | None
    state: str


@dataclass(frozen=True)
class WifiStatus:
    connected: bool
    ssid: str
    strength: int | None
    device: str


APP_ICONS: Mapping[str, str] = {
    "org.wezfurlong.wezterm": "org.wezfurlong.wezterm",
    "com.mitchellh.ghostty": "com.mitchellh.ghostty",
    "google-chrome": "google-chrome",
    "google-chrome-stable": "google-chrome",
    "chromium": "chromium",
    "obsidian": "obsidian",
    "dev.zed.zed": "dev.zed.Zed",
    "dev.zed.zed-dev": "dev.zed.Zed",
    "code": "visual-studio-code",
    "code-oss": "visual-studio-code",
    "firefox": "firefox",
}
APP_LABELS: Mapping[str, str] = {
    "org.wezfurlong.wezterm": "WezTerm",
    "com.mitchellh.ghostty": "Ghostty",
    "google-chrome": "Google Chrome",
    "google-chrome-stable": "Google Chrome",
    "chromium": "Chromium",
    "obsidian": "Obsidian",
    "dev.zed.zed": "Zed",
    "dev.zed.zed-dev": "Zed",
    "code": "Visual Studio Code",
    "code-oss": "Visual Studio Code",
    "firefox": "Firefox",
    "tauri-explorer": "Tauri Explorer",
}
WEZTERM_CLASS = "org.wezfurlong.wezterm"
PHYSICAL_DISK_EXCLUDES = ("loop", "ram", "zram", "dm-", "md")
CPU_HWMON_NAMES = frozenset({"coretemp", "k10temp", "zenpower"})
GPU_HWMON_NAMES = frozenset({"amdgpu", "nouveau", "nvidia"})
HOT_TEMPERATURE_C = 75
MAX_WEZTERM_INSTANCES = 64
MAX_WEZTERM_PANES = 1024
MAX_ACTIVITIES_PER_CLIENT = 32
TITLE_PREFIX = re.compile(r"^(?:\[Z\]\s+)?(?:\[\d+/(\d+)\]\s+)?")
WEZTERM_WINDOW_TAG = re.compile(r"([\U000e0020-\U000e007e]+)\U000e007f$")
THEME_KEYS = (
    "accent",
    "accent_light",
    "background",
    "surface",
    "border",
    "text",
    "text_dim",
)
DEFAULT_PALETTE: Mapping[str, str] = {
    "accent": "#d4607a",
    "accent_light": "#e87898",
    "background": "#0a0e28",
    "surface": "#2a3352",
    "border": "#3c4268",
    "text": "#d8dce8",
    "text_dim": "#8088b4",
}
ICON_ROOTS = tuple(
    path
    for path in (
        Path.home() / ".local/share/icons/hicolor",
        Path("/usr/local/share/icons/hicolor"),
        Path("/usr/share/icons/hicolor"),
        Path("/run/current-system/sw/share/icons/hicolor"),
    )
    if path.is_dir()
)


def clamp_percent(value: float) -> int:
    return round(max(0.0, min(100.0, value)))


def parse_theme_palette(text: str) -> dict[str, str]:
    palette = dict(DEFAULT_PALETTE)
    for key in THEME_KEYS:
        match = re.search(rf"\b{key}\s*=\s*[\"']([0-9a-fA-F]{{6}})[\"']", text)
        if match:
            palette[key] = "#" + match.group(1).lower()
    return palette


def parse_cpu_times(text: str) -> CpuTimes | None:
    line = next((line for line in text.splitlines() if line.startswith("cpu ")), "")
    try:
        values = [int(value) for value in line.split()[1:]]
    except ValueError:
        return None
    if len(values) < 4:
        return None
    return CpuTimes(
        total=sum(values), idle=values[3] + (values[4] if len(values) > 4 else 0)
    )


def cpu_percent(previous: CpuTimes | None, current: CpuTimes | None) -> int | None:
    if previous is None or current is None:
        return None
    total_delta = current.total - previous.total
    idle_delta = current.idle - previous.idle
    if total_delta <= 0:
        return None
    return clamp_percent(100.0 * (total_delta - idle_delta) / total_delta)


def memory_percent(text: str) -> int | None:
    values: dict[str, int] = {}
    for line in text.splitlines():
        name, separator, rest = line.partition(":")
        if separator and name in {"MemTotal", "MemAvailable"}:
            try:
                values[name] = int(rest.split()[0])
            except (IndexError, ValueError):
                return None
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable")
    if total <= 0 or available is None:
        return None
    return clamp_percent(100.0 * (total - available) / total)


def parse_temperature(text: str) -> int | None:
    """Parse a Linux hwmon millidegree value and reject impossible readings."""
    try:
        value = float(text.strip()) / 1000.0
    except ValueError:
        return None
    if not 0 <= value <= 200:
        return None
    return round(value)


def hot_temperature(value: int | None) -> int | None:
    return value if value is not None and value >= HOT_TEMPERATURE_C else None


def summarize_batteries(rows: Sequence[Mapping[str, str]]) -> BatteryStatus:
    if not rows:
        return BatteryStatus(is_laptop=False, percent=None, state="")
    capacities: list[int] = []
    states: list[str] = []
    for row in rows:
        try:
            capacity = int(row.get("capacity", ""))
        except ValueError:
            capacity = -1
        if 0 <= capacity <= 100:
            capacities.append(capacity)
        state = row.get("status", "").strip()
        if state:
            states.append(state)
    percent = clamp_percent(sum(capacities) / len(capacities)) if capacities else None
    state = states[0] if len(set(states)) == 1 else "Mixed" if states else "Unknown"
    return BatteryStatus(is_laptop=True, percent=percent, state=state)


def split_nmcli_row(line: str) -> list[str]:
    """Split nmcli terse output while preserving escaped colons and backslashes."""
    fields: list[str] = []
    current: list[str] = []
    escaped = False
    for character in line:
        if escaped:
            current.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == ":":
            fields.append("".join(current))
            current = []
        else:
            current.append(character)
    if escaped:
        current.append("\\")
    fields.append("".join(current))
    return fields


def parse_wifi_status(text: str) -> WifiStatus:
    for line in text.splitlines():
        fields = split_nmcli_row(line)
        if len(fields) != 4 or fields[0] != "*":
            continue
        try:
            strength = clamp_percent(float(fields[2]))
        except ValueError:
            strength = None
        return WifiStatus(
            connected=True,
            ssid=fields[1],
            strength=strength,
            device=fields[3],
        )
    return WifiStatus(connected=False, ssid="", strength=None, device="")


def parse_nvidia_stats(text: str) -> tuple[int | None, int | None]:
    utilization: list[int] = []
    temperatures: list[int] = []
    for line in text.splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) != 2:
            continue
        try:
            utilization.append(clamp_percent(float(fields[0])))
            temperature = int(fields[1])
        except ValueError:
            continue
        if 0 <= temperature <= 200:
            temperatures.append(temperature)
    return (
        max(utilization) if utilization else None,
        max(temperatures) if temperatures else None,
    )


def parse_diskstats(text: str, devices: Iterable[str]) -> dict[str, DiskCounters]:
    wanted = set(devices)
    result: dict[str, DiskCounters] = {}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) < 13 or fields[2] not in wanted:
            continue
        try:
            # Linux block stats: sectors read, sectors written, ms doing I/O.
            result[fields[2]] = DiskCounters(
                reads=int(fields[5]), writes=int(fields[9]), busy_ms=int(fields[12])
            )
        except ValueError:
            continue
    return result


def disk_busy_percent(
    old: DiskSample | None, new: DiskSample
) -> tuple[int | None, str]:
    if old is None or new.timestamp <= old.timestamp:
        return None, "Collecting a 30-second disk activity window"
    elapsed = new.timestamp - old.timestamp
    measurements: list[tuple[float, str, float, float]] = []
    for device, current in new.counters.items():
        previous = old.counters.get(device)
        if previous is None:
            continue
        busy = max(0, current.busy_ms - previous.busy_ms) / (elapsed * 1000.0) * 100.0
        # Kernel diskstats sectors are 512-byte units regardless of filesystem block size.
        read_mib = max(0, current.reads - previous.reads) * 512 / elapsed / 1024 / 1024
        write_mib = (
            max(0, current.writes - previous.writes) * 512 / elapsed / 1024 / 1024
        )
        measurements.append((busy, device, read_mib, write_mib))
    if not measurements:
        return None, "No physical disk activity data available"
    busy, device, read_mib, write_mib = max(measurements)
    window = min(30, round(elapsed))
    tooltip = (
        f"{device} was servicing I/O {clamp_percent(busy)}% of the last {window}s"
        f" · read {read_mib:.1f} MiB/s · write {write_mib:.1f} MiB/s"
    )
    return clamp_percent(busy), tooltip


def parse_io_pressure(text: str) -> tuple[float | None, float | None]:
    """Parse /proc/pressure/io avg10 values for the some and full lines."""
    some: float | None = None
    full: float | None = None
    for line in text.splitlines():
        fields = line.split()
        if not fields or fields[0] not in {"some", "full"}:
            continue
        for field in fields[1:]:
            if not field.startswith("avg10="):
                continue
            try:
                value = float(field[len("avg10=") :])
            except ValueError:
                continue
            if 0 <= value <= 100:
                if fields[0] == "some":
                    some = value
                else:
                    full = value
    return some, full


def io_pressure_metric(
    pressure: tuple[float | None, float | None],
    busy: int | None,
    busy_tooltip: str,
) -> tuple[int | None, str]:
    """Prefer PSI stall time over device busy time for the inline IO metric.

    Device utilisation is nearly meaningless on multi-queue NVMe: tasks can be
    stalled on I/O most of the time while the device reports modest busy time.
    PSI measures the stalls directly. Kernels without CONFIG_PSI (or booted
    with psi=0) fall back to the busy-time metric.
    """
    some, full = pressure
    value = full if full is not None else some
    if value is None:
        return busy, busy_tooltip
    # The inline number is the full-stall figure: the share of time every
    # non-idle task was blocked on disk at once. The softer some-task figure
    # stays in the tooltip.
    label = "All tasks" if full is not None else "Some task"
    tooltip = f"{label} stalled on disk I/O {round(value)}% of the last 10s"
    if full is not None and some is not None:
        tooltip += f" · some task stalled {round(some)}%"
    if busy is not None:
        tooltip += f"\n{busy_tooltip}"
    return clamp_percent(value), tooltip


def parse_tab_count(title: str) -> int:
    title = strip_wezterm_window_tag(title)
    match = TITLE_PREFIX.match(title)
    if not match or match.group(1) is None:
        return 1
    try:
        return max(1, int(match.group(1)))
    except ValueError:
        return 1


def title_body(title: str) -> str:
    return TITLE_PREFIX.sub("", strip_wezterm_window_tag(title), count=1)


def wezterm_window_id_from_title(title: str) -> int | None:
    match = WEZTERM_WINDOW_TAG.search(title)
    if not match:
        return None
    payload = "".join(chr(ord(character) - 0xE0000) for character in match.group(1))
    if not payload.startswith("wid:"):
        return None
    try:
        return int(payload.removeprefix("wid:"))
    except ValueError:
        return None


def strip_wezterm_window_tag(title: str) -> str:
    return WEZTERM_WINDOW_TAG.sub("", title)


def normalize_tty(tty: str) -> str:
    return tty if tty.startswith("/dev/") else f"/dev/{tty}"


# Deliberately not stream_kit.bounded_integer: hyprctl/wezterm emit ids as JSON
# strings often enough that they must coerce, while a float id (or a bool) is a
# schema violation to reject. The toolkit helper has the opposite polarity.
def positive_integer(value: object) -> int | None:
    if isinstance(value, (bool, float)):
        return None
    try:
        number = int(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if 0 < number <= 2_147_483_647 else None


def nonnegative_integer(value: object) -> int | None:
    if isinstance(value, (bool, float)):
        return None
    try:
        number = int(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if 0 <= number <= 2_147_483_647 else None


def normalized_agent_state(value: str) -> str:
    state = value.strip().casefold()
    if state == "working":
        return "working"
    if state == "attention":
        return "attention"
    return "idle"


def activity_title(value: object, kind: str = "") -> str:
    title = title_body(value) if isinstance(value, str) else ""
    title = title.strip()[:160]
    while title and not (title[0].isalnum() or title[0] in "~/."):
        title = title[1:].lstrip()
    if re.fullmatch(r"[0-9a-fA-F-]{32,36}", title):
        title = ""
    lowered = title.casefold()
    prefix = f"{kind} | "
    if kind and lowered.startswith(prefix):
        title = title[len(prefix):].strip()
    if title:
        return title
    return "Claude Code" if kind == "claude" else "Codex" if kind == "codex" else "Shell"


def wezterm_agent_state(
    row: Mapping[str, Any],
    kind: str,
    runtime_root: Path | None,
    state_reader: PathReader | None,
) -> str:
    gui_pid = positive_integer(row.get("gui_pid"))
    pane_id = nonnegative_integer(row.get("pane_id"))
    if (
        runtime_root is None
        or state_reader is None
        or gui_pid is None
        or pane_id is None
        or kind not in {"claude", "codex"}
    ):
        return "idle"
    path = runtime_root / f"wezterm-agent-state.gui-sock-{gui_pid}.{pane_id}.{kind}"
    return normalized_agent_state(state_reader(path)[:64])


def agent_counts_by_tty(processes: Iterable[AgentProcess]) -> dict[str, dict[str, int]]:
    counts: dict[str, dict[str, int]] = defaultdict(lambda: {"claude": 0, "codex": 0})
    for process in processes:
        if process.kind in {"claude", "codex"} and process.tty:
            counts[normalize_tty(process.tty)][process.kind] += 1
    return dict(counts)


def wezterm_pane_activities(
    pane: Mapping[str, Any],
    counts: Mapping[str, int],
    budget: int,
    *,
    runtime_root: Path | None,
    state_reader: PathReader | None,
) -> list[JsonObject]:
    """One activity per agent running in the pane, or one for a bare shell."""
    title = pane.get("title") or pane.get("window_title")
    activities: list[JsonObject] = []
    for kind, count in counts.items():
        for _ in range(min(count, budget - len(activities))):
            activities.append(
                {
                    "kind": kind,
                    "state": wezterm_agent_state(
                        pane, kind, runtime_root, state_reader
                    ),
                    "title": activity_title(title, kind),
                }
            )
    if not any(counts.values()) and budget > 0:
        activities.append(
            {"kind": "process", "state": "", "title": activity_title(title)}
        )
    return activities


def wezterm_windows(
    rows: Sequence[Mapping[str, Any]],
    tty_counts: Mapping[str, Mapping[str, int]],
    *,
    runtime_root: Path | None = None,
    state_reader: PathReader | None = None,
) -> list[JsonObject]:
    grouped: dict[tuple[int | None, int], list[Mapping[str, Any]]] = defaultdict(list)
    for row in rows[:MAX_WEZTERM_PANES]:
        window_id = nonnegative_integer(row.get("window_id"))
        if window_id is None:
            continue
        grouped[(positive_integer(row.get("gui_pid")), window_id)].append(row)
    result: list[JsonObject] = []
    for (gui_pid, window_id), panes in grouped.items():
        tab_ids = {pane.get("tab_id") for pane in panes}
        counts = {"claude": 0, "codex": 0}
        titles: set[str] = set()
        activities: list[JsonObject] = []
        for pane in panes:
            for key in ("title", "window_title"):
                value = pane.get(key)
                if isinstance(value, str) and value:
                    titles.add(title_body(value))
            pane_counts = tty_counts.get(str(pane.get("tty_name", "")), {})
            pane_agents = {
                kind: nonnegative_integer(pane_counts.get(kind, 0)) or 0
                for kind in counts
            }
            for kind, count in pane_agents.items():
                counts[kind] += count
            activities.extend(
                wezterm_pane_activities(
                    pane,
                    pane_agents,
                    MAX_ACTIVITIES_PER_CLIENT - len(activities),
                    runtime_root=runtime_root,
                    state_reader=state_reader,
                )
            )
        result.append(
            {
                "guiPid": gui_pid,
                "windowId": window_id,
                "tabs": max(1, len(tab_ids)),
                "titles": sorted(titles, key=len, reverse=True),
                "activities": activities,
                **counts,
            }
        )
    return result


def match_wezterm_window(
    title: str, windows: Sequence[Mapping[str, Any]]
) -> Mapping[str, Any] | None:
    tagged_id = wezterm_window_id_from_title(title)
    if tagged_id is not None:
        tagged = [window for window in windows if window.get("windowId") == tagged_id]
        return tagged[0] if len(tagged) == 1 else None
    tabs = parse_tab_count(title)
    body = title_body(title)
    candidates = [window for window in windows if int(window.get("tabs", 1)) == tabs]
    exact = [window for window in candidates if body in window.get("titles", [])]
    if len(exact) == 1:
        return exact[0]
    suffix = [
        window
        for window in candidates
        if any(
            body.endswith(candidate) or candidate.endswith(body)
            for candidate in window.get("titles", [])
        )
    ]
    return (
        suffix[0]
        if len(suffix) == 1
        else (candidates[0] if len(candidates) == 1 else None)
    )


def assign_wezterm_windows(
    clients: Sequence[Mapping[str, Any]],
    windows: Sequence[Mapping[str, Any]],
    previous_clients: Mapping[str, Mapping[str, Any]],
) -> dict[str, Mapping[str, Any]]:
    """Assign each mux window at most once, preferring stable title identities."""

    def identity(window: Mapping[str, Any]) -> tuple[int | None, int] | None:
        window_id = nonnegative_integer(window.get("windowId"))
        if window_id is None:
            return None
        return (positive_integer(window.get("guiPid")), window_id)

    available = {
        key: window
        for window in windows
        if (key := identity(window)) is not None
    }
    assigned: dict[str, Mapping[str, Any]] = {}
    ordered = sorted(clients, key=lambda client: str(client.get("address", "")))

    def candidate_keys(client: Mapping[str, Any]) -> list[tuple[int | None, int]]:
        gui_pid = positive_integer(client.get("pid"))
        exact = [key for key in available if key[0] == gui_pid]
        if gui_pid is not None and exact:
            return exact
        legacy = [key for key in available if key[0] is None]
        if legacy:
            return legacy
        return list(available) if gui_pid is None else []

    def claim(
        client: Mapping[str, Any], key: tuple[int | None, int] | None
    ) -> bool:
        address = str(client.get("address", ""))
        if not address or key is None or key not in available:
            return False
        assigned[address] = available.pop(key)
        return True

    pending: list[Mapping[str, Any]] = []
    for client in ordered:
        title = str(client.get("title", ""))
        tagged_id = wezterm_window_id_from_title(title)
        tagged = [key for key in candidate_keys(client) if key[1] == tagged_id]
        if len(tagged) == 1 and claim(client, tagged[0]):
            continue
        previous = previous_clients.get(str(client.get("address", "")), {})
        previous_id = nonnegative_integer(previous.get("weztermWindowId"))
        previous_gui = positive_integer(previous.get("weztermGuiPid"))
        if previous_gui is None:
            previous_gui = positive_integer(client.get("pid"))
        previous_key = (
            (previous_gui, previous_id) if previous_id is not None else None
        )
        if not claim(client, previous_key):
            pending.append(client)

    # Untagged legacy windows get a deterministic one-to-one fallback. It keeps
    # aggregate counts correct and stops two identical titles from consuming the
    # same mux window while WezTerm reloads the tagged title formatter.
    for client in pending:
        available_keys = candidate_keys(client)
        if not available_keys:
            continue
        title = str(client.get("title", ""))
        matched = match_wezterm_window(
            title, [available[key] for key in available_keys]
        )
        if matched is not None:
            claim(client, identity(matched))
            continue
        tabs = parse_tab_count(title)
        tab_matches = sorted(
            (
                key
                for key in available_keys
                if (window := available.get(key)) is not None
                if int(window.get("tabs", 1)) == tabs
            ),
            key=lambda key: (key[0] or 0, key[1]),
        )
        if tab_matches:
            claim(client, tab_matches[0])
    return assigned


def default_runtime_root() -> Path:
    value = os.environ.get("XDG_RUNTIME_DIR", "")
    return Path(value) if value.startswith("/") else Path(f"/run/user/{os.getuid()}")


def wezterm_list_targets(
    clients: Sequence[Mapping[str, Any]], runtime_root: Path
) -> list[tuple[int | None, tuple[str, ...]]]:
    wezterm_clients = [
        client for client in clients if is_wezterm_class(str(client.get("class", "")))
    ]
    gui_pids = sorted(
        {
            pid
            for client in wezterm_clients
            if (pid := positive_integer(client.get("pid"))) is not None
        }
    )[:MAX_WEZTERM_INSTANCES]
    base = ("wezterm", "cli", "list", "--format", "json")
    if not gui_pids:
        return [(None, base)] if wezterm_clients else []
    return [
        (
            pid,
            (
                "env",
                f"WEZTERM_UNIX_SOCKET={runtime_root / 'wezterm' / f'gui-sock-{pid}'}",
                *base,
            ),
        )
        for pid in gui_pids
    ]


def query_wezterm_rows(
    clients: Sequence[Mapping[str, Any]],
    runtime_root: Path,
    runner: CommandRunner,
) -> list[Mapping[str, Any]]:
    rows: list[Mapping[str, Any]] = []
    for gui_pid, command in wezterm_list_targets(clients, runtime_root):
        parsed = try_parse_json_array(runner(command))
        if parsed is None:
            continue
        for row in parsed[:MAX_WEZTERM_PANES]:
            rows.append({**row, "gui_pid": gui_pid})
    return rows[:MAX_WEZTERM_PANES]


def icon_name_for(app_class: str) -> str:
    normalized = app_class.casefold()
    if normalized.startswith(WEZTERM_CLASS):
        return APP_ICONS[WEZTERM_CLASS]
    return APP_ICONS.get(normalized, app_class or "application-x-executable")


def app_label(app_class: str) -> str:
    normalized = app_class.casefold()
    if normalized.startswith(WEZTERM_CLASS):
        return APP_LABELS[WEZTERM_CLASS]
    known = APP_LABELS.get(normalized)
    if known:
        return known
    tail = re.split(r"[./_-]+", app_class)[-1] if app_class else "Application"
    return tail[:64].replace("-", " ").title() or "Application"


def client_title(client: Mapping[str, Any], app_class: str) -> str:
    title = str(client.get("title", ""))
    if is_wezterm_class(app_class):
        title = title_body(title)
    elif is_ghostty_class(app_class):
        title = strip_invisible_metadata(title)
    return title.strip()[:256]


@lru_cache(maxsize=128)
def resolve_icon(icon_name: str, roots: tuple[Path, ...] = ICON_ROOTS) -> str:
    """Return a stable local URL when an icon exists, otherwise its theme name."""
    if icon_name.startswith("/"):
        path = Path(icon_name)
        return path.as_uri() if path.is_file() else "application-x-executable"
    candidates: list[Path] = []
    for root in roots:
        for extension in ("svg", "png", "xpm"):
            candidates.extend(root.glob(f"*/apps/{icon_name}.{extension}"))
    if not candidates:
        for pixmaps in (Path("/usr/local/share/pixmaps"), Path("/usr/share/pixmaps")):
            for extension in ("svg", "png", "xpm"):
                candidate = pixmaps / f"{icon_name}.{extension}"
                if candidate.is_file():
                    candidates.append(candidate)
    if not candidates:
        return icon_name

    def score(path: Path) -> tuple[int, int]:
        if path.suffix == ".svg":
            return (0, 0)
        match = re.search(r"/(\d+)x\d+", str(path))
        size = int(match.group(1)) if match else 0
        return (1, abs(size - 64))

    return min(candidates, key=score).resolve().as_uri()


def icon_for(app_class: str) -> str:
    return resolve_icon(icon_name_for(app_class))


def is_wezterm_class(app_class: str) -> bool:
    return app_class.casefold().startswith(WEZTERM_CLASS)


def is_terminal_class(app_class: str) -> bool:
    normalized = app_class.casefold()
    return is_wezterm_class(normalized) or is_ghostty_class(normalized)


def apply_agent_counts(
    app: Mapping[str, Any], source: Mapping[str, Any]
) -> JsonObject:
    """Tab and agent fields copied from a matched mux window or a stale client."""
    fields: JsonObject = {
        field: int(source.get(field, app.get(field, 0)))
        for field in ("tabs", "claude", "codex")
    }
    fields["activities"] = list(source.get("activities", []))[
        :MAX_ACTIVITIES_PER_CLIENT
    ]
    return fields


def ghostty_agent_counts(window: GhosttyWindow) -> JsonObject:
    """The same fields as `apply_agent_counts`, read off a Ghostty window value."""
    fields: JsonObject = {
        field: int(getattr(window, field)) for field in ("tabs", "claude", "codex")
    }
    fields["activities"] = [
        {"kind": activity.kind, "state": activity.state, "title": activity.title}
        for activity in window.activities[:MAX_ACTIVITIES_PER_CLIENT]
    ]
    return fields


def terminal_fields(
    client: Mapping[str, Any],
    app: Mapping[str, Any],
    *,
    wezterm: Mapping[str, Any] | None,
    ghostty: GhosttyWindow | None,
    stale: Mapping[str, Any] | None,
) -> JsonObject:
    """Agent fields for a terminal client: live mux window, else stale, else title.

    Non-terminal clients and unmatched Ghostty windows with no history keep the
    defaults already on `app`, so this returns nothing to merge for them.
    """
    app_class = str(client.get("class", ""))
    if is_wezterm_class(app_class):
        if wezterm:
            fields = apply_agent_counts(app, wezterm)
            fields["weztermWindowId"] = int(wezterm["windowId"])
            gui_pid = positive_integer(wezterm.get("guiPid"))
            if gui_pid is not None:
                fields["weztermGuiPid"] = gui_pid
            return fields
        if stale:
            return apply_agent_counts(app, stale)
        return {"tabs": parse_tab_count(str(client.get("title", "")))}
    if is_ghostty_class(app_class):
        if ghostty:
            fields = ghostty_agent_counts(ghostty)
            fields["ghosttyWindowId"] = ghostty.identity
            return fields
        if stale:
            return apply_agent_counts(app, stale)
    return {}


def client_entry(client: Mapping[str, Any]) -> JsonObject:
    """The presentation fields every client carries, before agent enrichment."""
    app_class = str(client.get("class", ""))
    return {
        "address": str(client.get("address", "")),
        "class": app_class,
        "icon": icon_for(app_class),
        "terminal": is_terminal_class(app_class),
        "label": app_label(app_class),
        "title": client_title(client, app_class),
        "tabs": 1,
        "claude": 0,
        "codex": 0,
        "activities": [],
    }


def workspace_placement(
    client: Mapping[str, Any], monitor_names: Mapping[Any, Any]
) -> tuple[tuple[int, str], str] | None:
    """The (id, monitor) key and display name for a client, or None if unplaced."""
    workspace = client.get("workspace") or {}
    try:
        workspace_id = int(workspace.get("id", 0))
    except (TypeError, ValueError, AttributeError):
        return None
    if workspace_id <= 0 or not client.get("mapped", True):
        return None
    monitor_name = str(monitor_names.get(client.get("monitor"), ""))
    return (workspace_id, monitor_name), str(workspace.get("name") or workspace_id)


def previous_client_index(
    previous: Sequence[Mapping[str, Any]],
) -> dict[str, Mapping[str, Any]]:
    """Last snapshot's clients by address, the fallback for a dropped mux query."""
    return {
        str(client.get("address", "")): client
        for workspace in previous
        for client in workspace.get("clients", [])
        if isinstance(client, Mapping)
    }


def build_workspaces(
    clients: Sequence[Mapping[str, Any]],
    monitors: Sequence[Mapping[str, Any]],
    wezterm: Sequence[Mapping[str, Any]],
    previous: Sequence[Mapping[str, Any]] = (),
    ghostty: Sequence[GhosttyWindow] = (),
) -> list[JsonObject]:
    monitor_names = {monitor.get("id"): monitor.get("name", "") for monitor in monitors}
    previous_clients = previous_client_index(previous)
    matched_wezterm = assign_wezterm_windows(
        [client for client in clients if is_wezterm_class(str(client.get("class", "")))],
        wezterm,
        previous_clients,
    )
    matched_ghostty = assign_ghostty_windows(
        [client for client in clients if is_ghostty_class(str(client.get("class", "")))],
        ghostty,
        previous_clients,
    )
    grouped: dict[tuple[int, str], list[JsonObject]] = defaultdict(list)
    workspace_names: dict[tuple[int, str], str] = {}
    for client in clients:
        placement = workspace_placement(client, monitor_names)
        if placement is None:
            continue
        workspace_key, workspace_name = placement
        workspace_names.setdefault(workspace_key, workspace_name)
        app = client_entry(client)
        app.update(
            terminal_fields(
                client,
                app,
                wezterm=matched_wezterm.get(app["address"]),
                ghostty=matched_ghostty.get(app["address"]),
                stale=previous_clients.get(app["address"]),
            )
        )
        grouped[workspace_key].append(app)

    return [
        {
            "id": workspace_id,
            "name": workspace_names[(workspace_id, monitor_name)],
            "monitor": monitor_name,
            "clients": apps,
            "claude": sum(app["claude"] for app in apps),
            "codex": sum(app["codex"] for app in apps),
        }
        for (workspace_id, monitor_name), apps in sorted(grouped.items())
    ]


def try_parse_json_array(text: str) -> list[Mapping[str, Any]] | None:
    try:
        value = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None
    return value if isinstance(value, list) else None


def parse_json_array(text: str) -> list[Mapping[str, Any]]:
    return try_parse_json_array(text) or []


def battery_tooltip(battery: BatteryStatus) -> str:
    return (
        f"Battery {battery.state.casefold()}"
        if battery.state
        else "Battery status unavailable"
    )


def wifi_tooltip(wifi: WifiStatus) -> str:
    return f"{wifi.ssid} · {wifi.device}" if wifi.connected else "Wi-Fi disconnected"


class StatusCollector:
    def __init__(
        self,
        *,
        proc_root: Path = Path("/proc"),
        sys_root: Path = Path("/sys"),
        runner: CommandRunner = run_command,
        clock: Callable[[], float] = time.monotonic,
        theme_path: Path | None = None,
        runtime_root: Path | None = None,
    ) -> None:
        self.proc_root = proc_root
        self.sys_root = sys_root
        self.runner = runner
        self.clock = clock
        self.theme_path = theme_path or Path.home() / ".config/hypr/theme-colors.lua"
        self.runtime_root = runtime_root or default_runtime_root()
        self.previous_cpu: CpuTimes | None = None
        self.disk_history: TrailingWindow[DiskSample] = TrailingWindow(30.0)
        # Workspace and wifi refreshes shell out; they are sampled far less often
        # than the 1 Hz snapshot. A failed workspace read retries immediately so a
        # single dropped hyprctl reply does not freeze the bar for a whole second.
        self.workspaces = ThrottledValue(
            self._refresh_workspaces, 1.0, initial=[], retry_failed=True
        )
        self.wifi = ThrottledValue(
            self._refresh_wifi, 5.0, initial=WifiStatus(False, "", None, "")
        )
        self.ghostty_discovery = GhosttyDiscovery(runner)

    def _read(self, path: Path) -> str:
        try:
            return path.read_text()
        except OSError:
            return ""

    def _physical_disks(self) -> list[str]:
        block_root = self.sys_root / "block"
        try:
            return sorted(
                path.name
                for path in block_root.iterdir()
                if not path.name.startswith(PHYSICAL_DISK_EXCLUDES)
            )
        except OSError:
            return []

    def _agent_processes(self) -> list[AgentProcess]:
        result: list[AgentProcess] = []
        try:
            pid_dirs = self.proc_root.iterdir()
        except OSError:
            return result
        for process_dir in pid_dirs:
            if not process_dir.name.isdigit():
                continue
            comm = self._read(process_dir / "comm").strip().casefold()
            kind = "codex" if comm == "codex" else "claude" if comm == "claude" else ""
            if not kind:
                continue
            try:
                tty = os.readlink(process_dir / "fd" / "0")
            except OSError:
                continue
            if tty.startswith("/dev/pts/"):
                result.append(AgentProcess(kind=kind, tty=tty))
        return result

    def _temperature_values(self, paths: Iterable[Path]) -> list[int]:
        values: list[int] = []
        for path in paths:
            value = parse_temperature(self._read(path))
            if value is not None:
                values.append(value)
        return values

    def _cpu_temperature(self) -> int | None:
        hwmon_root = self.sys_root / "class" / "hwmon"
        values: list[int] = []
        try:
            sensors = sorted(hwmon_root.glob("hwmon*"))
        except OSError:
            sensors = []
        for sensor in sensors:
            if self._read(sensor / "name").strip().casefold() in CPU_HWMON_NAMES:
                values.extend(self._temperature_values(sensor.glob("temp*_input")))
        if values:
            return max(values)

        thermal_root = self.sys_root / "class" / "thermal"
        try:
            zones = sorted(thermal_root.glob("thermal_zone*"))
        except OSError:
            zones = []
        for zone in zones:
            sensor_type = self._read(zone / "type").strip().casefold()
            if any(name in sensor_type for name in ("cpu", "x86_pkg", "soc_thermal")):
                values.extend(self._temperature_values([zone / "temp"]))
        return max(values) if values else None

    def _gpu_stats(self) -> tuple[int | None, int | None]:
        drm_root = self.sys_root / "class" / "drm"
        try:
            busy_paths = sorted(drm_root.glob("card*/device/gpu_busy_percent"))
            hwmon_paths = sorted(drm_root.glob("card*/device/hwmon/hwmon*"))
        except OSError:
            busy_paths = []
            hwmon_paths = []
        utilization: list[int] = []
        for path in busy_paths:
            try:
                utilization.append(clamp_percent(float(path.read_text().strip())))
            except (OSError, ValueError):
                continue
        temperatures: list[int] = []
        for sensor in hwmon_paths:
            name = self._read(sensor / "name").strip().casefold()
            if name in GPU_HWMON_NAMES:
                temperatures.extend(
                    self._temperature_values(sensor.glob("temp*_input"))
                )

        gpu = max(utilization) if utilization else None
        temperature = max(temperatures) if temperatures else None
        if gpu is None or temperature is None:
            nvidia_gpu, nvidia_temperature = parse_nvidia_stats(
                self.runner(
                    [
                        "nvidia-smi",
                        "--query-gpu=utilization.gpu,temperature.gpu",
                        "--format=csv,noheader,nounits",
                    ]
                )
            )
            gpu = gpu if gpu is not None else nvidia_gpu
            temperature = temperature if temperature is not None else nvidia_temperature
        return gpu, temperature

    def _batteries(self) -> BatteryStatus:
        power_root = self.sys_root / "class" / "power_supply"
        try:
            supplies = sorted(power_root.iterdir())
        except OSError:
            supplies = []
        rows = [
            {
                "capacity": self._read(supply / "capacity").strip(),
                "status": self._read(supply / "status").strip(),
            }
            for supply in supplies
            if self._read(supply / "type").strip().casefold() == "battery"
        ]
        return summarize_batteries(rows)

    def _refresh_wifi(self) -> WifiStatus:
        return parse_wifi_status(
            self.runner(
                [
                    "nmcli",
                    "--terse",
                    "--escape",
                    "yes",
                    "--fields",
                    "IN-USE,SSID,SIGNAL,DEVICE",
                    "device",
                    "wifi",
                    "list",
                    "--rescan",
                    "no",
                ]
            )
        )

    def _refresh_workspaces(self) -> list[JsonObject] | None:
        clients = try_parse_json_array(self.runner(["hyprctl", "-j", "clients"]))
        monitors = try_parse_json_array(self.runner(["hyprctl", "-j", "monitors"]))
        if clients is None or monitors is None:
            return None
        rows = query_wezterm_rows(clients, self.runtime_root, self.runner)
        tty_counts = agent_counts_by_tty(self._agent_processes())
        return build_workspaces(
            clients,
            monitors,
            wezterm_windows(
                rows,
                tty_counts,
                runtime_root=self.runtime_root,
                state_reader=self._read,
            ),
            previous=self.workspaces.value,
            ghostty=self.ghostty_discovery.windows(clients),
        )

    def snapshot(self) -> JsonObject:
        now = self.clock()
        current_cpu = parse_cpu_times(self._read(self.proc_root / "stat"))
        cpu = cpu_percent(self.previous_cpu, current_cpu)
        self.previous_cpu = current_cpu

        disk_sample = DiskSample(
            timestamp=now,
            counters=parse_diskstats(
                self._read(self.proc_root / "diskstats"), self._physical_disks()
            ),
        )
        self.disk_history.append(now, disk_sample)
        busy, busy_tooltip = disk_busy_percent(self.disk_history.baseline(), disk_sample)
        io, io_tooltip = io_pressure_metric(
            parse_io_pressure(self._read(self.proc_root / "pressure/io")),
            busy,
            busy_tooltip,
        )
        battery = self._batteries()
        wifi = (
            self.wifi.get(now)
            if battery.is_laptop
            else WifiStatus(False, "", None, "")
        )
        gpu, gpu_temperature = self._gpu_stats()
        return {
            "metrics": {
                "cpu": cpu,
                "ram": memory_percent(self._read(self.proc_root / "meminfo")),
                "io": io,
                "gpu": gpu,
                "ioTooltip": io_tooltip,
                "laptop": battery.is_laptop,
                "battery": battery.percent,
                "batteryState": battery.state.casefold(),
                "batteryTooltip": battery_tooltip(battery),
                "wifi": wifi.strength,
                "wifiConnected": wifi.connected,
                "wifiTooltip": wifi_tooltip(wifi),
                "cpuTemp": hot_temperature(self._cpu_temperature()),
                "gpuTemp": hot_temperature(gpu_temperature),
            },
            "palette": parse_theme_palette(self._read(self.theme_path)),
            "workspaces": self.workspaces.get(now),
        }


def main(
    argv: Sequence[str] | None = None,
    *,
    collector_factory: Callable[[], StatusCollector] = StatusCollector,
) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--once", action="store_true", help="emit one snapshot and exit"
    )
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args(argv)
    collector = collector_factory()
    # A sub-200ms cadence buys nothing: the cheapest sampled source (workspaces)
    # refreshes once a second.
    return run_stream(
        collector.snapshot, once=args.once, interval=max(0.2, args.interval)
    )


if __name__ == "__main__":
    sys.exit(main())
