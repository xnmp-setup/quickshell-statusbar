import QtQuick

// Decides whether an auto-hiding bar is currently down, in the style of the
// macOS menu bar: the bar sits off screen until the pointer touches the top
// edge, stays down while the pointer is on it or something on it is in use,
// and withdraws a beat after the pointer leaves.
//
// This is deliberately free of any window or compositor concern so the rule
// can be exercised directly; the bar only wires its inputs up to it.
Item {
    id: controller

    property bool enabled: false
    // Pointer is on the thin trigger strip at the screen edge.
    property bool pointerOnStrip: false
    // Pointer is anywhere on the revealed bar.
    property bool pointerOnBar: false
    // Something on the bar is mid-interaction — a menu, an open editor — and
    // must not be yanked away even though the pointer has moved off.
    property bool pinned: false
    // The grace period stops the bar flickering away when the pointer crosses
    // a seam between two hover regions.
    property int hideDelay: 350
    property bool held: false
    readonly property bool wantsReveal: pointerOnStrip || pointerOnBar || pinned
    readonly property bool revealed: !enabled || held

    function update(): void {
        if (!enabled) {
            hideTimer.stop();
            held = false;
        } else if (wantsReveal) {
            hideTimer.stop();
            held = true;
        } else if (held) {
            hideTimer.restart();
        }
    }

    onEnabledChanged: update()
    onWantsRevealChanged: update()

    Timer {
        id: hideTimer

        interval: controller.hideDelay
        repeat: false
        onTriggered: {
            if (!controller.wantsReveal)
                controller.held = false;
        }
    }
}
