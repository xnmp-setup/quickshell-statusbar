import QtQuick

// Bar preferences, opened by right-clicking the clock.
//
// Built on the same popup shell as the hover hints rather than a QtQuick
// Menu: QtQuick popups cannot position themselves against a layer-shell
// surface and map at an unrelated place on screen.
HoverPopup {
    id: menu

    required property bool autoHide

    // True while the pointer is on the bar the menu hangs from. The menu stays
    // put whenever the pointer is on either of them, so the gap between the
    // two never dismisses it.
    property bool pointerNearby: false
    // A focus grab would be the usual way to dismiss on an outside click, but
    // a layer-shell popup can only grab once its parent surface has taken
    // input, and it silently fails to map otherwise. Following the pointer is
    // both reliable and consistent with every other popup on this bar.
    property int dismissDelay: 700
    readonly property bool pointerInside: menuHover.hovered
    readonly property bool wanted: pointerInside || pointerNearby

    signal autoHideRequested(bool value)
    signal dismissed

    readonly property int rowWidth: 268

    onWantedChanged: {
        if (wanted)
            dismissTimer.stop();
        else if (opened)
            dismissTimer.restart();
    }

    function toggleAutoHide(): void {
        autoHideRequested(!autoHide);
    }

    // Clicking is deliberate, so there is nothing to debounce. Sitting flush
    // against the bar leaves no dead strip for the pointer to cross.
    delay: 0
    gap: 0
    padding: 8

    HoverHandler {
        id: menuHover
    }

    Timer {
        id: dismissTimer

        interval: menu.dismissDelay
        repeat: false
        onTriggered: {
            if (!menu.wanted)
                menu.dismissed();
        }
    }

    Column {
        spacing: 6

        Item {
            width: menu.rowWidth
            height: heading.implicitHeight

            Text {
                id: heading

                text: "BAR SETTINGS"
                color: menu.themeColors.text_dim
                font.family: "Inter"
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 0.5
            }
        }

        Rectangle {
            width: menu.rowWidth
            height: 1
            color: menu.themeColors.border
        }

        Item {
            id: autoHideRow

            width: menu.rowWidth
            height: 40

            MouseArea {
                id: autoHidePointer

                anchors.fill: parent
                hoverEnabled: true
                onClicked: menu.toggleAutoHide()
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 4
                color: autoHidePointer.containsMouse
                    ? Qt.lighter(menu.themeColors.surface, 1.15)
                    : "transparent"
            }

            Rectangle {
                id: checkBox

                anchors.verticalCenter: parent.verticalCenter
                width: 15
                height: 15
                radius: 3
                color: menu.autoHide ? menu.themeColors.accent : "transparent"
                border.width: 1
                border.color: menu.autoHide
                    ? menu.themeColors.accent
                    : menu.themeColors.border

                Text {
                    anchors.centerIn: parent
                    visible: menu.autoHide
                    text: "✓"
                    color: menu.themeColors.background
                    font.family: "Inter"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
            }

            Column {
                anchors {
                    left: checkBox.right
                    leftMargin: 9
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1

                Text {
                    text: "Auto-hide the bar"
                    color: menu.themeColors.text
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: "Stays out of sight until the pointer reaches the top of the screen"
                    color: menu.themeColors.text_dim
                    wrapMode: Text.Wrap
                    font.family: "Inter"
                    font.pixelSize: 10
                }
            }
        }
    }
}
