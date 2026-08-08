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

// Consumption rate in percent per hour, measured against the earliest
// occurrence of the trailing window's minimum rather than simply the sample
// one lookback ago: diffing across a quota reset would otherwise clamp the
// whole next lookback to zero while usage is visibly climbing again. On
// monotone data the minimum sits at the window start, so nothing changes;
// right after a reset the rate measures the climb since the reset. The
// window stays wide enough that integer percent readings resolve into
// something other than a spike train. Buckets whose window holds no earlier
// finite sample are null so the line starts where the measurement is real.
function ratePerHour(values, bucketSeconds, lookbackSeconds) {
    const span = Math.max(1, Math.round(lookbackSeconds / bucketSeconds));
    const result = [];
    for (let index = 0; index < values.length; index += 1) {
        const current = values[index];
        if (index < span
                || typeof current !== "number" || !Number.isFinite(current)) {
            result.push(null);
            continue;
        }
        let baseline = -1;
        for (let cursor = index - span; cursor < index; cursor += 1) {
            const value = values[cursor];
            if (typeof value === "number" && Number.isFinite(value)
                    && (baseline === -1 || value < values[baseline]))
                baseline = cursor;
        }
        if (baseline === -1) {
            result.push(null);
        } else if (current <= values[baseline]) {
            result.push(0);
        } else {
            const hours = (index - baseline) * bucketSeconds / 3600;
            result.push((current - values[baseline]) / hours);
        }
    }
    return result;
}

// Bucket indices where a quota window rolled over, walking back one window
// length at a time from the (future) next reset. Fixed-cadence steps are only
// guaranteed for the window in progress — idle gaps can delay earlier
// windows — but at the spans plotted here the current window's boundary is
// the only one on screen in practice. Index 0 is excluded: a marker pinned
// to the left edge reads as a plot border, not an event.
function resetIndices(resetsAt, windowSeconds, endTime, spanSeconds, buckets) {
    const result = [];
    if (typeof resetsAt !== "number" || !Number.isFinite(resetsAt)
            || typeof windowSeconds !== "number" || !(windowSeconds > 0)
            || buckets < 2)
        return result;
    const start = endTime - spanSeconds;
    const step = spanSeconds / (buckets - 1);
    for (let at = resetsAt; at > start; at -= windowSeconds) {
        if (at > endTime)
            continue;
        const index = Math.round((at - start) / step);
        if (index >= 1 && index < buckets)
            result.unshift(index);
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
// hugging an edge. Every plotted series is a non-negative quantity (percent
// used, percent per hour), so padding a near-zero series is slid up to rest on
// zero rather than inventing negative tick labels.
function bounds(values) {
    const numbers = numericValues(values);
    if (numbers.length === 0)
        return null;
    const dataMinimum = Math.min.apply(null, numbers);
    let minimum = dataMinimum;
    let maximum = Math.max.apply(null, numbers);
    if (maximum - minimum < 4) {
        const center = (maximum + minimum) / 2;
        minimum = center - 2;
        maximum = center + 2;
    }
    if (dataMinimum >= 0 && minimum < 0) {
        maximum -= minimum;
        minimum = 0;
    }
    return { min: minimum, max: maximum };
}

// Right-hand strip reserved for the min/max tick labels.
const plotGutter = 30;
// Breathing room above the line, and below it when no time axis is captioned.
const plotTopInset = 3;
const plotBottomInset = 3;
// Extra depth taken by the "<span> ago … now" axis caption.
const plotAxisInset = 13;

// Drawing box for one series canvas. `hasSpan` is true when the time axis is
// captioned, which steals height from the bottom of the plot.
function plotGeometry(width, height, hasSpan) {
    return {
        plotWidth: width - plotGutter,
        top: plotTopInset,
        bottom: height - (hasSpan ? plotAxisInset : plotBottomInset)
    };
}

// Sample index to canvas x. Samples are evenly spaced, the first sitting on
// the left edge and the last on the right edge of the plot area.
function xFor(index, count, plotWidth) {
    return index / (count - 1) * plotWidth;
}

// Value to canvas y, inverted so larger values sit higher. A degenerate range
// (min === max) yields NaN; bounds() never produces one, since it pads any
// span narrower than 4.
function yFor(value, range, top, bottom) {
    return bottom - (value - range.min) / (range.max - range.min) * (bottom - top);
}

// Tick labels gain a decimal only when the band is too narrow for whole
// numbers to distinguish the ends.
function tickDecimals(range) {
    return range.max - range.min < 8 ? 1 : 0;
}
