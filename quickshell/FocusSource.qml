import QtQuick
import Quickshell
import Quickshell.Io
import "FocusState.js" as FocusState

Scope {
    id: root

    property bool available: false
    property bool dnd: false
    property bool blockerSynced: false

    // Focus also blocks the sites listed in ~/.config/focus-block/domains.
    // Driving the blocker off observed state (not off the click) keeps it in
    // sync with external toggles, and the first live reply reconciles a block
    // left behind by a crash while Focus was on.
    onDndChanged: syncBlocker()

    function syncBlocker(): void {
        blockerSynced = true;
        Quickshell.execDetached(FocusState.blockerCommand(dnd));
    }

    function toggle(): void {
        // A toggle already in flight will report the fresh state when it
        // lands; restarting it would drop that reply.
        if (toggleProcess.running)
            return;
        // An in-flight poll carries a reply from before the toggle; letting
        // it land would overwrite the toggle's own result with stale state.
        pollProcess.running = false;
        pollTimer.restart();
        toggleProcess.running = true;
    }

    function commit(parsed: var): void {
        const state = FocusState.nextState(
            { available: root.available, dnd: root.dnd }, parsed);
        root.available = state.available;
        root.dnd = state.dnd;
        if (state.available && !root.blockerSynced)
            root.syncBlocker();
    }

    Process {
        id: pollProcess
        command: FocusState.queryCommand()

        stdout: StdioCollector {
            onStreamFinished: root.commit(FocusState.parsePollReply(text))
        }
    }

    Process {
        id: toggleProcess
        command: FocusState.toggleCommand()

        stdout: StdioCollector {
            onStreamFinished: root.commit(FocusState.parseToggleReply(text))
        }
    }

    // The bar owns every toggle it makes, so polling only exists to catch
    // external changes (a keybind, makoctl in a terminal) and mako restarts.
    Timer {
        id: pollTimer
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!pollProcess.running && !toggleProcess.running)
                pollProcess.running = true;
        }
    }
}
