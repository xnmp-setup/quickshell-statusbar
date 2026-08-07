import QtQuick
import "StatusGraph.js" as StatusGraph

Item {
    id: root

    required property string provider
    required property var usage
    required property var themeColors
    property bool compact: false
    property bool last: false
    property double nowEpoch: Date.now() / 1000
    // Each quota window is plotted over a horizon that suits how fast it
    // moves: the long window creeps and needs hours of context, while the
    // short one can swing through its whole range within its own reset cycle.
    property int primarySpanSeconds: 4 * 3600
    property int secondarySpanSeconds: 3600
    property int graphBuckets: 96
    // Quota percentages are whole numbers that creep, so a rate measured over
    // one sample is a spike train. An hour of lookback resolves it to 1 %/h.
    property int rateLookbackSeconds: 3600
    readonly property real primaryBucketSeconds: primarySpanSeconds / (graphBuckets - 1)
    // Timestamped {at, percent, secondaryPercent} samples from the usage
    // stream, oldest first, spanning the last several hours.
    readonly property var history: usage && usage.history ? usage.history : []
    readonly property var primarySeries: StatusGraph.resample(
        history, "percent", nowEpoch, primarySpanSeconds, graphBuckets
    )
    readonly property var secondarySeries: StatusGraph.resample(
        history, "secondaryPercent", nowEpoch, secondarySpanSeconds, graphBuckets
    )
    readonly property var graphSeries: {
        const series = [{
            label: windowTitle(usage ? usage.windowMinutes : null) + " · % USED",
            values: primarySeries,
            smoothed: false,
            span: spanLabel(primarySpanSeconds)
        }];
        if (StatusGraph.finiteCount(secondarySeries) >= 2) {
            series.push({
                label: windowTitle(usage.secondaryWindowMinutes) + " · % USED",
                values: secondarySeries,
                smoothed: false,
                span: spanLabel(secondarySpanSeconds)
            });
        }
        series.push({
            label: "BURN RATE · % PER HOUR",
            // Already a trailing average by construction, so no overlay.
            values: StatusGraph.ratePerHour(
                primarySeries, primaryBucketSeconds, rateLookbackSeconds
            ),
            smoothed: false,
            span: spanLabel(primarySpanSeconds)
        });
        return series;
    }
    readonly property string providerName: provider === "claude" ? "CLAUDE" : "CODEX"
    readonly property var percent: usage ? usage.percent : null
    readonly property var resetsAt: usage ? usage.resetsAt : null
    readonly property string percentText: percent === null || percent === undefined
        ? "--"
        : percent + "%"
    readonly property string resetText: resetsAt === null || resetsAt === undefined
        ? "waiting"
        : "↻ " + countdownText(resetsAt)
    readonly property color displayColor: percentageColor()
    readonly property real percentColumnX: percentLabel.mapToItem(root, 0, 0).x
    readonly property real resetColumnX: resetLabel.mapToItem(root, 0, 0).x

    function windowLabel(minutes: var): string {
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

    function spanLabel(seconds: int): string {
        return seconds % 3600 === 0
            ? seconds / 3600 + "h ago"
            : Math.round(seconds / 60) + "m ago";
    }

    function windowTitle(minutes: var): string {
        return windowLabel(minutes).replace(" window", "").toUpperCase();
    }

    function fullReset(timestamp: var): string {
        if (timestamp === null || timestamp === undefined)
            return "reset unavailable";
        return "resets " + Qt.formatDateTime(
            new Date(timestamp * 1000),
            "ddd d MMM yyyy HH:mm t"
        );
    }

    function countdownText(timestamp: var): string {
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

    function tooltipText(): string {
        const product = provider === "claude" ? "Claude Code" : "Codex";
        if (percent === null || percent === undefined)
            return product + " usage unavailable · waiting for fresh account activity";
        let text = product + " " + windowLabel(usage.windowMinutes)
            + " · " + percentText + " used · " + fullReset(resetsAt);
        if (usage.secondaryPercent !== null && usage.secondaryPercent !== undefined) {
            text += "\n" + windowLabel(usage.secondaryWindowMinutes)
                + " · " + usage.secondaryPercent + "% used · "
                + fullReset(usage.secondaryResetsAt);
        }
        return text;
    }

    function percentageColor(): color {
        if (percent === null || percent === undefined)
            return themeColors.text_dim;
        if (percent >= 90)
            return "#fb4934";
        if (percent >= 75)
            return "#fabd2f";
        return themeColors.text;
    }

    implicitWidth: compact ? 39 : 188
    implicitHeight: 40

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowEpoch = Date.now() / 1000
    }

    Rectangle {
        visible: !root.last
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        width: 1
        height: 18
        color: root.themeColors.border
    }

    Row {
        anchors.centerIn: parent
        spacing: root.compact ? 2 : 4

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: root.compact ? 8 : 14
            height: width
            source: root.provider === "claude"
                ? "assets/claude.png"
                : "assets/openai.svg"
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }

        Text {
            visible: !root.compact
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            text: root.providerName
            color: root.themeColors.text_dim
            opacity: 0.72
            horizontalAlignment: Text.AlignRight
            font.family: "Inter"
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 0.45
        }

        Text {
            id: percentLabel
            anchors.verticalCenter: parent.verticalCenter
            width: root.compact ? 28 : 36
            clip: true
            text: root.percentText
            color: root.displayColor
            horizontalAlignment: Text.AlignLeft
            font.family: "JetBrains Mono"
            font.pixelSize: root.compact ? 9 : 12
            font.weight: Font.DemiBold
        }

        Text {
            id: resetLabel
            visible: !root.compact
            anchors.verticalCenter: parent.verticalCenter
            width: 76
            clip: true
            elide: Text.ElideRight
            text: root.resetText
            color: root.themeColors.text_dim
            opacity: 0.68
            font.family: "Inter"
            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }

    // Overridable seam so tests can drive the real popup-open path; live it
    // simply mirrors the hover handler. A competing hover-enabled MouseArea
    // must NOT be added here: buttonless MouseAreas break popup activation on
    // the live compositor even though they behave offscreen.
    property bool hoverActive: hoverHandler.hovered
    // Last pointer x captured during event delivery. HoverHandler.point
    // resets to zeroed values between events, so it must be sampled inside
    // onPointChanged, never read from a binding.
    property real hoverX: -1

    HoverHandler {
        id: hoverHandler
        onPointChanged: {
            const position = point.position;
            if (position.x !== 0 || position.y !== 0)
                root.hoverX = position.x;
        }
    }

    ThemedToolTip {
        shown: root.hoverActive
        hostItem: root
        text: root.tooltipText()
        themeColors: root.themeColors
        series: root.graphSeries
        pointerX: root.hoverX
    }
}
