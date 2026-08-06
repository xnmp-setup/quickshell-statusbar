import QtQuick
import QtQuick.Controls
import "StatusGraph.js" as StatusGraph

ToolTip {
    id: control

    required property var themeColors
    property int maximumWidth: 420
    // Recent samples, oldest first. Two or more numeric points draw a graph.
    property var history: []
    // Overlay a moving average for jittery series (CPU, IO, GPU, Wi-Fi).
    property bool smoothed: false
    property int smoothingWindow: 10
    // Multiple labeled graphs: [{label, values, smoothed}]. When set it
    // replaces the single history graph.
    property var series: []
    // Pointer x in parent coordinates. The popup maps under the pointer as it
    // opens; anchorX freezes the open position because Wayland popups cannot
    // rely on being movable after they are mapped.
    property real pointerX: -1
    property real anchorX: -1
    readonly property color surfaceColor: themeColors.surface
    readonly property var normalizedSeries: {
        const result = [];
        const append = (label, values, wantSmoothed) => {
            const numbers = StatusGraph.numericValues(values);
            if (numbers.length >= 2)
                result.push({ label: label, values: numbers, smoothed: wantSmoothed });
        };
        if (series && typeof series.length === "number" && series.length > 0) {
            for (let index = 0; index < series.length; index += 1) {
                const entry = series[index];
                if (entry !== null && typeof entry === "object")
                    append(entry.label || "", entry.values, entry.smoothed === true);
            }
        } else {
            append("", history, smoothed);
        }
        return result;
    }
    readonly property bool showsGraph: normalizedSeries.length > 0

    // Status-bar hints should track the pointer without feeling sticky, while a
    // tiny guard avoids flashing a popup when crossing adjacent metrics.
    delay: 90
    timeout: -1
    padding: 10
    popupType: Popup.Window
    implicitWidth: Math.min(
        maximumWidth,
        contentItem.implicitWidth + leftPadding + rightPadding
    )

    x: anchorX >= 0
        ? anchorX - width / 2
        : parent ? (parent.width - width) / 2 : 0
    y: parent ? parent.height + 6 : 0

    onAboutToShow: anchorX = pointerX

    contentItem: Column {
        spacing: 6

        Text {
            width: Math.min(
                control.maximumWidth - control.leftPadding - control.rightPadding,
                implicitWidth
            )
            text: control.text
            color: control.themeColors.text
            wrapMode: Text.Wrap
            font.family: "Inter"
            font.pixelSize: 12
            font.weight: Font.Medium
            lineHeight: 1.2
        }

        Repeater {
            model: control.normalizedSeries

            Column {
                required property var modelData

                spacing: 2

                Text {
                    visible: modelData.label.length > 0
                    text: modelData.label
                    color: control.themeColors.text_dim
                    font.family: "Inter"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.4
                }

                Canvas {
                    id: graphCanvas
                    width: 224
                    height: 48

                    // The model row is replaced wholesale on data change, so a
                    // repaint on completion covers both creation and updates.
                    Component.onCompleted: requestPaint()

                    onPaint: {
                        const context = getContext("2d");
                        context.reset();
                        const values = modelData.values;
                        if (values.length < 2)
                            return;
                        const range = StatusGraph.bounds(values);
                        const gutter = 30;
                        const plotWidth = width - gutter;
                        const top = 3;
                        const bottom = height - 3;
                        const yFor = value => bottom
                            - (value - range.min) / (range.max - range.min) * (bottom - top);
                        const xFor = index => index / (values.length - 1) * plotWidth;
                        const drawSeries = (points, style, lineWidth) => {
                            context.strokeStyle = style;
                            context.lineWidth = lineWidth;
                            context.lineJoin = "round";
                            context.beginPath();
                            let started = false;
                            for (let index = 0; index < points.length; index += 1) {
                                const value = points[index];
                                if (typeof value !== "number" || !Number.isFinite(value))
                                    continue;
                                if (started)
                                    context.lineTo(xFor(index), yFor(value));
                                else
                                    context.moveTo(xFor(index), yFor(value));
                                started = true;
                            }
                            context.stroke();
                        };

                        const dim = control.themeColors.text_dim;
                        drawSeries(
                            values,
                            modelData.smoothed
                                ? Qt.alpha(dim, 0.45)
                                : control.themeColors.accent_light,
                            modelData.smoothed ? 1 : 1.5
                        );
                        if (modelData.smoothed) {
                            drawSeries(
                                StatusGraph.movingAverage(values, control.smoothingWindow),
                                control.themeColors.accent_light,
                                1.6
                            );
                        }

                        context.fillStyle = dim;
                        context.font = "8px Inter";
                        context.textAlign = "right";
                        const decimals = range.max - range.min < 8 ? 1 : 0;
                        context.fillText(range.max.toFixed(decimals), width, top + 6);
                        context.fillText(range.min.toFixed(decimals), width, bottom);
                    }
                }
            }
        }
    }

    background: Rectangle {
        color: control.surfaceColor
        border.width: 1
        border.color: control.themeColors.border
        radius: 6
    }
}
