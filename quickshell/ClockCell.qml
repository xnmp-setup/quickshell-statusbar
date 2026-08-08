import QtQuick
import Quickshell

Item {
    id: root

    required property var themeColors

    // Right-clicking the clock is the way into the bar's settings; x is in
    // cell coordinates so the menu can open where the click landed.
    signal menuRequested(real x)

    // Two 10px Row gaps plus the 1px divider.
    implicitWidth: timeText.implicitWidth + dateText.implicitWidth + 21
    implicitHeight: 38

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => root.menuRequested(mouse.x)
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Row {
        anchors.centerIn: parent
        spacing: 10

        Text {
            id: timeText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: root.themeColors.text
            font.family: "Inter"
            font.pixelSize: 18
            font.weight: Font.DemiBold
            font.letterSpacing: 0.2
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: root.themeColors.border
        }

        Text {
            id: dateText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            color: root.themeColors.text_dim
            opacity: 0.74
            font.family: "Inter"
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}
