import QtQuick
import QtQuick.Effects
import "StatusGraph.js" as StatusGraph
import "StatusFormat.js" as StatusFormat
import "StatusSeverity.js" as StatusSeverity

Item {
    id: root

    required property string provider
    required property var usage
    required property var themeColors
    property bool compact: false
    property bool stacked: false
    property bool last: false
    property bool dividerVisible: !last
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
    // Bucket indices where each window reset inside its plotted span; drawn
    // as faint vertical rules so a percent falling off a cliff (and the burn
    // rate restarting) reads as the scheduled event it is.
    readonly property var primaryResets: StatusGraph.resetIndices(
        usage ? usage.resetsAt : null,
        (usage && usage.windowMinutes ? usage.windowMinutes : 0) * 60,
        nowEpoch, primarySpanSeconds, graphBuckets
    )
    readonly property var secondaryResets: StatusGraph.resetIndices(
        usage ? usage.secondaryResetsAt : null,
        (usage && usage.secondaryWindowMinutes ? usage.secondaryWindowMinutes : 0) * 60,
        nowEpoch, secondarySpanSeconds, graphBuckets
    )
    readonly property var graphSeries: {
        const series = [{
            label: windowTitle(usage ? usage.windowMinutes : null) + " · % USED",
            values: primarySeries,
            smoothed: false,
            span: spanLabel(primarySpanSeconds),
            resets: primaryResets
        }];
        if (StatusGraph.finiteCount(secondarySeries) >= 2) {
            series.push({
                label: windowTitle(usage.secondaryWindowMinutes) + " · % USED",
                values: secondarySeries,
                smoothed: false,
                span: spanLabel(secondarySpanSeconds),
                resets: secondaryResets
            });
        }
        series.push({
            label: "BURN RATE · % PER HOUR",
            // Already a trailing average by construction, so no overlay.
            values: StatusGraph.ratePerHour(
                primarySeries, primaryBucketSeconds, rateLookbackSeconds
            ),
            smoothed: false,
            span: spanLabel(primarySpanSeconds),
            resets: primaryResets
        });
        return series;
    }
    readonly property string providerName: provider === "claude" ? "CLAUDE" : "CODEX"
    readonly property var percent: usage ? usage.percent : null
    readonly property var resetsAt: usage ? usage.resetsAt : null
    readonly property string percentText: StatusFormat.percentText(percent)
    readonly property string resetText: StatusFormat.resetText(resetsAt, nowEpoch)
    readonly property string compactResetText: StatusFormat.compactCountdownText(
        resetsAt, nowEpoch
    )
    readonly property color displayColor: percentageColor()
    readonly property real percentColumnX: percentLabel.mapToItem(root, 0, 0).x
    readonly property real resetColumnX: resetLabel.mapToItem(root, 0, 0).x
    readonly property bool providerIconRounded: provider === "claude"

    component ProviderIcon: Item {
        id: providerIcon

        required property int iconSize

        width: iconSize
        height: iconSize

        Image {
            id: iconSource

            anchors.fill: parent
            visible: !root.providerIconRounded
            source: root.provider === "claude"
                ? "assets/claude.png"
                : "assets/openai.svg"
            fillMode: Image.PreserveAspectFit
            mipmap: true
            layer.enabled: root.providerIconRounded
        }

        Rectangle {
            id: roundedMask

            anchors.fill: parent
            visible: false
            radius: 3
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            visible: root.providerIconRounded
            source: iconSource
            maskEnabled: true
            maskSource: roundedMask
        }
    }

    function windowLabel(minutes: var): string {
        return StatusFormat.windowLabel(minutes);
    }

    function spanLabel(seconds: int): string {
        return StatusFormat.spanLabel(seconds);
    }

    function windowTitle(minutes: var): string {
        return StatusFormat.windowTitle(minutes);
    }

    function fullReset(timestamp: var): string {
        return StatusFormat.fullReset(timestamp);
    }

    function countdownText(timestamp: var): string {
        return StatusFormat.countdownText(timestamp, nowEpoch);
    }

    function tooltipText(): string {
        return StatusFormat.usageTooltipText(provider, usage);
    }

    function percentageColor(): color {
        return StatusSeverity.usagePercentColor(
            percent, themeColors.text, themeColors.text_dim
        );
    }

    implicitWidth: stacked ? 96 : (compact ? 39 : 188)
    implicitHeight: 38

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.nowEpoch = Date.now() / 1000
    }

    Rectangle {
        visible: root.dividerVisible
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        width: 1
        height: 18
        color: root.themeColors.border
    }

    Row {
        visible: !root.stacked
        anchors.centerIn: parent
        spacing: root.compact ? 2 : 4

        ProviderIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconSize: root.compact ? 8 : 14
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

    Row {
        visible: root.stacked
        anchors.centerIn: parent
        spacing: 5

        ProviderIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 17
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: -1

            Text {
                width: 66
                text: root.percentText
                color: root.displayColor
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Text {
                width: 66
                text: root.compactResetText
                color: root.themeColors.text_dim
                opacity: 0.7
                font.family: "Inter"
                font.pixelSize: 10
                font.weight: Font.Medium
            }
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
