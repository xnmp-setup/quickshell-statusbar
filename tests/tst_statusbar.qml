import QtQuick
import QtQuick.Controls
import QtTest
import "../quickshell"
import "../quickshell/StatusLayout.js" as StatusLayout
import "../quickshell/StatusSanitizer.js" as Sanitizer
import "../quickshell/StatusGraph.js" as StatusGraph
import "../quickshell/StatusIcons.js" as StatusIcons
import "../quickshell/StatusSeverity.js" as StatusSeverity
import "../quickshell/StatusFormat.js" as StatusFormat
import "../quickshell/StatusCommands.js" as StatusCommands
import "../quickshell/FocusState.js" as FocusState

TestCase {
    id: testCase
    name: "StatusBarMetrics"

    readonly property var themeColors: ({
        accent: "#fe8019",
        accent_light: "#fea45c",
        background: "#282828",
        surface: "#4b4840",
        border: "#625d51",
        text: "#ebdbb2",
        text_dim: "#a89984"
    })

    Component {
        id: metricComponent

        MetricCell {
            label: "CPU"
            themeColors: testCase.themeColors
        }
    }

    Component {
        id: workspaceComponent

        WorkspaceContextMenu {
            themeColors: testCase.themeColors
        }
    }

    Component {
        id: workspaceEditorComponent

        WorkspaceNameEditor {
            initialText: "Deep work"
            themeColors: testCase.themeColors
        }
    }

    Component {
        id: usageCellComponent

        UsageCell {
            provider: "claude"
            usage: ({
                percent: 76,
                resetsAt: 1800000600,
                windowMinutes: 300,
                secondaryPercent: 41,
                secondaryResetsAt: 1800086400,
                secondaryWindowMinutes: 10080
            })
            themeColors: testCase.themeColors
        }
    }

    Component {
        id: autoHideComponent

        AutoHideController {
            hideDelay: 40
        }
    }

    Component {
        id: settingsMenuComponent

        SettingsMenu {
            themeColors: testCase.themeColors
            autoHide: false
        }
    }

    Component {
        id: themedTooltipComponent

        ThemedToolTip {
            text: "Disk activity"
            themeColors: testCase.themeColors
        }
    }

    Component {
        id: workspaceTooltipComponent

        WorkspaceToolTip {
            workspaceData: ({
                id: 1,
                name: "Chez4",
                claude: 1,
                codex: 2,
                clients: [
                    {
                        label: "WezTerm",
                        title: "chezmoi",
                        icon: "assets/openai.svg",
                        terminal: true,
                        tabs: 2,
                        activities: [
                            { kind: "codex", state: "working", title: "chezmoi" },
                            { kind: "claude", state: "attention", title: "dotfiles" }
                        ]
                    }
                ]
            })
            themeColors: testCase.themeColors
        }
    }

    Component {
        id: sessionChipComponent

        WorkspaceChip {
            candidate: "segmented"
            editing: false
            themeColors: testCase.themeColors
            workspaceData: testCase.agentWorkspace("working", "working")
        }
    }

    Component {
        id: workspaceEditorRowComponent

        Row {
            id: editorRow

            property bool editing: true
            readonly property alias editorLoader: loader
            spacing: 5

            Loader {
                id: loader

                active: editorRow.editing
                visible: active
                width: active && item ? item.implicitWidth : 0
                height: active && item ? item.implicitHeight : 0
                sourceComponent: WorkspaceNameEditor {
                    initialText: "Deep work"
                    themeColors: testCase.themeColors
                }
            }

            Rectangle {
                width: 20
                height: 24
            }
        }
    }

    function colorAt(value): string {
        const metric = createTemporaryObject(metricComponent, this, { value: value });
        verify(metric !== null);
        return metric.displayColor.toString();
    }

    function metricAt(value): var {
        const metric = createTemporaryObject(metricComponent, this, { value: value });
        verify(metric !== null);
        return metric;
    }

    function test_thresholds(): void {
        compare(colorAt(null), "#ebdbb2");
        compare(colorAt(49), "#ebdbb2");
        compare(colorAt(50), "#fabd2f");
        compare(colorAt(75), "#fabd2f");
        compare(colorAt(76), "#fb4934");
        compare(colorAt(100), "#fb4934");
    }

    function test_workspace_context_menu_exposes_rename_and_shortcut(): void {
        const menu = createTemporaryObject(workspaceComponent, this);
        verify(menu !== null);
        compare(menu.shortcutLabel, "Alt+F2");
        compare(menu.modal, false);
        compare(menu.focus, true);
        compare(menu.popupType, Popup.Window);
        verify((menu.closePolicy & Popup.CloseOnEscape) !== 0);
        verify((menu.closePolicy & Popup.CloseOnPressOutside) !== 0);

        menu.open();
        tryCompare(menu, "visible", true);
        tryCompare(menu, "activeFocus", true);
        menu.dismissOnFocusLoss(false);
        tryCompare(menu, "visible", false);
    }

    function test_workspace_editor_prefills_selects_and_limits_input(): void {
        const editor = createTemporaryObject(workspaceEditorComponent, this);
        verify(editor !== null);
        compare(editor.editorText, "Deep work");
        compare(editor.maximumLength, 32);
        compare(editor.focusRequested, true);
        tryCompare(editor, "inputHasFocus", true);

        editor.editorText = "123456789012345678901234567890123";
        compare(editor.editorText, "12345678901234567890123456789012");
    }

    function test_workspace_editor_submits_trimmed_name_with_enter(): void {
        const editor = createTemporaryObject(workspaceEditorComponent, this);
        verify(editor !== null);
        let submittedName = null;
        editor.submitted.connect(name => submittedName = name);
        editor.editorText = "  project alpha  ";
        tryCompare(editor, "inputHasFocus", true);

        keyClick(Qt.Key_Return);

        compare(submittedName, "project alpha");
    }

    function test_workspace_editor_allows_empty_reset(): void {
        const editor = createTemporaryObject(workspaceEditorComponent, this);
        verify(editor !== null);
        let submittedName = null;
        editor.submitted.connect(name => submittedName = name);
        editor.editorText = "   ";

        editor.submit();

        compare(submittedName, "");
    }

    function test_workspace_editor_cancels_on_escape_or_focus_loss(): void {
        const escapeEditor = createTemporaryObject(workspaceEditorComponent, this);
        verify(escapeEditor !== null);
        let escapeCancelled = false;
        escapeEditor.cancelled.connect(() => escapeCancelled = true);
        tryCompare(escapeEditor, "inputHasFocus", true);

        keyClick(Qt.Key_Escape);

        verify(escapeCancelled);

        const blurEditor = createTemporaryObject(workspaceEditorComponent, this);
        verify(blurEditor !== null);
        let blurCancelled = false;
        blurEditor.cancelled.connect(() => blurCancelled = true);
        tryCompare(blurEditor, "inputHasFocus", true);

        blurEditor.dismissOnFocusLoss(false);

        verify(blurCancelled);
    }

    function test_workspace_editor_releases_row_width_when_closed(): void {
        const row = createTemporaryObject(workspaceEditorRowComponent, this);
        verify(row !== null);
        compare(row.editorLoader.width, 160);
        compare(row.implicitWidth, 185);

        row.editing = false;

        compare(row.editorLoader.visible, false);
        tryCompare(row, "implicitWidth", 20);
    }

    function test_hot_temperature_widens_cell_and_renders_next_to_value(): void {
        const cool = createTemporaryObject(metricComponent, this, { value: 42 });
        const hot = createTemporaryObject(metricComponent, this, {
            value: 42,
            temperature: 78
        });
        const critical = createTemporaryObject(metricComponent, this, {
            value: 42,
            temperature: 91
        });
        verify(cool !== null);
        verify(hot !== null);
        verify(critical !== null);
        compare(cool.implicitWidth, 96);
        compare(cool.temperatureText, "");
        compare(hot.implicitWidth, 130);
        compare(hot.temperatureText, "78°");
        compare(critical.temperatureText, "91°");
    }

    function test_moving_average_smooths_and_keeps_alignment(): void {
        compare(StatusGraph.movingAverage([], 3), []);
        compare(StatusGraph.movingAverage([10], 3), [10]);
        compare(StatusGraph.movingAverage([0, 10, 20, 30], 3), [0, 5, 10, 20]);
        const withGap = StatusGraph.movingAverage([10, null, 20], 3);
        compare(withGap.length, 3);
        compare(withGap[0], 10);
        compare(withGap[2], 15);
    }

    function test_graph_bounds_pad_flat_series_and_ignore_junk(): void {
        compare(StatusGraph.bounds([]), null);
        compare(StatusGraph.bounds(["broken", null]), null);
        const flat = StatusGraph.bounds([50, 50, 50]);
        compare(flat.min, 48);
        compare(flat.max, 52);
        const spread = StatusGraph.bounds([5, 90, null, 30]);
        compare(spread.min, 5);
        compare(spread.max, 90);
    }

    function test_graph_bounds_never_dip_below_zero_for_non_negative_series(): void {
        // A resting burn rate is all zeroes; padding it must widen upward
        // instead of labelling the axis with rates that cannot occur.
        const idle = StatusGraph.bounds([0, 0, 0]);
        compare(idle.min, 0);
        compare(idle.max, 4);
        const crawling = StatusGraph.bounds([0, 1, 0.5]);
        compare(crawling.min, 0);
        compare(crawling.max, 4);
        // Genuinely negative data still gets a band that contains it.
        const signed = StatusGraph.bounds([-1, -1]);
        compare(signed.min, -3);
        compare(signed.max, 1);
    }

    function test_tooltip_graph_needs_two_numeric_samples(): void {
        const bare = createTemporaryObject(themedTooltipComponent, this);
        const sparse = createTemporaryObject(themedTooltipComponent, this, {
            history: [42, null, "junk"]
        });
        const graphed = createTemporaryObject(themedTooltipComponent, this, {
            history: [42, 55, 61],
            smoothed: true
        });
        verify(bare !== null);
        verify(sparse !== null);
        verify(graphed !== null);
        compare(bare.showsGraph, false);
        compare(sparse.showsGraph, false);
        compare(graphed.showsGraph, true);
    }

    function test_wifi_icon_tracks_connection_and_strength(): void {
        compare(StatusIcons.wifiIcon(false, 80), "\u{f092d}");
        compare(StatusIcons.wifiIcon(true, null), "\u{f092f}");
        compare(StatusIcons.wifiIcon(true, 2), "\u{f092f}");
        compare(StatusIcons.wifiIcon(true, 15), "\u{f091f}");
        compare(StatusIcons.wifiIcon(true, 40), "\u{f0922}");
        compare(StatusIcons.wifiIcon(true, 60), "\u{f0925}");
        compare(StatusIcons.wifiIcon(true, 95), "\u{f0928}");
    }

    function test_battery_icon_tracks_charge_and_charging_state(): void {
        compare(StatusIcons.batteryIcon(50, "charging"), "\u{f0084}");
        compare(StatusIcons.batteryIcon(null, "discharging"), "\u{f008e}");
        compare(StatusIcons.batteryIcon(2, "discharging"), "\u{f0083}");
        compare(StatusIcons.batteryIcon(10, "discharging"), "\u{f007a}");
        compare(StatusIcons.batteryIcon(54, "discharging"), "\u{f007e}");
        compare(StatusIcons.batteryIcon(90, "full"), "\u{f0082}");
        compare(StatusIcons.batteryIcon(97, "full"), "\u{f0079}");
    }

    Component {
        id: focusCellComponent

        FocusCell {
            themeColors: testCase.themeColors
            width: implicitWidth
            height: implicitHeight
        }
    }

    function test_focus_toggle_reply_parses_one_mode_per_line(): void {
        const idle = FocusState.parseToggleReply("default\n");
        verify(idle.available);
        verify(!idle.dnd);

        const silenced = FocusState.parseToggleReply("default\ndo-not-disturb\n");
        verify(silenced.available);
        verify(silenced.dnd);

        // Surrounding noise must not fabricate or hide the mode.
        const padded = FocusState.parseToggleReply("  default \n\n do-not-disturb \n");
        verify(padded.dnd);
        verify(!FocusState.parseToggleReply("do-not-disturb-extra\n").dnd);
        // An oversized-but-valid single mode still parses at the size limit.
        verify(FocusState.parseToggleReply("x".repeat(4096)).available);
    }

    function test_focus_poll_reply_parses_the_busctl_modes_property(): void {
        const idle = FocusState.parsePollReply("v as 1 \"default\"\n");
        verify(idle.available);
        verify(!idle.dnd);

        const silenced = FocusState.parsePollReply(
            "v as 2 \"default\" \"do-not-disturb\"\n");
        verify(silenced.available);
        verify(silenced.dnd);

        // A daemon with every mode cleared is alive, just not focused.
        const bare = FocusState.parsePollReply("v as 0\n");
        verify(bare.available);
        verify(!bare.dnd);

        verify(!FocusState.parsePollReply("do-not-disturb").dnd);
        verify(!FocusState.parsePollReply("Call failed: Destination does not exist").available);
    }

    function test_focus_bad_replies_read_as_unreachable(): void {
        for (const reply of ["", "\n \n", null, undefined, 42, "x".repeat(5000)]) {
            for (const parse of [FocusState.parsePollReply,
                                 FocusState.parseToggleReply]) {
                const state = parse(reply);
                verify(!state.available, "available for " + reply);
                verify(!state.dnd, "dnd for " + reply);
            }
        }
    }

    function test_focus_unreachable_reply_never_rewrites_known_dnd(): void {
        // A transient read failure must not flip the cell to "off" and turn
        // the next click into a disable of the Focus the user still has on.
        const on = { available: true, dnd: true };
        const dropped = FocusState.nextState(on, FocusState.parsePollReply(""));
        verify(!dropped.available);
        verify(dropped.dnd);

        // A live reply is authoritative in both directions.
        const cleared = FocusState.nextState(
            dropped, FocusState.parsePollReply("as 1 \"default\""));
        verify(cleared.available);
        verify(!cleared.dnd);
        verify(FocusState.nextState(
            { available: true, dnd: false },
            FocusState.parseToggleReply("do-not-disturb\n")).dnd);

        // No history at all starts from "off".
        verify(!FocusState.nextState(null, FocusState.parsePollReply("")).dnd);
    }

    function test_focus_commands_split_autostart_by_intent(): void {
        // The poll must never resurrect a deliberately stopped daemon; the
        // toggle is the one call where waking mako is wanted.
        const query = FocusState.queryCommand();
        compare(query[0], "busctl");
        verify(query.indexOf("--auto-start=no") !== -1);
        // busctl honors --auto-start only on the `call` verb; `get-property`
        // activates the destination regardless.
        verify(query.indexOf("call") !== -1);
        verify(query.indexOf("get-property") === -1);
        verify(query.indexOf("Modes") !== -1);
        compare(FocusState.toggleCommand(),
                ["makoctl", "mode", "-t", "do-not-disturb"]);
    }

    function test_focus_icon_distinguishes_states(): void {
        compare(StatusIcons.focusIcon(false), "\u{f009c}");
        compare(StatusIcons.focusIcon(true), "\u{f0594}");
    }

    // Synthetic pointer events do not deliver under the offscreen platform,
    // so interaction rides the same hoverActive seam the metric cells use.
    function test_focus_cell_hover_narrates_the_state_it_would_toggle(): void {
        const cell = createTemporaryObject(focusCellComponent, this, {
            available: true, dnd: false, hoverX: 12
        });
        const tip = tooltipOf(cell);
        verify(tip !== null);
        compare(tip.visible, false);

        cell.hoverActive = true;
        tryCompare(tip, "opened", true);
        verify(cell.tooltip.indexOf("click to silence") !== -1);

        cell.dnd = true;
        verify(cell.tooltip.indexOf("silenced") !== -1);

        // The unreachable cell keeps a tooltip: the click is what wakes mako.
        cell.dnd = false;
        cell.available = false;
        verify(cell.tooltip.indexOf("unreachable") !== -1);

        cell.hoverActive = false;
        tryCompare(tip, "opened", false);
    }

    function test_focus_cell_reflects_state_in_glyph_and_color(): void {
        const cell = createTemporaryObject(focusCellComponent, this, {
            available: true, dnd: false
        });
        const offText = cell.displayText;
        verify(offText.length > 0);
        verify(Qt.colorEqual(cell.displayColor, testCase.themeColors.text_dim));
        cell.dnd = true;
        verify(Qt.colorEqual(cell.displayColor, testCase.themeColors.accent));
        // The two states must be distinguishable by glyph when the icon font
        // exists; without it both fall back to the label and color carries it.
        if (cell.iconAvailable)
            verify(cell.displayText !== offText);
        else
            compare(cell.displayText, "DND");
    }

    Component {
        id: stripComponent

        WorkspaceStrip {
            screenName: "DP-1"
            candidate: "segmented"
            themeColors: testCase.themeColors
            workspaces: [
                {
                    id: 4,
                    name: "Deep work",
                    monitor: "DP-1",
                    active: true,
                    claude: 1,
                    codex: 0,
                    clients: [{
                        address: "0xa", class: "wezterm", icon: "terminal",
                        label: "WezTerm", title: "chezmoi", terminal: true,
                        tabs: 2, claude: 1, codex: 0, activities: []
                    }]
                },
                {
                    id: 7,
                    name: "Mail",
                    monitor: "DP-1",
                    active: false,
                    claude: 0,
                    codex: 0,
                    clients: [{
                        address: "0xb", class: "chrome", icon: "chrome",
                        label: "Chrome", title: "Inbox", terminal: false,
                        tabs: 1, claude: 0, codex: 0, activities: []
                    }]
                },
                {
                    id: 9,
                    name: "Other screen",
                    monitor: "DP-2",
                    active: false,
                    claude: 0,
                    codex: 0,
                    clients: [{
                        address: "0xc", class: "zed", icon: "zed",
                        label: "Zed", title: "notes", terminal: false,
                        tabs: 1, claude: 0, codex: 0, activities: []
                    }]
                }
            ]
        }
    }

    function test_strip_shows_only_this_screens_workspaces(): void {
        const strip = createTemporaryObject(stripComponent, this);
        verify(strip !== null);
        compare(strip.monitorWorkspaceIds.length, 2);
        compare(strip.chipAt(0).workspaceData.id, 4);
        compare(strip.chipAt(1).workspaceData.id, 7);
        compare(strip.chipAt(2), null);
    }

    function test_rename_flow_targets_the_hovered_chip(): void {
        const strip = createTemporaryObject(stripComponent, this, {
            homeDir: "/home/test"
        });
        verify(strip !== null);
        const commands = [];
        strip.runCommand = command => commands.push(command);
        let startedId = -1;
        let finishedId = -1;
        strip.renameStarted.connect(workspaceId => startedId = workspaceId);
        strip.renameFinished.connect(workspaceId => finishedId = workspaceId);

        const chip = strip.chipAt(1);
        chip.beginRename();
        compare(startedId, 7);

        strip.editingWorkspaceId = 7;
        compare(strip.chipAt(1).editing, true);
        compare(strip.chipAt(0).editing, false);

        chip.submitRename("focus");
        compare(finishedId, 7);
        compare(commands.length, 1);
        compare(commands[0][0], "/home/test/.local/bin/rename-hypr-workspace");
        compare(commands[0][1], "7");
        compare(commands[0][2], "focus");
    }

    function test_snapshot_churn_keeps_chip_instances_and_updates_data(): void {
        const strip = createTemporaryObject(stripComponent, this);
        verify(strip !== null);
        const originalChip = strip.chipAt(0);
        const untouchedData = strip.chipAt(1).workspaceData;

        const updated = JSON.parse(JSON.stringify(strip.workspaces));
        updated[0].clients[0].title = "statusbar";
        strip.workspaces = updated;

        verify(strip.chipAt(0) === originalChip);
        compare(strip.chipAt(0).workspaceData.clients[0].title, "statusbar");
        verify(strip.chipAt(1).workspaceData === untouchedData);
    }

    function test_membership_change_rebuilds_only_the_id_model(): void {
        const strip = createTemporaryObject(stripComponent, this);
        verify(strip !== null);
        const shrunk = strip.workspaces.filter(workspace => workspace.id !== 7);
        strip.workspaces = shrunk;
        compare(strip.monitorWorkspaceIds.length, 1);
        compare(strip.chipAt(0).workspaceData.id, 4);
        compare(strip.chipAt(1), null);
    }

    function test_usage_history_resamples_onto_an_even_time_grid(): void {
        const samples = [
            { at: 1000, percent: 10, secondaryPercent: 1 },
            { at: 1500, percent: 20, secondaryPercent: null },
            { at: 2000, percent: 30, secondaryPercent: 3 }
        ];
        // A quota reading holds until the next one replaces it.
        compare(StatusGraph.resample(samples, "percent", 2000, 1000, 5),
            [10, 10, 20, 20, 30]);
        // Buckets before the first reading stay empty rather than inventing a
        // value, so a young history draws only where it was measured.
        compare(StatusGraph.resample(samples, "percent", 2500, 2000, 5),
            [null, 10, 20, 30, 30]);
        // A missing sub-reading blanks its buckets without shifting the rest.
        compare(StatusGraph.resample(samples, "secondaryPercent", 2000, 1000, 5),
            [1, 1, null, null, 3]);
        compare(StatusGraph.resample([], "percent", 2000, 1000, 5),
            [null, null, null, null, null]);
        compare(StatusGraph.resample(null, "percent", 2000, 1000, 5), []);
        compare(StatusGraph.resample(samples, "percent", 2000, 1000, 1), []);
    }

    function test_usage_burn_rate_measures_a_trailing_window(): void {
        // Ten-minute buckets with an hour of lookback: six buckets back, so
        // +1% per bucket reads as 6% per hour once the lookback is available.
        compare(StatusGraph.ratePerHour([0, 1, 2, 3, 4, 5, 6, 7], 600, 3600),
            [null, null, null, null, null, null, 6, 6]);
        // A quota reset clamps to zero rather than reporting negative burn.
        compare(StatusGraph.ratePerHour([50, 0], 1800, 1800), [null, 0]);
        // Gaps in the source stay gaps in the rate.
        compare(StatusGraph.ratePerHour([null, 2, 8], 1800, 1800), [null, null, 12]);
        compare(StatusGraph.ratePerHour([], 600, 3600), []);
    }

    function test_tooltip_series_replace_the_single_history_graph(): void {
        const single = createTemporaryObject(themedTooltipComponent, this, {
            history: [1, 2, 3]
        });
        const multi = createTemporaryObject(themedTooltipComponent, this, {
            history: [1, 2, 3],
            series: [
                { label: "RATE", values: [0, 120, 60], smoothed: true },
                { label: "TOTAL", values: [40, 41], smoothed: false },
                { label: "EMPTY", values: [7], smoothed: false }
            ]
        });
        verify(single !== null);
        verify(multi !== null);
        compare(single.normalizedSeries.length, 1);
        compare(single.normalizedSeries[0].label, "");
        compare(multi.normalizedSeries.length, 2);
        compare(multi.normalizedSeries[0].label, "RATE");
        compare(multi.normalizedSeries[0].smoothed, true);
        compare(multi.normalizedSeries[1].label, "TOTAL");
        compare(multi.showsGraph, true);
    }

    function test_tooltip_anchors_where_the_pointer_arrived(): void {
        const tip = createTemporaryObject(themedTooltipComponent, this, {
            pointerX: 70
        });
        verify(tip !== null);
        tip.shown = true;
        compare(tip.anchor.rect.x, 70);
        // Moving within the host does not drag the hint along behind the
        // cursor; it stays where the pointer first arrived.
        tip.pointerX = 20;
        compare(tip.anchor.rect.x, 70);
        // The next hover anchors afresh.
        tip.shown = false;
        tip.shown = true;
        compare(tip.anchor.rect.x, 20);
        // A hint with nothing to hang from never shows.
        wait(150);
        compare(tip.opened, false);
    }

    function test_tooltip_anchor_waits_for_a_pointer_reading(): void {
        const cell = createTemporaryObject(metricComponent, this, {
            value: 42,
            tooltip: "Total CPU use"
        });
        verify(cell !== null);
        const tip = tooltipOf(cell);
        // Hover can be reported before the pointer position is, so until one
        // arrives the hint centres on the cell rather than jumping to its edge.
        cell.hoverActive = true;
        compare(tip.anchorX, cell.width / 2);
        cell.hoverX = 12;
        compare(tip.anchorX, 12);
        // And that first reading is the one it keeps.
        cell.hoverX = 80;
        compare(tip.anchorX, 12);
    }

    // A workspace holding two Claude sessions and one Codex session, each in
    // the requested run state.
    function agentWorkspace(claudeState: string, codexState: string): var {
        return {
            id: 3,
            name: "Agents",
            monitor: "DP-1",
            active: false,
            claude: 2,
            codex: 1,
            clients: [{
                address: "0xd", class: "ghostty", icon: "terminal",
                label: "Ghostty", title: "repos", terminal: true, tabs: 3,
                claude: 2, codex: 1,
                activities: [
                    { kind: "claude", state: claudeState, title: "statusbar" },
                    { kind: "claude", state: "working", title: "notes" },
                    { kind: "codex", state: codexState, title: "review" }
                ]
            }]
        };
    }

    function sessionCountOf(item: var, kind: string): var {
        const pending = [item];
        while (pending.length > 0) {
            const node = pending.shift();
            if (node === null || typeof node !== "object")
                continue;
            if ("countColor" in node && node.kind === kind)
                return node;
            const children = node.data;
            if (children === undefined || children === null)
                continue;
            for (let index = 0; index < children.length; index += 1)
                pending.push(children[index]);
        }
        return null;
    }

    function tooltipOf(item: var): var {
        for (let index = 0; index < item.data.length; index += 1) {
            const child = item.data[index];
            if (child !== null && typeof child === "object" && "anchorX" in child)
                return child;
        }
        return null;
    }

    function test_metric_cell_hover_opens_and_closes_its_tooltip(): void {
        const cell = createTemporaryObject(metricComponent, this, {
            value: 42,
            tooltip: "Total CPU use",
            history: [10, 20, 30],
            smoothHistory: true,
            hoverX: 61
        });
        verify(cell !== null);
        const tip = tooltipOf(cell);
        verify(tip !== null);
        compare(tip.visible, false);

        cell.hoverActive = true;
        tryCompare(tip, "opened", true);
        compare(tip.anchorX, 61);
        compare(tip.anchor.rect.x, 61);
        // Hints hang below the cell they describe, never over it.
        compare(tip.anchor.rect.y, cell.height + tip.gap);
        compare(tip.showsGraph, true);

        cell.hoverActive = false;
        tryCompare(tip, "opened", false);
    }

    function test_metric_cell_without_tooltip_text_never_opens(): void {
        const cell = createTemporaryObject(metricComponent, this, {
            value: 42,
            tooltip: ""
        });
        verify(cell !== null);
        cell.hoverActive = true;
        wait(150);
        compare(tooltipOf(cell).opened, false);
    }

    function usageSamples(now: var): var {
        const samples = [];
        // Five-minute readings across the plotted window, climbing 1% each:
        // steady consumption of 12% per hour.
        for (let index = 0; index <= 72; index += 1) {
            samples.push({
                at: now - (72 - index) * 300,
                percent: index,
                secondaryPercent: index
            });
        }
        return samples;
    }

    function test_usage_cell_graphs_both_windows_and_the_burn_rate(): void {
        const now = 1800000000;
        const cell = createTemporaryObject(usageCellComponent, this, {
            nowEpoch: now,
            usage: {
                percent: 72,
                resetsAt: now + 3600,
                windowMinutes: 10080,
                secondaryPercent: 72,
                secondaryResetsAt: now + 600,
                secondaryWindowMinutes: 300,
                history: usageSamples(now)
            }
        });
        verify(cell !== null);
        const tip = tooltipOf(cell);
        verify(tip !== null);

        cell.hoverActive = true;
        tryCompare(tip, "opened", true);
        compare(tip.normalizedSeries.length, 3);
        compare(tip.normalizedSeries[0].label, "1-WEEK · % USED");
        compare(tip.normalizedSeries[1].label, "5-HOUR · % USED");
        compare(tip.normalizedSeries[2].label, "BURN RATE · % PER HOUR");
        // Each graph is captioned with the horizon it covers, and the fast
        // window gets a tighter one than the slow window.
        compare(tip.normalizedSeries[0].span, "4h ago");
        compare(tip.normalizedSeries[1].span, "1h ago");
        compare(tip.normalizedSeries[2].span, "4h ago");
        // The plot ends at the newest reading, not at an interpolated point.
        const cumulative = tip.normalizedSeries[0].values;
        compare(cumulative[cumulative.length - 1], 72);
        // 1% per five minutes is 12%/hour. Readings hold until replaced, so
        // the lookback rounds out to the sample cadence rather than landing
        // exactly on an hour.
        const rate = tip.normalizedSeries[2].values;
        verify(rate[rate.length - 1] > 11 && rate[rate.length - 1] < 14);

        cell.hoverActive = false;
        tryCompare(tip, "opened", false);
    }

    function test_usage_cell_without_history_shows_no_graph(): void {
        const cell = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: 52, resetsAt: 1800003600, windowMinutes: 10080 }
        });
        verify(cell !== null);
        const tip = tooltipOf(cell);
        verify(tip !== null);
        compare(tip.showsGraph, false);
    }

    function test_workspace_chip_hover_opens_tooltip_unless_busy(): void {
        const strip = createTemporaryObject(stripComponent, this);
        verify(strip !== null);
        const chip = strip.chipAt(0);
        const tip = tooltipOf(chip);
        verify(tip !== null);

        chip.hoverActive = true;
        tryCompare(tip, "opened", true);

        chip.hoverActive = false;
        tryCompare(tip, "opened", false);
    }

    function test_bar_stays_down_while_it_is_in_use(): void {
        const hide = createTemporaryObject(autoHideComponent, this);
        verify(hide !== null);
        // Disabled, the bar is simply always there.
        compare(hide.revealed, true);
        hide.pointerOnBar = true;
        hide.enabled = true;
        compare(hide.revealed, true);

        // Enabling with the pointer away withdraws it.
        hide.pointerOnBar = false;
        tryCompare(hide, "revealed", false);

        // Touching the trigger strip brings it down, and it stays down once
        // the pointer moves off the strip onto the bar itself.
        hide.pointerOnStrip = true;
        compare(hide.revealed, true);
        hide.pointerOnBar = true;
        hide.pointerOnStrip = false;
        compare(hide.revealed, true);

        // An open menu holds it down even with the pointer gone.
        hide.pinned = true;
        hide.pointerOnBar = false;
        wait(120);
        compare(hide.revealed, true);
        hide.pinned = false;
        tryCompare(hide, "revealed", false);

        // Turning the setting off restores it immediately.
        hide.enabled = false;
        compare(hide.revealed, true);
    }

    function test_bar_survives_the_pointer_crossing_a_seam(): void {
        const hide = createTemporaryObject(autoHideComponent, this, {
            enabled: true,
            pointerOnStrip: true
        });
        verify(hide !== null);
        compare(hide.revealed, true);
        // A gap of a few frames between leaving the strip and entering the
        // bar must not make it flicker away.
        hide.pointerOnStrip = false;
        hide.pointerOnBar = true;
        wait(80);
        compare(hide.revealed, true);
    }

    function test_settings_menu_asks_for_the_opposite_of_what_is_set(): void {
        const menu = createTemporaryObject(settingsMenuComponent, this);
        verify(menu !== null);
        const seen = [];
        menu.autoHideRequested.connect(value => seen.push(value));

        // The menu never writes the setting itself; it reports the intent and
        // renders whatever comes back.
        menu.toggleAutoHide();
        compare(seen, [true]);
        compare(menu.autoHide, false);

        menu.autoHide = true;
        menu.toggleAutoHide();
        compare(seen, [true, false]);
    }

    function test_numeric_column_does_not_move_with_digit_count(): void {
        const oneDigit = metricAt(5);
        const twoDigits = metricAt(55);
        const threeDigits = metricAt(100);
        compare(oneDigit.valueColumnX, twoDigits.valueColumnX);
        compare(twoDigits.valueColumnX, threeDigits.valueColumnX);
        compare(oneDigit.valueColumnRight, threeDigits.valueColumnRight);
    }

    function test_explicit_severity_and_units_keep_the_same_value_column(): void {
        const temperature = createTemporaryObject(metricComponent, this, {
            value: 86,
            suffix: "°",
            severity: 2
        });
        const disconnected = createTemporaryObject(metricComponent, this, {
            formattedValue: "OFF",
            severity: 1
        });
        verify(temperature !== null);
        verify(disconnected !== null);
        compare(temperature.displayText, "86°");
        compare(temperature.displayColor.toString(), "#fb4934");
        compare(disconnected.displayText, "OFF");
        compare(disconnected.displayColor.toString(), "#fabd2f");
        compare(temperature.valueColumnX, disconnected.valueColumnX);
        compare(temperature.valueColumnRight, disconnected.valueColumnRight);
    }

    function test_malformed_workspace_payload_is_bounded_and_safe(): void {
        const raw = [];
        raw.push(null);
        raw.push({ id: -4, clients: [] });
        raw.push({
            id: 2,
            clients: [{ icon: null, class: null, tabs: -10 }, "broken"],
            claude: Number.POSITIVE_INFINITY
        });
        for (let index = 0; index < 100; index += 1)
            raw.push({ id: index + 3, clients: [{}] });
        raw.push({ id: 999, clients: [] });

        const normalized = Sanitizer.normalizeWorkspaces(raw);
        compare(normalized.length, 64);
        compare(normalized[0].id, 2);
        compare(normalized[0].name, "2");
        compare(normalized[0].clients[0].icon, "application-x-executable");
        compare(normalized[0].clients[0].class, "application");
        compare(normalized[0].clients[0].tabs, 1);
        compare(normalized[0].claude, 0);
        verify(normalized.every(workspace => workspace.clients.length > 0));
    }

    function test_agent_activities_are_bounded_and_states_are_normalized(): void {
        const activities = [];
        activities.push({ kind: "codex", state: "attention", title: "review" });
        activities.push({ kind: "claude", state: "unknown", title: "x".repeat(500) });
        activities.push({ kind: "forged", state: "working", title: "shell" });
        for (let index = 0; index < 100; index += 1)
            activities.push({ kind: "process", title: "task " + index });
        const normalized = Sanitizer.normalizeWorkspaces([{
            id: 1,
            clients: [{
                label: "WezTerm",
                title: "chezmoi",
                activities: activities
            }]
        }]);
        const client = normalized[0].clients[0];
        compare(client.label, "WezTerm");
        compare(client.title, "chezmoi");
        compare(client.activities.length, 32);
        compare(client.activities[0].state, "attention");
        compare(client.activities[1].state, "idle");
        compare(client.activities[1].title.length, 160);
        compare(client.activities[2].kind, "process");
        compare(client.activities[2].state, "");
    }

    function test_tooltips_use_theme_and_human_agent_states(): void {
        const themed = createTemporaryObject(themedTooltipComponent, this);
        const workspace = createTemporaryObject(workspaceTooltipComponent, this);
        verify(themed !== null);
        verify(workspace !== null);
        compare(themed.surfaceColor.toString(), "#4b4840");
        compare(workspace.surfaceColor.toString(), "#4b4840");
        compare(themed.delay, 90);
        compare(workspace.delay, 0);
        compare(workspace.windowSummary, "1 window");
        compare(workspace.agentSummary, "3 agents");
        compare(workspace.stateLabel("working"), "Running");
        compare(workspace.stateLabel("idle"), "Idle");
        compare(workspace.stateLabel("attention"), "Awaiting input");
        // A waiting session is red wherever it appears: this row label and the
        // counts on the chip.
        compare(workspace.stateColor("attention").toString(), "#fb4934");
    }

    function test_tooltip_agent_count_alerts_only_while_input_is_awaited(): void {
        // The fixture workspace has a Claude session in "attention".
        const waiting = createTemporaryObject(workspaceTooltipComponent, this);
        verify(waiting !== null);
        compare(waiting.agentsAwaitInput, true);
        compare(waiting.agentSummaryColor.toString(), "#fb4934");

        const busy = createTemporaryObject(workspaceTooltipComponent, this, {
            workspaceData: testCase.agentWorkspace("working", "working")
        });
        verify(busy !== null);
        compare(busy.agentsAwaitInput, false);
        compare(busy.agentSummaryColor.toString(), "#a89984");
    }

    function test_chip_session_count_alerts_for_the_agent_that_is_waiting(): void {
        const chip = createTemporaryObject(sessionChipComponent, this);
        verify(chip !== null);
        const claudeCount = sessionCountOf(chip, "claude");
        const codexCount = sessionCountOf(chip, "codex");
        verify(claudeCount !== null);
        verify(codexCount !== null);

        // Both agents running: each count keeps its own resting colour.
        compare(claudeCount.countColor.toString(), "#fea45c");
        compare(codexCount.countColor.toString(), "#ebdbb2");

        // Only the waiting agent's count alerts.
        chip.workspaceData = testCase.agentWorkspace("attention", "working");
        compare(claudeCount.countColor.toString(), "#fb4934");
        compare(codexCount.countColor.toString(), "#ebdbb2");

        chip.workspaceData = testCase.agentWorkspace("working", "attention");
        compare(claudeCount.countColor.toString(), "#fea45c");
        compare(codexCount.countColor.toString(), "#fb4934");

        // An idle session is not waiting on anyone.
        chip.workspaceData = testCase.agentWorkspace("idle", "idle");
        compare(claudeCount.countColor.toString(), "#fea45c");
        compare(codexCount.countColor.toString(), "#ebdbb2");
    }

    function test_a_plain_process_never_counts_as_awaiting_input(): void {
        // Only agent activities carry a run state; a process row with a
        // forged one must not turn the counts red.
        const workspace = testCase.agentWorkspace("working", "working");
        workspace.clients[0].activities.push({
            kind: "process", state: "attention", title: "rsync"
        });
        compare(StatusFormat.sessionsAwaitInput(workspace.clients, ""), false);
    }

    function test_malformed_metrics_are_bounded_before_rendering(): void {
        const base = {
            cpu: 5,
            ram: 10,
            io: 20,
            gpu: 30,
            laptop: false,
            battery: null,
            batteryState: "",
            wifi: null,
            wifiConnected: false,
            cpuTemp: null,
            gpuTemp: null,
            ioTooltip: "ok",
            batteryTooltip: "ok",
            wifiTooltip: "ok"
        };
        const normalized = Sanitizer.normalizeMetrics(base, {
            cpu: "9".repeat(10000),
            ram: Number.POSITIVE_INFINITY,
            io: 900,
            gpu: { percent: 90 },
            laptop: "yes",
            battery: -50,
            batteryState: { status: "charging" },
            wifi: 61,
            wifiConnected: true,
            cpuTemp: 20,
            gpuTemp: 900,
            ioTooltip: "x".repeat(10000)
        });
        compare(normalized.cpu, 5);
        compare(normalized.ram, 10);
        compare(normalized.io, 100);
        compare(normalized.gpu, 30);
        compare(normalized.laptop, false);
        compare(normalized.battery, 0);
        compare(normalized.batteryState, "");
        compare(normalized.wifi, 61);
        compare(normalized.wifiConnected, true);
        compare(normalized.cpuTemp, null);
        compare(normalized.gpuTemp, null);
        compare(normalized.ioTooltip.length, 512);
    }

    function test_usage_payload_is_bounded_and_nullable(): void {
        const base = {
            claude: {
                percent: 12,
                resetsAt: 1800000600,
                windowMinutes: 300,
                secondaryPercent: null,
                secondaryResetsAt: null,
                secondaryWindowMinutes: null
            },
            codex: {
                percent: null,
                resetsAt: null,
                windowMinutes: null,
                secondaryPercent: null,
                secondaryResetsAt: null,
                secondaryWindowMinutes: null
            }
        };
        const normalized = Sanitizer.normalizeUsage(base, {
            claude: {
                percent: 900,
                resetsAt: Number.POSITIVE_INFINITY,
                windowMinutes: "five hours"
            },
            codex: {
                percent: null,
                resetsAt: null,
                windowMinutes: null
            },
            extra: "ignored"
        });
        compare(normalized.claude.percent, 100);
        compare(normalized.claude.resetsAt, 1800000600);
        compare(normalized.claude.windowMinutes, 300);
        compare(normalized.codex.percent, null);
        compare(Object.keys(normalized).length, 2);
    }

    function test_usage_columns_are_stable_for_empty_and_three_digit_values(): void {
        const low = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: 5, resetsAt: 1800000600, windowMinutes: 300 }
        });
        const full = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: 100, resetsAt: 1800000600, windowMinutes: 300 }
        });
        const empty = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: null, resetsAt: null, windowMinutes: null }
        });
        verify(low !== null);
        verify(full !== null);
        verify(empty !== null);
        compare(low.percentColumnX, full.percentColumnX);
        compare(full.percentColumnX, empty.percentColumnX);
        compare(low.resetColumnX, full.resetColumnX);
        compare(full.resetColumnX, empty.resetColumnX);
        compare(full.percentText, "100%");
        compare(empty.percentText, "--");
        verify(low.resetText.indexOf("↻ ") === 0);
        compare(empty.resetText, "waiting");
    }

    function test_usage_reset_is_a_live_countdown(): void {
        const cell = createTemporaryObject(usageCellComponent, this, {
            nowEpoch: 1800000000,
            usage: {
                percent: 40,
                resetsAt: 1800445260,
                windowMinutes: 10080
            }
        });
        verify(cell !== null);
        compare(cell.resetText, "↻ 5d 3h 41m");
        cell.nowEpoch = 1800445260;
        compare(cell.resetText, "↻ <1m");
    }

    function test_usage_color_reflects_consumed_quota_thresholds(): void {
        const low = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: 24, resetsAt: 1800000600, windowMinutes: 300 }
        });
        const warning = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: 76, resetsAt: 1800000600, windowMinutes: 300 }
        });
        const critical = createTemporaryObject(usageCellComponent, this, {
            usage: { percent: 90, resetsAt: 1800000600, windowMinutes: 300 }
        });
        verify(low !== null);
        verify(warning !== null);
        verify(critical !== null);
        compare(low.displayColor.toString(), "#ebdbb2");
        compare(warning.displayColor.toString(), "#fabd2f");
        compare(critical.displayColor.toString(), "#fb4934");
    }

    function test_2560_layout_keeps_maximum_telemetry_clear_of_clock(): void {
        const width = 2560;
        const clockWidth = 180;
        const metricCount = 6;
        const metricWidth = 96;
        const rightMargin = 12;
        const minimumGap = 12;
        verify(StatusLayout.telemetryClearsClock(
            width,
            clockWidth,
            metricCount,
            metricWidth,
            rightMargin,
            minimumGap
        ));
        verify(StatusLayout.telemetryLeft(width, metricCount, metricWidth, rightMargin)
            >= StatusLayout.clockRight(width, clockWidth) + minimumGap);
    }

    function test_2560_layout_keeps_full_usage_cluster_clear_of_clock(): void {
        const width = 2560;
        const clockWidth = 180;
        // Six cells, both hot-temperature extensions, both full usage cells.
        const rightRegionWidth = 6 * 96 + 2 * 34 + 2 * 188;
        verify(StatusLayout.rightRegionClearsClock(
            width,
            clockWidth,
            rightRegionWidth,
            12,
            12
        ));
    }

    function test_1920_layout_uses_compact_usage_without_covering_clock(): void {
        const width = 1920;
        const clockWidth = 180;
        const fullRegionWidth = 6 * 96 + 2 * 34 + 2 * 188;
        const compactRegionWidth = 6 * 96 + 2 * 34 + 2 * 39;
        verify(!StatusLayout.rightRegionClearsClock(
            width,
            clockWidth,
            fullRegionWidth,
            12,
            12
        ));
        verify(StatusLayout.rightRegionClearsClock(
            width,
            clockWidth,
            compactRegionWidth,
            12,
            12
        ));
    }

    readonly property string bodyColor: "#ebdbb2"
    readonly property string dimColor: "#a89984"

    function test_metric_value_color_reddens_above_75_and_ambers_from_50(): void {
        const body = testCase.bodyColor;
        compare(StatusSeverity.valueColor(null, body), body);
        compare(StatusSeverity.valueColor(undefined, body), body);
        compare(StatusSeverity.valueColor(0, body), body);
        compare(StatusSeverity.valueColor(49, body), body);
        compare(StatusSeverity.valueColor(49.9, body), body);
        compare(StatusSeverity.valueColor(50, body), "#fabd2f");
        compare(StatusSeverity.valueColor(75, body), "#fabd2f");
        compare(StatusSeverity.valueColor(75.1, body), "#fb4934");
        compare(StatusSeverity.valueColor(76, body), "#fb4934");
        compare(StatusSeverity.valueColor(100, body), "#fb4934");
    }

    function test_explicit_severity_overrides_the_value_thresholds(): void {
        const body = testCase.bodyColor;
        // A forced level ignores the reading entirely, in both directions.
        compare(StatusSeverity.severityColor(100, 0, body), body);
        compare(StatusSeverity.severityColor(0, 1, body), "#fabd2f");
        compare(StatusSeverity.severityColor(0, 2, body), "#fb4934");
        // -1 defers to the percentage thresholds.
        compare(StatusSeverity.severityColor(90, -1, body), "#fb4934");
        compare(StatusSeverity.severityColor(50, -1, body), "#fabd2f");
        compare(StatusSeverity.severityColor(null, -1, body), body);
        // Any other level is treated as no opinion rather than throwing.
        compare(StatusSeverity.severityColor(90, 7, body), "#fb4934");
    }

    function test_temperature_color_and_severity_break_at_85(): void {
        compare(StatusSeverity.temperatureColor(75), "#fabd2f");
        compare(StatusSeverity.temperatureColor(84), "#fabd2f");
        compare(StatusSeverity.temperatureColor(84.9), "#fabd2f");
        compare(StatusSeverity.temperatureColor(85), "#fb4934");
        compare(StatusSeverity.temperatureColor(120), "#fb4934");
        compare(StatusSeverity.temperatureSeverity(84), 1);
        compare(StatusSeverity.temperatureSeverity(85), 2);
        // The bar only asks once a temperature is already hot, so a missing
        // reading still warns rather than reading as normal.
        compare(StatusSeverity.temperatureSeverity(null), 1);
        compare(StatusSeverity.temperatureSeverity(undefined), 1);
    }

    function test_usage_percent_color_breaks_at_75_and_90_inclusive(): void {
        const body = testCase.bodyColor;
        const dim = testCase.dimColor;
        compare(StatusSeverity.usagePercentColor(null, body, dim), dim);
        compare(StatusSeverity.usagePercentColor(undefined, body, dim), dim);
        compare(StatusSeverity.usagePercentColor(0, body, dim), body);
        compare(StatusSeverity.usagePercentColor(74, body, dim), body);
        compare(StatusSeverity.usagePercentColor(74.9, body, dim), body);
        // Inclusive at 75, unlike the metric cell's exclusive 75.
        compare(StatusSeverity.usagePercentColor(75, body, dim), "#fabd2f");
        compare(StatusSeverity.usagePercentColor(89, body, dim), "#fabd2f");
        compare(StatusSeverity.usagePercentColor(89.9, body, dim), "#fabd2f");
        compare(StatusSeverity.usagePercentColor(90, body, dim), "#fb4934");
        compare(StatusSeverity.usagePercentColor(100, body, dim), "#fb4934");
    }

    function test_battery_severity_counts_down_through_25_and_10(): void {
        compare(StatusSeverity.batterySeverity(null), 1);
        compare(StatusSeverity.batterySeverity(undefined), 1);
        compare(StatusSeverity.batterySeverity(0), 2);
        compare(StatusSeverity.batterySeverity(10), 2);
        compare(StatusSeverity.batterySeverity(10.1), 1);
        compare(StatusSeverity.batterySeverity(11), 1);
        compare(StatusSeverity.batterySeverity(25), 1);
        compare(StatusSeverity.batterySeverity(25.1), 0);
        compare(StatusSeverity.batterySeverity(26), 0);
        compare(StatusSeverity.batterySeverity(100), 0);
    }

    function test_wifi_severity_warns_when_off_and_alerts_below_20(): void {
        // A disconnected radio is usually deliberate, so it warns.
        compare(StatusSeverity.wifiSeverity(false, 90), 1);
        compare(StatusSeverity.wifiSeverity(true, null), 1);
        compare(StatusSeverity.wifiSeverity(true, undefined), 1);
        compare(StatusSeverity.wifiSeverity(true, 0), 2);
        compare(StatusSeverity.wifiSeverity(true, 19), 2);
        compare(StatusSeverity.wifiSeverity(true, 19.9), 2);
        compare(StatusSeverity.wifiSeverity(true, 20), 1);
        compare(StatusSeverity.wifiSeverity(true, 39), 1);
        compare(StatusSeverity.wifiSeverity(true, 39.9), 1);
        compare(StatusSeverity.wifiSeverity(true, 40), 0);
        compare(StatusSeverity.wifiSeverity(true, 100), 0);
    }

    function test_window_label_reads_in_the_coarsest_whole_unit(): void {
        compare(StatusFormat.windowLabel(null), "current window");
        compare(StatusFormat.windowLabel(undefined), "current window");
        compare(StatusFormat.windowLabel(10080), "1-week window");
        compare(StatusFormat.windowLabel(20160), "2-week window");
        compare(StatusFormat.windowLabel(1440), "1-day window");
        compare(StatusFormat.windowLabel(4320), "3-day window");
        compare(StatusFormat.windowLabel(60), "1-hour window");
        compare(StatusFormat.windowLabel(300), "5-hour window");
        compare(StatusFormat.windowLabel(45), "45-minute window");
        compare(StatusFormat.windowLabel(1), "1-minute window");
        // Zero is divisible by everything; the widest unit wins.
        compare(StatusFormat.windowLabel(0), "0-week window");
    }

    function test_window_title_strips_the_noun_and_shouts(): void {
        compare(StatusFormat.windowTitle(300), "5-HOUR");
        compare(StatusFormat.windowTitle(10080), "1-WEEK");
        compare(StatusFormat.windowTitle(45), "45-MINUTE");
        compare(StatusFormat.windowTitle(null), "CURRENT");
    }

    function test_span_label_uses_hours_only_for_whole_hours(): void {
        compare(StatusFormat.spanLabel(3600), "1h ago");
        compare(StatusFormat.spanLabel(14400), "4h ago");
        compare(StatusFormat.spanLabel(1800), "30m ago");
        compare(StatusFormat.spanLabel(900), "15m ago");
        compare(StatusFormat.spanLabel(5400), "90m ago");
        compare(StatusFormat.spanLabel(0), "0h ago");
    }

    function test_full_reset_names_the_wall_clock_or_says_so(): void {
        compare(StatusFormat.fullReset(null), "reset unavailable");
        compare(StatusFormat.fullReset(undefined), "reset unavailable");
        const stamped = StatusFormat.fullReset(1800000600);
        verify(stamped.indexOf("resets ") === 0);
        // Same instant formatted the same way the component would.
        compare(stamped, "resets " + Qt.formatDateTime(
            new Date(1800000600 * 1000), "ddd d MMM yyyy HH:mm t"
        ));
    }

    function test_countdown_drops_units_as_the_reset_nears(): void {
        const now = 1800000000;
        compare(StatusFormat.countdownText(now + 445260, now), "5d 3h 41m");
        compare(StatusFormat.countdownText(now + 86400, now), "1d 0h 0m");
        compare(StatusFormat.countdownText(now + 3660, now), "1h 1m");
        compare(StatusFormat.countdownText(now + 120, now), "2m");
        compare(StatusFormat.countdownText(now + 59, now), "<1m");
        compare(StatusFormat.countdownText(now, now), "<1m");
        // A reset already in the past clamps to zero rather than counting up.
        compare(StatusFormat.countdownText(now - 90000, now), "<1m");
        // Anything that is not a real number is "not yet known".
        compare(StatusFormat.countdownText(null, now), "waiting");
        compare(StatusFormat.countdownText(undefined, now), "waiting");
        compare(StatusFormat.countdownText("1800000600", now), "waiting");
        compare(StatusFormat.countdownText(NaN, now), "waiting");
        compare(StatusFormat.countdownText(Infinity, now), "waiting");
    }

    function test_percent_and_reset_text_fall_back_when_unknown(): void {
        const now = 1800000000;
        compare(StatusFormat.percentText(null), "--");
        compare(StatusFormat.percentText(undefined), "--");
        compare(StatusFormat.percentText(0), "0%");
        compare(StatusFormat.percentText(100), "100%");
        compare(StatusFormat.resetText(null, now), "waiting");
        compare(StatusFormat.resetText(undefined, now), "waiting");
        compare(StatusFormat.resetText(now + 3660, now), "↻ 1h 1m");
    }

    function test_usage_tooltip_names_the_product_and_both_windows(): void {
        const reset = 1800000600;
        const secondaryReset = 1800086400;
        compare(
            StatusFormat.usageTooltipText("claude", null),
            "Claude Code usage unavailable · waiting for fresh account activity"
        );
        compare(
            StatusFormat.usageTooltipText("codex", { percent: null }),
            "Codex usage unavailable · waiting for fresh account activity"
        );
        compare(
            StatusFormat.usageTooltipText("codex", { percent: undefined }),
            "Codex usage unavailable · waiting for fresh account activity"
        );
        // Single window: one line, no newline.
        const single = StatusFormat.usageTooltipText("claude", {
            percent: 76,
            resetsAt: reset,
            windowMinutes: 300,
            secondaryPercent: null
        });
        compare(single, "Claude Code 5-hour window · 76% used · "
            + StatusFormat.fullReset(reset));
        verify(single.indexOf("\n") === -1);
        // Secondary window adds exactly one more line.
        const paired = StatusFormat.usageTooltipText("claude", {
            percent: 76,
            resetsAt: reset,
            windowMinutes: 300,
            secondaryPercent: 41,
            secondaryResetsAt: secondaryReset,
            secondaryWindowMinutes: 10080
        });
        compare(paired.split("\n").length, 2);
        compare(paired.split("\n")[1], "1-week window · 41% used · "
            + StatusFormat.fullReset(secondaryReset));
        // A missing secondary reset degrades in place rather than dropping it.
        const stampless = StatusFormat.usageTooltipText("claude", {
            percent: 76,
            resetsAt: null,
            windowMinutes: null,
            secondaryPercent: 41,
            secondaryResetsAt: null,
            secondaryWindowMinutes: null
        });
        compare(stampless, "Claude Code current window · 76% used · reset unavailable"
            + "\ncurrent window · 41% used · reset unavailable");
    }

    function test_agent_state_labels_and_colors_default_to_idle(): void {
        compare(StatusFormat.stateLabel("working"), "Running");
        compare(StatusFormat.stateLabel("attention"), "Awaiting input");
        compare(StatusFormat.stateLabel("idle"), "Idle");
        compare(StatusFormat.stateLabel("nonsense"), "Idle");
        compare(StatusFormat.stateLabel(""), "Idle");
        compare(StatusFormat.stateLabel(null), "Idle");
        compare(StatusFormat.stateLabel(undefined), "Idle");
        const theme = testCase.themeColors;
        compare(StatusFormat.stateColor("attention", theme), "#fb4934");
        compare(StatusFormat.stateColor("working", theme), theme.accent_light);
        compare(StatusFormat.stateColor("idle", theme), theme.text_dim);
        compare(StatusFormat.stateColor("nonsense", theme), theme.text_dim);
        compare(StatusFormat.stateColor(null, theme), theme.text_dim);
    }

    function test_activity_label_prefixes_the_agent_without_repeating_it(): void {
        compare(
            StatusFormat.activityLabel({ kind: "claude", title: "dotfiles" }),
            "Claude Code · dotfiles"
        );
        compare(
            StatusFormat.activityLabel({ kind: "codex", title: "chezmoi" }),
            "Codex · chezmoi"
        );
        // A title that is already the product name is not doubled up.
        compare(
            StatusFormat.activityLabel({ kind: "claude", title: "Claude Code" }),
            "Claude Code"
        );
        compare(
            StatusFormat.activityLabel({ kind: "codex", title: "Codex" }),
            "Codex"
        );
        // Non-agent kinds keep their bare title.
        compare(
            StatusFormat.activityLabel({ kind: "process", title: "cargo build" }),
            "cargo build"
        );
        compare(
            StatusFormat.activityLabel({ kind: "unknown", title: "" }),
            ""
        );
    }

    function test_focus_command_is_the_exact_hyprland_dispatch(): void {
        const command = StatusCommands.focusWorkspaceCommand(7);
        compare(command.length, 3);
        compare(command[0], "hyprctl");
        compare(command[1], "dispatch");
        compare(command[2], "hl.dsp.focus({ workspace = 7 })");
        // Ids arrive as numbers from Hyprland and as strings from the model.
        compare(
            StatusCommands.focusWorkspaceCommand("12")[2],
            "hl.dsp.focus({ workspace = 12 })"
        );
        compare(
            StatusCommands.focusWorkspaceCommand(-99)[2],
            "hl.dsp.focus({ workspace = -99 })"
        );
    }

    function test_rename_command_is_the_exact_helper_invocation(): void {
        const command = StatusCommands.renameWorkspaceCommand(
            "/home/test", 4, "Deep work"
        );
        compare(command.length, 3);
        compare(command[0], "/home/test/.local/bin/rename-hypr-workspace");
        compare(command[1], "4");
        compare(command[2], "Deep work");
        // The id is always stringified; the name is passed through verbatim,
        // including an empty reset and anything shell-hostile.
        compare(StatusCommands.renameWorkspaceCommand("/root", "9", "")[1], "9");
        compare(StatusCommands.renameWorkspaceCommand("/root", 9, "")[2], "");
        compare(
            StatusCommands.renameWorkspaceCommand("/root", 9, "a b; rm -rf /")[2],
            "a b; rm -rf /"
        );
        compare(
            StatusCommands.renameWorkspaceCommand("", 1, "x")[0],
            "/.local/bin/rename-hypr-workspace"
        );
    }

    function test_plot_geometry_reserves_the_gutter_and_axis_caption(): void {
        const captioned = StatusGraph.plotGeometry(224, 48, true);
        compare(captioned.plotWidth, 194);
        compare(captioned.top, 3);
        compare(captioned.bottom, 35);
        const bare = StatusGraph.plotGeometry(224, 48, false);
        compare(bare.plotWidth, 194);
        compare(bare.top, 3);
        compare(bare.bottom, 45);
    }

    function test_graph_x_spreads_samples_across_the_plot_width(): void {
        compare(StatusGraph.xFor(0, 5, 200), 0);
        compare(StatusGraph.xFor(2, 5, 200), 100);
        compare(StatusGraph.xFor(4, 5, 200), 200);
        compare(StatusGraph.xFor(1, 2, 194), 194);
    }

    function test_graph_y_inverts_the_value_within_the_band(): void {
        const range = { min: 0, max: 100 };
        compare(StatusGraph.yFor(100, range, 3, 35), 3);
        compare(StatusGraph.yFor(0, range, 3, 35), 35);
        compare(StatusGraph.yFor(50, range, 3, 35), 19);
        // Offset bands map their own min and max to the same edges.
        const offset = { min: 20, max: 24 };
        compare(StatusGraph.yFor(24, offset, 3, 35), 3);
        compare(StatusGraph.yFor(20, offset, 3, 35), 35);
        compare(StatusGraph.yFor(22, offset, 3, 35), 19);
    }

    function test_degenerate_range_is_unreachable_through_bounds(): void {
        // A zero-width band divides by zero, so bounds() guarantees one at
        // least 4 wide before any value is ever mapped.
        verify(!Number.isFinite(
            StatusGraph.yFor(5, { min: 5, max: 5 }, 3, 35)
        ));
        const flat = StatusGraph.bounds([5, 5, 5]);
        compare(flat.max - flat.min, 4);
        compare(StatusGraph.yFor(5, flat, 3, 35), 19);
        const single = StatusGraph.bounds([12]);
        compare(single.min, 10);
        compare(single.max, 14);
        compare(StatusGraph.bounds([]), null);
    }

    function test_tick_decimals_appear_only_for_narrow_bands(): void {
        compare(StatusGraph.tickDecimals({ min: 0, max: 100 }), 0);
        compare(StatusGraph.tickDecimals({ min: 0, max: 8 }), 0);
        compare(StatusGraph.tickDecimals({ min: 0, max: 7.9 }), 1);
        // The narrowest band bounds() can produce still gets a decimal.
        compare(StatusGraph.tickDecimals(StatusGraph.bounds([5, 5])), 1);
    }

    // The consumer side of the Python→QML wire contract: the same fixture is
    // asserted against the producers in tests/test_stream_contract.py, so
    // neither side can rename or drop a field without a test failing.
    function readContractFixture() {
        const request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl("fixtures/stream_contract.json"), false);
        request.send();
        verify(request.responseText.length > 0,
               "cannot read stream_contract.json — run qmltestrunner with "
               + "QML_XHR_ALLOW_FILE_READ=1 (see README)");
        return JSON.parse(request.responseText);
    }

    function test_contract_fixture_metrics_survive_the_sanitizer(): void {
        const fixture = readContractFixture();
        const base = {
            cpu: null, ram: null, io: null, gpu: null,
            laptop: false, battery: null, batteryState: "",
            wifi: null, wifiConnected: false, cpuTemp: null, gpuTemp: null,
            ioTooltip: "", batteryTooltip: "", wifiTooltip: ""
        };
        const normalized = Sanitizer.normalizeMetrics(base, fixture.hypr.metrics);
        for (const key of Object.keys(fixture.hypr.metrics))
            compare(normalized[key], fixture.hypr.metrics[key], "metrics." + key);
        const palette = Sanitizer.mergeObject({}, fixture.hypr.palette);
        compare(Object.keys(palette).sort().join(","),
                Object.keys(fixture.hypr.palette).sort().join(","));
    }

    function test_contract_fixture_workspaces_survive_the_sanitizer(): void {
        const fixture = readContractFixture();
        const normalized = Sanitizer.normalizeWorkspaces(fixture.hypr.workspaces);
        compare(normalized.length, 1);
        const workspace = normalized[0];
        const expected = fixture.hypr.workspaces[0];
        for (const key of ["id", "name", "monitor", "claude", "codex"])
            compare(workspace[key], expected[key], "workspace." + key);
        const client = workspace.clients[0];
        const expectedClient = expected.clients[0];
        for (const key of ["address", "class", "icon", "terminal", "label",
                           "title", "tabs", "claude", "codex"])
            compare(client[key], expectedClient[key], "client." + key);
        compare(client.activities.length, expectedClient.activities.length);
        for (let index = 0; index < client.activities.length; index += 1) {
            compare(client.activities[index].kind,
                    expectedClient.activities[index].kind);
            compare(client.activities[index].state,
                    expectedClient.activities[index].state);
            compare(client.activities[index].title,
                    expectedClient.activities[index].title);
        }
    }

    function test_contract_fixture_usage_survives_the_sanitizer(): void {
        const fixture = readContractFixture();
        const emptyProvider = {
            percent: null, resetsAt: null, windowMinutes: null,
            secondaryPercent: null, secondaryResetsAt: null,
            secondaryWindowMinutes: null
        };
        const normalized = Sanitizer.normalizeUsage(
            { claude: emptyProvider, codex: emptyProvider }, fixture.usage);
        for (const key of Object.keys(emptyProvider)) {
            compare(normalized.claude[key], fixture.usage.claude[key],
                    "claude." + key);
            compare(normalized.codex[key], fixture.usage.codex[key],
                    "codex." + key);
        }
        // Wire history triples [at, primary, secondary] become plot samples.
        compare(normalized.claude.history.length,
                fixture.usage.claude.history.length);
        for (let index = 0; index < normalized.claude.history.length; index += 1) {
            const sample = normalized.claude.history[index];
            const wire = fixture.usage.claude.history[index];
            compare(sample.at, wire[0]);
            compare(sample.percent, wire[1]);
            compare(sample.secondaryPercent, wire[2]);
        }
        compare(normalized.codex.history.length, 0);
    }
}
