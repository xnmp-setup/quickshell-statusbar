import QtQuick

// Mirrors Quickshell's Edges flags; see PopupWindow.qml for why stubs exist.
QtObject {
    enum Enum {
        None = 0,
        Top = 1,
        Left = 2,
        Right = 4,
        Bottom = 8
    }
}
