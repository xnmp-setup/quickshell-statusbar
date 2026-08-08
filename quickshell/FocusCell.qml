import QtQuick
import "StatusIcons.js" as StatusIcons

Item {
    id: root

    required property var themeColors
    property bool available: false
    property bool dnd: false
    property bool last: false

    signal toggled()
    signal editSitesRequested()
    signal viewHostsRequested()

    // Hack Nerd Font is assumed by the WezTerm config on every platform, but a
    // machine without it degrades to the plain text label rather than tofu.
    readonly property bool iconAvailable: Qt.fontFamilies().indexOf("Hack Nerd Font") !== -1
    readonly property string displayText: glyphText.text
    readonly property string tooltip: !available
        ? "Notification daemon unreachable · click to wake mako and enable Focus"
        : dnd
            ? "Focus is on · notifications silenced, listed sites blocked"
            : "Focus is off · click to silence notifications and block distracting sites"
    readonly property color displayColor: dnd
        ? themeColors.accent
        : themeColors.text_dim

    implicitWidth: 40
    implicitHeight: 40

    Rectangle {
        visible: !root.last
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        width: 1
        height: 18
        color: root.themeColors.border
    }

    Text {
        id: glyphText
        anchors.centerIn: parent
        text: root.iconAvailable ? StatusIcons.focusIcon(root.dnd) : "DND"
        color: root.displayColor
        opacity: root.available ? (root.dnd ? 1 : 0.62) : 0.35
        font.family: root.iconAvailable ? "Hack Nerd Font" : "Inter"
        font.pixelSize: root.iconAvailable ? 15 : 11
        font.weight: root.iconAvailable ? Font.Normal : Font.DemiBold
        font.letterSpacing: root.iconAvailable ? 0 : 0.5
    }

    // Clicks and hover stay on separate handlers, exactly as MetricCell warns:
    // a hover-enabled MouseArea on the bar surface breaks popup activation on
    // the live compositor, so hover belongs to a HoverHandler alone.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                contextMenu.popup(root, 0, root.height + 4);
            else
                root.toggled();
        }
    }

    FocusContextMenu {
        id: contextMenu

        themeColors: root.themeColors
        onEditSitesRequested: root.editSitesRequested()
        onViewHostsRequested: root.viewHostsRequested()
    }

    // Overridable seam so tests can drive the popup-open path (synthetic
    // pointer events do not deliver under the offscreen test platform).
    property bool hoverActive: hoverHandler.hovered
    // Sampled inside onPointChanged, never read from a binding: the handler's
    // point resets to zeroed values between events.
    property real hoverX: -1

    HoverHandler {
        id: hoverHandler
        onPointChanged: {
            const position = point.position;
            if (position.x !== 0 || position.y !== 0)
                root.hoverX = position.x;
        }
    }

    ThemedToolTip {
        shown: root.hoverActive
        hostItem: root
        text: root.tooltip
        themeColors: root.themeColors
        pointerX: root.hoverX
    }
}
