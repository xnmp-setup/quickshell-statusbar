import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "StatusLayout.js" as StatusLayout
import "StatusIcons.js" as StatusIcons
import "StatusSeverity.js" as StatusSeverity

PanelWindow {
    id: bar

    required property bool barVisible
    required property string candidate
    required property var statusSource
    required property var settings
    required property int renameRequestSerial
    property int editingWorkspaceId: 0
    property real settingsMenuX: 0
    property bool renameRequestsReady: false
    readonly property var themeColors: statusSource.themeColors
    readonly property bool editingWorkspaceExists: editingWorkspaceId === 0
        || statusSource.workspaces.some(workspace => workspace.id === editingWorkspaceId
            && workspace.monitor === screen.name)
    readonly property bool showCpuTemp: statusSource.metrics.cpuTemp !== null
        && statusSource.metrics.cpuTemp !== undefined
    readonly property bool showGpuTemp: statusSource.metrics.gpuTemp !== null
        && statusSource.metrics.gpuTemp !== undefined
    readonly property bool showLaptop: statusSource.metrics.laptop === true
    readonly property int metricCellCount: 4 + (showLaptop ? 2 : 0)
    readonly property int metricCellWidth: 96
    // Hot temperatures widen their host cell instead of adding a cell.
    readonly property int temperatureExtraWidth: (showCpuTemp ? 34 : 0)
        + (showGpuTemp ? 34 : 0)
    readonly property int usageCellWidth: 188
    readonly property int compactUsageCellWidth: 39
    readonly property bool compactUsage: !StatusLayout.rightRegionClearsClock(
        width,
        clockCell.implicitWidth,
        metricCellCount * metricCellWidth + temperatureExtraWidth
            + 2 * usageCellWidth,
        12,
        12
    )
    // An auto-hiding bar withdraws off screen and claims no exclusive zone, so
    // windows fill the display exactly as they would with no bar at all.
    readonly property bool collapsed: !autoHide.revealed
    readonly property bool rightRegionClearsClock: StatusLayout.rightRegionClearsClock(
        width,
        clockCell.implicitWidth,
        rightRegion.implicitWidth,
        12,
        12
    )

    function temperatureSeverity(value: var): int {
        return StatusSeverity.temperatureSeverity(value);
    }

    function batterySeverity(value: var): int {
        return StatusSeverity.batterySeverity(value);
    }

    function wifiSeverity(connected: bool, value: var): int {
        return StatusSeverity.wifiSeverity(connected, value);
    }

    function beginFocusedWorkspaceRename(): void {
        const focusedWorkspace = Hyprland.focusedWorkspace;
        if (!focusedWorkspace)
            return;
        const belongsToBar = statusSource.workspaces.some(
            workspace => workspace.id === focusedWorkspace.id
                && workspace.monitor === screen.name
        );
        if (belongsToBar)
            editingWorkspaceId = focusedWorkspace.id;
    }

    onEditingWorkspaceExistsChanged: {
        if (!editingWorkspaceExists)
            editingWorkspaceId = 0;
    }
    onRenameRequestSerialChanged: {
        if (renameRequestsReady)
            beginFocusedWorkspaceRename();
    }

    Component.onCompleted: renameRequestsReady = true

    visible: barVisible
    implicitHeight: 40
    exclusiveZone: barVisible && !settings.autoHide ? 40 : 0
    // The bar paints its own background so the whole thing can fade out
    // together; the surface itself stays transparent.
    color: "transparent"
    focusable: editingWorkspaceId > 0
    // While withdrawn only the trigger strip accepts input, so clicks land on
    // whatever is behind the bar.
    mask: Region {
        item: bar.collapsed ? revealStrip : contentRoot
    }

    AutoHideController {
        id: autoHide

        enabled: bar.settings.autoHide
        pointerOnStrip: stripHover.hovered
        pointerOnBar: contentHover.hovered
        // Never withdraw out from under an open menu or a rename in progress.
        pinned: bar.editingWorkspaceId > 0 || settingsMenu.opened
    }

    Item {
        id: revealStrip

        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 2

        HoverHandler {
            id: stripHover
        }
    }

    HyprlandFocusGrab {
        id: renameFocusGrab

        windows: [bar]
        active: bar.editingWorkspaceId > 0
        onCleared: {
            if (bar.editingWorkspaceId > 0)
                bar.editingWorkspaceId = 0;
        }
    }

    anchors {
        top: true
        left: true
        right: true
    }

    Item {
        id: contentRoot

        width: bar.width
        height: bar.height
        y: bar.collapsed ? -height : 0
        opacity: bar.collapsed ? 0 : 1

        Behavior on y {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 130 }
        }

        HoverHandler {
            id: contentHover
        }

        Rectangle {
            anchors.fill: parent
            color: bar.themeColors.background
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: bar.themeColors.border
        }

        Item {
            id: workspaceViewport
            anchors {
                left: parent.left
                right: clockCell.left
                top: parent.top
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 12
            }
            clip: true

            WorkspaceStrip {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                workspaces: bar.statusSource.workspaces
                screenName: bar.screen.name
                candidate: bar.candidate
                themeColors: bar.themeColors
                editingWorkspaceId: bar.editingWorkspaceId
                hyprlandWorkspaces: Hyprland.workspaces.values
                homeDir: Quickshell.env("HOME")
                runCommand: command => Quickshell.execDetached(command)
                resolveIcon: name => Quickshell.iconPath(name)
                onRenameStarted: workspaceId => {
                    bar.editingWorkspaceId = workspaceId;
                }
                onRenameFinished: workspaceId => {
                    if (bar.editingWorkspaceId === workspaceId)
                        bar.editingWorkspaceId = 0;
                }
            }
        }

        ClockCell {
            id: clockCell
            anchors.centerIn: parent
            themeColors: bar.themeColors
            z: 2
            onMenuRequested: x => {
                bar.settingsMenuX = clockCell.mapToItem(contentRoot, x, 0).x;
                settingsMenu.shown = !settingsMenu.shown;
            }
        }

        SettingsMenu {
            id: settingsMenu

            themeColors: bar.themeColors
            hostItem: contentRoot
            pointerX: bar.settingsMenuX
            autoHide: bar.settings.autoHide
            onAutoHideRequested: value => bar.settings.setAutoHide(value)
            onDismissed: shown = false
        }

        RowLayout {
            id: rightRegion
            anchors {
                right: parent.right
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 0
            z: 1

            RowLayout {
                id: telemetry
                spacing: 0

                MetricCell {
                    label: "CPU"
                    value: bar.statusSource.metrics.cpu
                    temperature: bar.statusSource.metrics.cpuTemp
                    tooltip: bar.showCpuTemp
                        ? "Total CPU use · package temperature shown while 75°C or hotter"
                        : "Total CPU use"
                    themeColors: bar.themeColors
                    history: bar.statusSource.history.cpu
                    smoothHistory: true
                }
                MetricCell {
                    label: "RAM"
                    value: bar.statusSource.metrics.ram
                    tooltip: "Used memory, excluding readily reclaimable cache"
                    themeColors: bar.themeColors
                    history: bar.statusSource.history.ram
                }
                MetricCell {
                    label: "IO"
                    value: bar.statusSource.metrics.io
                    tooltip: bar.statusSource.metrics.ioTooltip || "Time tasks were stalled on disk I/O"
                    themeColors: bar.themeColors
                    history: bar.statusSource.history.io
                    smoothHistory: true
                }
                MetricCell {
                    label: "GPU"
                    value: bar.statusSource.metrics.gpu
                    temperature: bar.statusSource.metrics.gpuTemp
                    tooltip: bar.showGpuTemp
                        ? "Graphics processor use · temperature shown while 75°C or hotter"
                        : "Graphics processor use"
                    themeColors: bar.themeColors
                    history: bar.statusSource.history.gpu
                    smoothHistory: true
                }

                Loader {
                    active: bar.showLaptop
                    sourceComponent: MetricCell {
                        label: "WIFI"
                        iconText: StatusIcons.wifiIcon(
                            bar.statusSource.metrics.wifiConnected,
                            bar.statusSource.metrics.wifi
                        )
                        value: bar.statusSource.metrics.wifi
                        formattedValue: bar.statusSource.metrics.wifiConnected
                            && value !== null && value !== undefined ? value + "%" : "OFF"
                        severity: bar.wifiSeverity(bar.statusSource.metrics.wifiConnected, value)
                        tooltip: bar.statusSource.metrics.wifiTooltip || "Wi-Fi status unavailable"
                        themeColors: bar.themeColors
                        history: bar.statusSource.history.wifi
                        smoothHistory: true
                    }
                }
                Loader {
                    active: bar.showLaptop
                    sourceComponent: MetricCell {
                        label: "BAT"
                        iconText: StatusIcons.batteryIcon(
                            bar.statusSource.metrics.battery,
                            bar.statusSource.metrics.batteryState
                        )
                        value: bar.statusSource.metrics.battery
                        severity: bar.batterySeverity(value)
                        tooltip: bar.statusSource.metrics.batteryTooltip || "Battery status unavailable"
                        themeColors: bar.themeColors
                        history: bar.statusSource.history.battery
                    }
                }
            }

            UsageCell {
                provider: "claude"
                usage: bar.statusSource.usage.claude
                themeColors: bar.themeColors
                compact: bar.compactUsage
            }

            UsageCell {
                provider: "codex"
                usage: bar.statusSource.usage.codex
                themeColors: bar.themeColors
                compact: bar.compactUsage
                last: true
            }
        }
    }
}
