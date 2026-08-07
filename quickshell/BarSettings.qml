import Quickshell
import Quickshell.Io

// Persisted bar preferences.
//
// The file lives outside ~/.config/quickshell/statusbar on purpose: that path
// is a checkout managed by chezmoi, and writing settings into it would leave
// the deployment tree permanently dirty.
Scope {
    id: root

    readonly property string directory: (Quickshell.env("XDG_CONFIG_HOME")
        || Quickshell.env("HOME") + "/.config") + "/quickshell-statusbar"
    // Hide the bar until the pointer reaches the top edge of the screen.
    readonly property bool autoHide: store.autoHide === true

    function setAutoHide(value: bool): void {
        store.autoHide = value;
    }

    FileView {
        id: file

        path: root.directory + "/settings.json"
        watchChanges: true
        atomicWrites: true
        // Missing or unreadable settings are not an error worth reporting:
        // the defaults below are a complete configuration on their own.
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: store

            property bool autoHide: false
        }
    }
}
