import QtQuick
import QtQuick.Layouts
import "StatusFormat.js" as StatusFormat

HoverPopup {
    id: control

    required property var workspaceData
    readonly property int contentWidth: 388 - 2 * padding
    readonly property int visibleClientCount: Math.min(workspaceData.clients.length, 8)
    readonly property int agentCount: workspaceData.claude + workspaceData.codex
    readonly property string windowSummary: workspaceData.clients.length
        + (workspaceData.clients.length === 1 ? " window" : " windows")
    readonly property string agentSummary: agentCount
        + (agentCount === 1 ? " agent" : " agents")
    readonly property bool agentsAwaitInput: StatusFormat.sessionsAwaitInput(
        workspaceData.clients, ""
    )
    readonly property color agentSummaryColor: StatusFormat.attentionColor(
        agentsAwaitInput, themeColors.text_dim
    )

    function stateLabel(state: string): string {
        return StatusFormat.stateLabel(state);
    }

    function stateColor(state: string): color {
        return StatusFormat.stateColor(state, themeColors);
    }

    function activityLabel(activity: var): string {
        return StatusFormat.activityLabel(activity);
    }

    // Workspace contents are the primary hover interaction, so reveal them
    // immediately instead of inheriting the desktop tooltip pause.
    delay: 0
    padding: 12

    Column {
        id: contentColumn

        width: control.contentWidth
        spacing: 8

        RowLayout {
            width: parent.width
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: control.workspaceData.name
                color: control.themeColors.text
                elide: Text.ElideRight
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            // Two texts rather than one so the agent count can alert without
            // dragging the window count red with it.
            Row {
                spacing: 0

                Text {
                    text: control.windowSummary + " · "
                    color: control.themeColors.text_dim
                    font.family: "Inter"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Text {
                    text: control.agentSummary
                    color: control.agentSummaryColor
                    font.family: "Inter"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: control.themeColors.border
        }

        Repeater {
            model: control.workspaceData.clients.slice(0, control.visibleClientCount)

            Column {
                required property var modelData

                width: contentColumn.width
                spacing: 5

                RowLayout {
                    width: parent.width
                    spacing: 8

                    Item {
                        Layout.preferredWidth: 17
                        Layout.preferredHeight: 17

                        Image {
                            id: tooltipAppIcon
                            anchors.fill: parent
                            source: modelData.icon
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: tooltipAppIcon.status === Image.Error
                            radius: 3
                            color: Qt.darker(control.themeColors.surface, 1.12)
                            border.width: 1
                            border.color: control.themeColors.border

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label.charAt(0).toUpperCase()
                                color: control.themeColors.text_dim
                                font.family: "Inter"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: control.themeColors.text
                        elide: Text.ElideRight
                        font.family: "Inter"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: modelData.terminal
                            ? modelData.tabs + (modelData.tabs === 1 ? " tab" : " tabs")
                            : "window"
                        color: control.themeColors.text_dim
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                    }
                }

                Text {
                    visible: !modelData.terminal && modelData.title.length > 0
                    width: parent.width - 25
                    x: 25
                    text: modelData.title
                    color: control.themeColors.text_dim
                    elide: Text.ElideRight
                    font.family: "Inter"
                    font.pixelSize: 11
                }

                Repeater {
                    model: modelData.activities.slice(0, 8)

                    RowLayout {
                        required property var modelData

                        width: contentColumn.width
                        height: 18
                        spacing: 7

                        Item {
                            Layout.preferredWidth: 18
                        }

                        Image {
                            visible: modelData.kind === "claude" || modelData.kind === "codex"
                            Layout.preferredWidth: 12
                            Layout.preferredHeight: 12
                            source: modelData.kind === "claude"
                                ? "assets/claude.png"
                                : "assets/openai.svg"
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }

                        Text {
                            visible: modelData.kind === "process"
                            Layout.preferredWidth: 12
                            text: "·"
                            color: control.themeColors.text_dim
                            horizontalAlignment: Text.AlignHCenter
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            Layout.fillWidth: true
                            text: control.activityLabel(modelData)
                            color: control.themeColors.text_dim
                            elide: Text.ElideRight
                            font.family: "Inter"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        Text {
                            visible: modelData.kind === "claude" || modelData.kind === "codex"
                            text: control.stateLabel(modelData.state)
                            color: control.stateColor(modelData.state)
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Text {
                    visible: modelData.activities.length > 8
                    width: parent.width - 25
                    x: 25
                    text: "+ " + (modelData.activities.length - 8) + " more"
                    color: control.themeColors.text_dim
                    font.family: "Inter"
                    font.pixelSize: 10
                }
            }
        }

        Text {
            visible: control.workspaceData.clients.length > control.visibleClientCount
            text: "+ " + (control.workspaceData.clients.length - control.visibleClientCount)
                + " more windows"
            color: control.themeColors.text_dim
            font.family: "Inter"
            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }
}
