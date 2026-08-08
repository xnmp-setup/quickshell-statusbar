//@ pragma IconTheme hicolor

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property bool barVisible: true
    property int renameRequestSerial: 0
    property string candidate: Quickshell.env("STATUSBAR_CANDIDATE") === "instrument"
        ? "instrument"
        : "segmented"

    StatusSource {
        id: source
    }

    BarSettings {
        id: barSettings
    }

    FocusSource {
        id: focusControl
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            root.barVisible = !root.barVisible;
        }

        function show(): void {
            root.barVisible = true;
        }

        function hide(): void {
            root.barVisible = false;
        }

        function visible(): bool {
            return root.barVisible;
        }

        function autoHide(enabled: bool): void {
            barSettings.setAutoHide(enabled);
        }

        function autoHidden(): bool {
            return barSettings.autoHide;
        }

        function renameCurrentWorkspace(): void {
            root.renameRequestSerial += 1;
        }

        function toggleFocus(): void {
            focusControl.toggle();
        }

        function focusEnabled(): bool {
            return focusControl.dnd;
        }
    }

    Variants {
        model: Quickshell.screens

        StatusBar {
            required property var modelData

            screen: modelData
            barVisible: root.barVisible
            candidate: root.candidate
            statusSource: source
            focusSource: focusControl
            settings: barSettings
            renameRequestSerial: root.renameRequestSerial
        }
    }
}
