// Deliberately free of Quickshell imports: every environment dependency is an
// injected property so behavioral tests can drive a real chip offscreen.
import QtQuick

Rectangle {
    id: chip

    required property var workspaceData
    required property string candidate
    required property var themeColors
    required property bool editing
    // Live Hyprland workspace objects; empty offline/in tests.
    property var hyprlandWorkspaces: []
    // Side effects injected by the shell (Quickshell in production).
    property var runCommand: function (command) {}
    property var resolveIcon: function (name) { return ""; }
    property string homeDir: ""

    readonly property bool segmented: candidate === "segmented"
    readonly property var liveWorkspace: hyprlandWorkspaces
        && typeof hyprlandWorkspaces.find === "function"
        ? hyprlandWorkspaces.find(workspace => workspace.id === workspaceData.id)
        : undefined
    readonly property bool active: liveWorkspace ? liveWorkspace.active : workspaceData.active === true
    readonly property string displayName: workspaceData.name
    readonly property color accent: themeColors.accent
    readonly property color textPrimary: themeColors.text
    readonly property color textSecondary: themeColors.text_dim

    // Overridable seam so tests can drive the real popup-open path; live it
    // mirrors the pointer MouseArea and the rename/menu suppression rules.
    property bool hoverActive: pointer.containsMouse && !editing && !contextMenu.opened

    signal renameStarted(int workspaceId)
    signal renameFinished

    function beginRename(): void {
        contextMenu.close();
        if (editing) {
            if (editorLoader.item)
                editorLoader.item.activate();
            return;
        }
        renameStarted(workspaceData.id);
    }

    function submitRename(name: string): void {
        runCommand([
            homeDir + "/.local/bin/rename-hypr-workspace",
            String(chip.workspaceData.id),
            name
        ]);
        renameFinished();
    }

    function openRenameMenu(): void {
        contextMenu.popup();
    }

    implicitWidth: content.implicitWidth + (segmented ? 14 : 18)
    implicitHeight: 34
    radius: segmented ? 4 : 6
    color: active
        ? themeColors.surface
        : Qt.darker(themeColors.surface, segmented ? 1.34 : 1.42)
    border.width: 1
    border.color: active ? themeColors.accent : themeColors.border

    Rectangle {
        visible: chip.active
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: chip.segmented ? 3 : 5
            rightMargin: chip.segmented ? 3 : 5
        }
        height: 2
        radius: 1
        color: chip.accent
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: chip.segmented ? 7 : 8

        Loader {
            id: editorLoader

            active: chip.editing
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            width: active && item ? item.implicitWidth : 0
            height: active && item ? item.implicitHeight : 0

            sourceComponent: WorkspaceNameEditor {
                initialText: chip.displayName
                highlighted: chip.active
                themeColors: chip.themeColors
                onSubmitted: name => chip.submitRename(name)
                onCancelled: chip.renameFinished()
            }
        }

        Rectangle {
            id: workspaceNameTile

            visible: chip.segmented && !chip.editing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(140, Math.max(22, workspaceNameSegmented.implicitWidth + 10))
            height: 24
            radius: 3
            color: chip.active
                ? chip.themeColors.accent
                : Qt.darker(chip.themeColors.surface, 1.18)

            Text {
                id: workspaceNameSegmented

                anchors.centerIn: parent
                width: workspaceNameTile.width - 10
                text: chip.displayName
                color: chip.active ? "#ffffff" : chip.textPrimary
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Text {
            id: workspaceNameInstrument

            visible: !chip.segmented && !chip.editing
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(140, implicitWidth)
            text: chip.displayName
            color: chip.active ? "#ffffff" : chip.textPrimary
            font.family: "Inter"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 18
            color: chip.active ? chip.themeColors.accent_light : chip.themeColors.border
            opacity: chip.active ? 0.65 : 1
        }

        Repeater {
            model: chip.workspaceData.clients

            Item {
                required property var modelData

                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: appRow.implicitWidth
                implicitHeight: 24

                Row {
                    id: appRow
                    anchors.centerIn: parent
                    spacing: 3

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18

                        Image {
                            id: appIcon
                            anchors.fill: parent
                            source: modelData.icon.startsWith("file:")
                                ? modelData.icon
                                : chip.resolveIcon(modelData.icon)
                            sourceSize.width: 18
                            sourceSize.height: 18
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                            mipmap: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: appIcon.status === Image.Error
                            radius: 4
                            color: Qt.darker(chip.themeColors.surface, 1.14)
                            border.width: 1
                            border.color: chip.themeColors.border

                            Text {
                                anchors.centerIn: parent
                                text: modelData.class.length > 0
                                    ? modelData.class.charAt(0).toUpperCase()
                                    : "·"
                                color: chip.themeColors.text_dim
                                font.family: "Inter"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        visible: modelData.terminal && modelData.tabs > 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: tabText.implicitWidth + 7
                        height: 17
                        radius: chip.segmented ? 2 : 4
                        color: Qt.darker(chip.themeColors.surface, chip.segmented ? 1.08 : 1.14)
                        border.width: 1
                        border.color: chip.themeColors.border

                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: modelData.tabs
                            color: chip.themeColors.text
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        SessionCount {
            visible: chip.workspaceData.claude > 0
            kind: "claude"
            count: chip.workspaceData.claude
            themeColors: chip.themeColors
        }

        SessionCount {
            visible: chip.workspaceData.codex > 0
            kind: "codex"
            count: chip.workspaceData.codex
            themeColors: chip.themeColors
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        enabled: !chip.editing
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                chip.openRenameMenu();
                return;
            }
            chip.runCommand([
                "hyprctl",
                "dispatch",
                "hl.dsp.focus({ workspace = " + chip.workspaceData.id + " })"
            ]);
        }
    }

    WorkspaceContextMenu {
        id: contextMenu

        x: 0
        y: chip.height + 4
        themeColors: chip.themeColors
        onRenameRequested: chip.beginRename()
    }

    WorkspaceToolTip {
        visible: chip.hoverActive
        workspaceData: chip.workspaceData
        themeColors: chip.themeColors
        pointerX: pointer.mouseX
    }

}
