import QtQuick

// Mirrors Quickshell's PopupAdjustment flags; see PopupWindow.qml.
QtObject {
    enum Enum {
        None = 0,
        SlideX = 1,
        SlideY = 2,
        Slide = 3,
        FlipX = 4,
        FlipY = 8,
        Flip = 12,
        ResizeX = 16,
        ResizeY = 32,
        Resize = 48,
        All = 63
    }
}
