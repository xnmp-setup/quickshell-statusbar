import QtQuick
import Quickshell

// Positioning shell shared by every hover hint in the bar.
//
// QtQuick's ToolTip cannot place a popup window against a layer-shell
// surface: Qt has no idea where the panel sits on screen, so the popup lands
// at an unrelated position (observed: centre-bottom of the monitor) no matter
// what x/y the ToolTip is given. Quickshell's PopupWindow anchors through the
// compositor instead, and re-issues an xdg_popup reposition whenever the
// anchor rect changes — so the hint can genuinely follow the pointer.
PopupWindow {
    id: control

    required property var themeColors
    // Item the hint hangs from, in whose coordinates pointerX is expressed.
    property Item hostItem: null
    // Live pointer x within hostItem. Negative centres the hint on the host.
    property real pointerX: -1
    // Vertical gap between the host's bottom edge and the hint.
    property int gap: 6
    property int padding: 10
    // Requested visibility. A short grace period keeps the hint from flashing
    // while the pointer crosses adjacent cells; 0 shows immediately.
    property bool shown: false
    property int delay: 90
    property bool ready: false
    readonly property color surfaceColor: themeColors.surface
    // Whether the hint is currently on screen. Distinct from `visible` so it
    // reads the same whether the popup is a real window or a test double.
    readonly property bool opened: shown && ready && hostItem !== null
    readonly property real anchorX: pointerX >= 0
        ? pointerX
        : hostItem ? hostItem.width / 2 : 0
    default property alias content: contentHolder.data

    function reveal(): void {
        if (delay <= 0)
            ready = true;
        else
            openTimer.restart();
    }

    onShownChanged: {
        if (shown) {
            reveal();
        } else {
            openTimer.stop();
            ready = false;
        }
    }

    anchor {
        item: control.hostItem
        rect.x: Math.round(control.anchorX)
        rect.y: control.hostItem ? control.hostItem.height + control.gap : 0
        rect.width: 1
        rect.height: 1
        edges: Edges.Bottom
        gravity: Edges.Bottom
        // Slide back on screen at the edges rather than flipping above the
        // bar, where the hint would cover the cell it describes.
        adjustment: PopupAdjustment.SlideX
    }

    visible: opened
    color: "transparent"
    implicitWidth: contentHolder.implicitWidth + 2 * padding
    implicitHeight: contentHolder.implicitHeight + 2 * padding

    Timer {
        id: openTimer
        interval: control.delay
        repeat: false
        onTriggered: control.ready = true
    }

    Rectangle {
        anchors.fill: parent
        color: control.surfaceColor
        border.width: 1
        border.color: control.themeColors.border
        radius: 6
    }

    Item {
        id: contentHolder

        x: control.padding
        y: control.padding
        width: childrenRect.width
        height: childrenRect.height
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
