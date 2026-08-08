import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Menu {
    id: menu

    required property var themeColors

    signal editSitesRequested
    signal viewHostsRequested

    component ThemedItem: MenuItem {
        id: item

        required property string label
        property string hint: ""

        implicitHeight: 38
        text: label

        background: Rectangle {
            radius: 4
            color: item.highlighted
                ? Qt.lighter(menu.themeColors.surface, 1.16)
                : "transparent"
        }

        contentItem: RowLayout {
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: item.label
                color: menu.themeColors.text
                font.family: "Inter"
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Text {
                visible: item.hint.length > 0
                text: item.hint
                color: menu.themeColors.text_dim
                font.family: "JetBrains Mono"
                font.pixelSize: 11
            }
        }
    }

    width: 238
    padding: 6
    modal: false
    focus: true
    popupType: Popup.Window
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onActiveFocusChanged: {
        if (opened && !activeFocus)
            close();
    }

    background: Rectangle {
        color: menu.themeColors.surface
        border.width: 1
        border.color: menu.themeColors.border
        radius: 6
    }

    ThemedItem {
        label: "Edit blocked sites"
        hint: "domains"
        onTriggered: menu.editSitesRequested()
    }

    ThemedItem {
        label: "View /etc/hosts"
        onTriggered: menu.viewHostsRequested()
    }
}
