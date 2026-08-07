.pragma library

// Project irregularly spaced {at, ...} samples onto an evenly spaced grid
// covering [endTime - spanSeconds, endTime]. Quota percentages are step
// functions — a reading holds until the next one — so each bucket takes the
// most recent sample at or before it. Buckets preceding the first sample are
// null, which the renderer skips, so a young history draws a short line at the
// right of the plot instead of a misleading one stretched across the window.
function resample(samples, field, endTime, spanSeconds, buckets) {
    const result = [];
    if (samples === null || samples === undefined
            || typeof samples.length !== "number" || buckets < 2)
        return result;
    const step = spanSeconds / (buckets - 1);
    let cursor = 0;
    let held = null;
    for (let index = 0; index < buckets; index += 1) {
        const at = endTime - spanSeconds + index * step;
        while (cursor < samples.length && samples[cursor].at <= at) {
            const value = samples[cursor][field];
            held = typeof value === "number" && Number.isFinite(value) ? value : null;
            cursor += 1;
        }
        result.push(held);
    }
    return result;
}

// Consumption rate in percent per hour, measured across a trailing window
// wide enough that the integer percent readings resolve into something other
// than a spike train. Quota resets show up as negative deltas and clamp to
// zero. Buckets without a full lookback are null so the line starts where the
// measurement becomes real.
function ratePerHour(values, bucketSeconds, lookbackSeconds) {
    const span = Math.max(1, Math.round(lookbackSeconds / bucketSeconds));
    const hours = span * bucketSeconds / 3600;
    const result = [];
    for (let index = 0; index < values.length; index += 1) {
        const current = values[index];
        const previous = index >= span ? values[index - span] : null;
        const measurable = typeof current === "number" && Number.isFinite(current)
            && typeof previous === "number" && Number.isFinite(previous);
        result.push(measurable ? Math.max(0, current - previous) / hours : null);
    }
    return result;
}

// Trailing moving average. Non-numeric entries contribute nothing but keep
// their slot so the smoothed series stays aligned with the raw one.
function movingAverage(values, windowSize) {
    const result = [];
    for (let index = 0; index < values.length; index += 1) {
        const start = Math.max(0, index - windowSize + 1);
        let sum = 0;
        let count = 0;
        for (let cursor = start; cursor <= index; cursor += 1) {
            const value = values[cursor];
            if (typeof value === "number" && Number.isFinite(value)) {
                sum += value;
                count += 1;
            }
        }
        result.push(count > 0 ? sum / count : null);
    }
    return result;
}

// Accepts plain JS arrays and the QVariantList shape that `property var`
// values take on when they cross QML object boundaries (Array.isArray is
// false for the latter, so only length + indexing may be relied upon).
// Like numericValues but slot-preserving: gaps become null instead of
// vanishing. Series plotted against time must keep their positions.
function alignedValues(values) {
    const result = [];
    if (values === null || values === undefined
            || typeof values.length !== "number")
        return result;
    for (let index = 0; index < values.length; index += 1) {
        const value = values[index];
        result.push(
            typeof value === "number" && Number.isFinite(value) ? value : null
        );
    }
    return result;
}

function finiteCount(values) {
    return numericValues(values).length;
}

function numericValues(values) {
    const result = [];
    if (values === null || values === undefined
            || typeof values.length !== "number")
        return result;
    for (let index = 0; index < values.length; index += 1) {
        const value = values[index];
        if (typeof value === "number" && Number.isFinite(value))
            result.push(value);
    }
    return result;
}

// Y-axis bounds padded so a flat series still renders mid-band instead of
// hugging an edge.
function bounds(values) {
    const numbers = numericValues(values);
    if (numbers.length === 0)
        return null;
    let minimum = Math.min.apply(null, numbers);
    let maximum = Math.max.apply(null, numbers);
    if (maximum - minimum < 4) {
        const center = (maximum + minimum) / 2;
        minimum = center - 2;
        maximum = center + 2;
    }
    return { min: minimum, max: maximum };
}
