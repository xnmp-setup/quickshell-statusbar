.pragma library

// argv builders for the two external effects the bar triggers. Both strings
// are contracts with Hyprland and with the rename helper respectively, so they
// live here rather than being concatenated at the click site.

function focusWorkspaceCommand(id) {
    return [
        "hyprctl",
        "dispatch",
        "hl.dsp.focus({ workspace = " + id + " })"
    ];
}

function renameWorkspaceCommand(homeDir, id, name) {
    return [
        homeDir + "/.local/bin/rename-hypr-workspace",
        String(id),
        name
    ];
}
