import QtQuick
import "StatusFormat.js" as StatusFormat

Item {
    id: root

    required property string kind
    required property int count
    required property var themeColors
    // True while any session behind this count is stopped waiting on a human.
    property bool awaitingInput: false

    readonly property color countColor: StatusFormat.sessionCountColor(
        kind, awaitingInput, themeColors
    )

    implicitWidth: sessionRow.implicitWidth
    implicitHeight: 22

    Row {
        id: sessionRow
        anchors.centerIn: parent
        spacing: 3

        Image {
            visible: root.kind === "claude"
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            source: Qt.resolvedUrl("assets/claude.png")
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }

        Image {
            visible: root.kind === "codex"
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            source: Qt.resolvedUrl("assets/openai.svg")
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.count
            color: root.countColor
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
}
