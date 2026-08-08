.pragma library
.import "StatusSeverity.js" as StatusSeverity

// Human name for a quota window given its length in minutes. Whole weeks,
// days and hours read as such; anything else stays in minutes.
function windowLabel(minutes) {
    if (minutes === null || minutes === undefined)
        return "current window";
    if (minutes % 10080 === 0)
        return minutes / 10080 + "-week window";
    if (minutes % 1440 === 0)
        return minutes / 1440 + "-day window";
    if (minutes % 60 === 0)
        return minutes / 60 + "-hour window";
    return minutes + "-minute window";
}

// Caption for the left edge of a plot's time axis.
function spanLabel(seconds) {
    return seconds % 3600 === 0
        ? seconds / 3600 + "h ago"
        : Math.round(seconds / 60) + "m ago";
}

// Graph heading form of windowLabel.
function windowTitle(minutes) {
    return windowLabel(minutes).replace(" window", "").toUpperCase();
}

// Absolute reset wall-clock, for the tooltip where there is room for it.
function fullReset(timestamp) {
    if (timestamp === null || timestamp === undefined)
        return "reset unavailable";
    return "resets " + Qt.formatDateTime(
        new Date(timestamp * 1000),
        "ddd d MMM yyyy HH:mm t"
    );
}

// Coarse countdown for the inline label. Units drop away as the reset nears,
// and anything under a minute collapses to "<1m" rather than counting seconds.
function countdownText(timestamp, nowEpoch) {
    if (typeof timestamp !== "number" || !Number.isFinite(timestamp))
        return "waiting";
    const remaining = Math.max(0, Math.floor(timestamp - nowEpoch));
    const days = Math.floor(remaining / 86400);
    const hours = Math.floor((remaining % 86400) / 3600);
    const minutes = Math.floor((remaining % 3600) / 60);
    if (days > 0)
        return days + "d " + hours + "h " + minutes + "m";
    if (hours > 0)
        return hours + "h " + minutes + "m";
    if (minutes > 0)
        return minutes + "m";
    return "<1m";
}

// Tray countdowns prioritize stability and density: minutes only matter in
// the final hour. The detailed tooltip still exposes the absolute reset time.
function compactCountdownText(timestamp, nowEpoch) {
    if (typeof timestamp !== "number" || !Number.isFinite(timestamp))
        return "waiting";
    const remaining = Math.max(0, Math.floor(timestamp - nowEpoch));
    const days = Math.floor(remaining / 86400);
    const hours = Math.floor((remaining % 86400) / 3600);
    const minutes = Math.floor((remaining % 3600) / 60);
    if (days > 0)
        return days + "d " + hours + "h";
    if (hours > 0)
        return hours + "h";
    if (minutes > 0)
        return minutes + "m";
    return "<1m";
}

function percentText(percent) {
    return percent === null || percent === undefined ? "--" : percent + "%";
}

function resetText(resetsAt, nowEpoch) {
    return resetsAt === null || resetsAt === undefined
        ? "waiting"
        : "↻ " + countdownText(resetsAt, nowEpoch);
}

// Full hover text for a usage cell: the primary window on one line and, when
// the provider reports one, the secondary window on a second.
function usageTooltipText(provider, usage) {
    const product = provider === "claude" ? "Claude Code" : "Codex";
    const percent = usage ? usage.percent : null;
    if (percent === null || percent === undefined)
        return product + " usage unavailable · waiting for fresh account activity";
    let text = product + " " + windowLabel(usage.windowMinutes)
        + " · " + percentText(percent) + " used · " + fullReset(usage.resetsAt);
    if (usage.secondaryPercent !== null && usage.secondaryPercent !== undefined) {
        text += "\n" + windowLabel(usage.secondaryWindowMinutes)
            + " · " + usage.secondaryPercent + "% used · "
            + fullReset(usage.secondaryResetsAt);
    }
    return text;
}

// Agent run states as shown beside an activity row.
function stateLabel(state) {
    if (state === "working")
        return "Running";
    if (state === "attention")
        return "Awaiting input";
    return "Idle";
}

function stateColor(state, themeColors) {
    // Same red as the counts: a session waiting on a human reads one way
    // wherever it is shown.
    if (state === "attention")
        return StatusSeverity.alertColor;
    if (state === "working")
        return themeColors.accent_light;
    return themeColors.text_dim;
}

// An agent session awaits input when it has stopped and cannot continue until
// a human answers it. Only the two agent kinds have run states; a plain
// process activity never does.
function awaitsInput(activity) {
    return !!activity && activity.state === "attention"
        && (activity.kind === "claude" || activity.kind === "codex");
}

// Whether any session of `kind` across these clients is waiting on a human.
// `kind` of "" asks about both agents at once.
function sessionsAwaitInput(clients, kind) {
    const matches = activity => awaitsInput(activity)
        && (kind === "" || activity.kind === kind);
    return (clients || []).some(
        client => (client.activities || []).some(matches)
    );
}

// A count alerts the moment one of the sessions behind it is waiting on a
// human, and otherwise keeps its resting colour. The count is the only part of
// a chip a glance catches, so it carries the signal rather than the icon.
function attentionColor(awaitingInput, restingColor) {
    return awaitingInput ? StatusSeverity.alertColor : restingColor;
}

// Session counts rest in their own agent's colour.
function sessionCountColor(kind, awaitingInput, themeColors) {
    return attentionColor(
        awaitingInput,
        kind === "claude" ? themeColors.accent_light : themeColors.text
    );
}

// Activity rows are prefixed with the agent product name, except when the
// title already is the product name, or the activity is a plain process.
function activityLabel(activity) {
    const agent = activity.kind === "claude"
        ? "Claude Code"
        : activity.kind === "codex" ? "Codex" : "";
    if (agent.length === 0)
        return activity.title;
    if (activity.title === agent)
        return agent;
    return agent + " · " + activity.title;
}
