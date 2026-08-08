.pragma library

// The mako contract for Focus mode, split by direction:
//
// - Polling reads the fr.emersion.Mako Modes property through busctl with
//   auto-start disabled, so a daemon the user deliberately stopped is never
//   resurrected just by looking at it. This must be the `call` verb spelling
//   of Properties.Get: busctl documents --auto-start for `call` only, and its
//   `get-property` verb activates the destination regardless (verified live).
//   busctl prints `v as <n> "mode"...` on stdout and errors on stderr, so an
//   empty reply means "unreachable" while `v as 0` means "alive, no modes".
// - Toggling goes through `makoctl mode -t <name>`, whose D-Bus call does
//   auto-start mako — clicking Focus on a dead daemon is the one moment
//   waking it is wanted. It prints the resulting modes one per line.
//
// A reply that reads as unreachable never rewrites the last known dnd state:
// otherwise a transient read failure would flip the cell to "off" and make
// the next click disable the Focus the user still has on.

const DND_MODE = "do-not-disturb";
const MAX_OUTPUT = 4096;

function queryCommand() {
    return [
        "busctl", "--user", "--auto-start=no", "call",
        "org.freedesktop.Notifications", "/fr/emersion/Mako",
        "org.freedesktop.DBus.Properties", "Get",
        "ss", "fr.emersion.Mako", "Modes"
    ];
}

function toggleCommand() {
    return ["makoctl", "mode", "-t", DND_MODE];
}

// The website blocker rides the observed dnd state rather than the click, so
// external toggles (a keybind, makoctl in a terminal) stay in sync too. The
// sudoers entry authorizes exactly these two argv shapes; -n keeps a
// misconfigured sudo from hanging on a password prompt.
function blockerCommand(active) {
    return ["sudo", "-n", "/usr/local/bin/focus-block", active ? "on" : "off"];
}

function fromModes(modes) {
    return { available: true, dnd: modes.indexOf(DND_MODE) !== -1 };
}

function unreachable() {
    return { available: false, dnd: false };
}

function parsePollReply(reply) {
    if (typeof reply !== "string" || reply.length > MAX_OUTPUT)
        return unreachable();
    const trimmed = reply.trim();
    if (!/^(v )?as \d+/.test(trimmed))
        return unreachable();
    const modes = [];
    const quoted = /"([^"]*)"/g;
    let match;
    while ((match = quoted.exec(trimmed)) !== null)
        modes.push(match[1]);
    return fromModes(modes);
}

function parseToggleReply(reply) {
    if (typeof reply !== "string" || reply.length === 0
            || reply.length > MAX_OUTPUT)
        return unreachable();
    const modes = reply.split("\n")
        .map(line => line.trim())
        .filter(line => line.length > 0);
    if (modes.length === 0)
        return unreachable();
    return fromModes(modes);
}

function nextState(previous, parsed) {
    return {
        available: parsed.available,
        dnd: parsed.available
            ? parsed.dnd
            : previous !== null && previous !== undefined && previous.dnd === true
    };
}
