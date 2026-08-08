import QtQuick
import "StatusGraph.js" as StatusGraph

HoverPopup {
    id: control

    property string text: ""
    property int maximumWidth: 420
    // Recent samples, oldest first. Two or more numeric points draw a graph.
    property var history: []
    // Overlay a moving average for jittery series (CPU, IO, GPU, Wi-Fi).
    property bool smoothed: false
    property int smoothingWindow: 10
    // Multiple labeled graphs: [{label, values, smoothed, span}]. When set it
    // replaces the single history graph. `span` captions the time axis.
    property var series: []
    readonly property var normalizedSeries: {
        const result = [];
        const append = (label, values, wantSmoothed, span, resets) => {
            const points = StatusGraph.alignedValues(values);
            const marks = [];
            if (resets && typeof resets.length === "number") {
                for (let index = 0; index < resets.length; index += 1) {
                    const mark = resets[index];
                    if (typeof mark === "number" && Number.isFinite(mark)
                            && mark >= 0 && mark < points.length)
                        marks.push(mark);
                }
            }
            if (StatusGraph.finiteCount(points) >= 2)
                result.push({
                    label: label,
                    values: points,
                    smoothed: wantSmoothed,
                    span: span || "",
                    resets: marks
                });
        };
        if (series && typeof series.length === "number" && series.length > 0) {
            for (let index = 0; index < series.length; index += 1) {
                const entry = series[index];
                if (entry !== null && typeof entry === "object")
                    append(entry.label || "", entry.values, entry.smoothed === true,
                           entry.span, entry.resets);
            }
        } else {
            append("", history, smoothed, "", []);
        }
        return result;
    }
    readonly property bool showsGraph: normalizedSeries.length > 0
    readonly property int contentWidth: Math.min(
        maximumWidth - 2 * padding,
        Math.max(hintText.implicitWidth, showsGraph ? 224 : 0)
    )

    Column {
        spacing: 6

        Text {
            id: hintText

            width: control.contentWidth
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
                    width: control.contentWidth
                    height: 48

                    // The model row is replaced wholesale on data change, so a
                    // repaint on completion covers both creation and updates.
                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        const context = getContext("2d");
                        context.reset();
                        const values = modelData.values;
                        if (values.length < 2)
                            return;
                        const range = StatusGraph.bounds(values);
                        const box = StatusGraph.plotGeometry(
                            width, height, modelData.span.length > 0
                        );
                        const plotWidth = box.plotWidth;
                        const top = box.top;
                        const bottom = box.bottom;
                        const yFor = value => StatusGraph.yFor(value, range, top, bottom);
                        const xFor = index => StatusGraph.xFor(index, values.length, plotWidth);
                        const drawSeries = (points, style, lineWidth) => {
                            context.strokeStyle = style;
                            context.lineWidth = lineWidth;
                            context.lineJoin = "round";
                            context.beginPath();
                            let started = false;
                            for (let index = 0; index < points.length; index += 1) {
                                const value = points[index];
                                if (typeof value !== "number" || !Number.isFinite(value)) {
                                    // A gap breaks the line rather than
                                    // bridging across missing measurements.
                                    started = false;
                                    continue;
                                }
                                if (started)
                                    context.lineTo(xFor(index), yFor(value));
                                else
                                    context.moveTo(xFor(index), yFor(value));
                                started = true;
                            }
                            context.stroke();
                        };

                        const dim = control.themeColors.text_dim;
                        // Reset markers go down first so the data line stays
                        // on top of them.
                        context.strokeStyle = Qt.alpha(dim, 0.35);
                        context.lineWidth = 1;
                        for (let mark = 0; mark < modelData.resets.length; mark += 1) {
                            const markX = xFor(modelData.resets[mark]);
                            context.beginPath();
                            context.moveTo(markX, top);
                            context.lineTo(markX, bottom);
                            context.stroke();
                        }
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
                        const decimals = StatusGraph.tickDecimals(range);
                        context.fillText(range.max.toFixed(decimals), width, top + 6);
                        context.fillText(range.min.toFixed(decimals), width, bottom);
                        if (modelData.span.length > 0) {
                            context.textAlign = "left";
                            context.fillText(modelData.span, 0, height - 2);
                            context.textAlign = "right";
                            context.fillText("now", plotWidth, height - 2);
                        }
                    }
                }
            }
        }
    }
}
