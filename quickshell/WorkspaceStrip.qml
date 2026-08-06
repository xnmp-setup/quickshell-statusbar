// The workspace chip strip. Free of Quickshell imports so behavioral tests
// can instantiate it with fake workspace data and injected side effects; the
// production shell (StatusBar) injects the Quickshell/Hyprland bindings.
import QtQuick
import QtQuick.Layouts

Item {
    id: strip

    required property var workspaces
    required property string screenName
    required property string candidate
    required property var themeColors
    property int editingWorkspaceId: 0
    // Live Hyprland workspace objects and shell side effects, injected.
    property var hyprlandWorkspaces: []
    property var runCommand: function (command) {}
    property var resolveIcon: function (name) { return ""; }
    property string homeDir: ""

    // Stable id-keyed model: reassigning the Repeater's model destroys every
    // chip (closing any open hover popup), so the id list only changes when
    // membership or order actually changes; chip content updates in place.
    property var monitorWorkspaceIds: []
    property string monitorWorkspaceIdsJson: "[]"

    signal renameStarted(int workspaceId)
    signal renameFinished(int workspaceId)

    function workspaceById(workspaceId: int): var {
        return workspaces.find(
            workspace => workspace.id === workspaceId && workspace.monitor === screenName
        ) || {
            id: workspaceId,
            name: String(workspaceId),
            monitor: screenName,
            active: false,
            clients: [],
            claude: 0,
            codex: 0
        };
    }

    function syncMonitorWorkspaceIds(): void {
        const ids = [];
        for (let index = 0; index < workspaces.length; index += 1) {
            const workspace = workspaces[index];
            if (workspace.monitor === screenName)
                ids.push(workspace.id);
        }
        const encoded = JSON.stringify(ids);
        if (encoded !== monitorWorkspaceIdsJson) {
            monitorWorkspaceIdsJson = encoded;
            monitorWorkspaceIds = ids;
        }
    }

    // Test/introspection helper: the live chip instance at a strip position.
    function chipAt(index: int): var {
        return chipRepeater.itemAt(index);
    }

    onWorkspacesChanged: syncMonitorWorkspaceIds()
    onScreenNameChanged: syncMonitorWorkspaceIds()
    Component.onCompleted: syncMonitorWorkspaceIds()

    implicitWidth: chipRow.implicitWidth
    implicitHeight: chipRow.implicitHeight

    RowLayout {
        id: chipRow
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        spacing: 8

        Repeater {
            id: chipRepeater
            model: strip.monitorWorkspaceIds

            WorkspaceChip {
                required property var modelData
                // String dedupe: the chip only re-reads its workspace when
                // that workspace's own content changed, so unrelated
                // snapshot churn cannot rebuild rows in an open tooltip.
                readonly property string workspaceJson: JSON.stringify(
                    strip.workspaceById(modelData)
                )

                workspaceData: JSON.parse(workspaceJson)
                candidate: strip.candidate
                themeColors: strip.themeColors
                editing: strip.editingWorkspaceId === modelData
                hyprlandWorkspaces: strip.hyprlandWorkspaces
                runCommand: strip.runCommand
                resolveIcon: strip.resolveIcon
                homeDir: strip.homeDir
                onRenameStarted: workspaceId => strip.renameStarted(workspaceId)
                onRenameFinished: strip.renameFinished(modelData)
            }
        }
    }
}
