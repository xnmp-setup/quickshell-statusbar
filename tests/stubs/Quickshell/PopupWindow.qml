import QtQuick

// Test double for Quickshell.PopupWindow.
//
// The real type comes from a C++ plugin that only loads inside the quickshell
// binary, so importing it would make every component that shows a hover hint
// untestable. This stub mirrors the surface the bar actually uses — the anchor
// group, visibility and implicit sizing — so tests can assert where a hint
// anchors itself without a compositor. Behaviour that only the compositor can
// provide (actually mapping the surface) is verified by running the bar.
Item {
    id: window

    component Box: QtObject {
        property real x: 0
        property real y: 0
        property real width: 0
        property real height: 0
    }

    component PopupAnchor: QtObject {
        property Item item: null
        property Box rect: Box {}
        property int edges: 0
        property int gravity: 0
        property int adjustment: 0
    }

    property color color: "transparent"
    readonly property PopupAnchor anchor: PopupAnchor {}
}
