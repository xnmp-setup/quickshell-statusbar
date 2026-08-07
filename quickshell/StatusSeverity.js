.pragma library

// The two alert hues used across every cell. Named once so a palette change
// cannot drift between the metric, temperature and quota call sites.
const alertColor = "#fb4934";
const warnColor = "#fabd2f";

// Generic percentage metrics (CPU/RAM/IO/GPU) go red above 75 and amber from
// 50 up. Deliberately asymmetric: strictly greater for the alert, at-or-above
// for the warning. Do not normalize — the bar has always read this way.
const metricAlertAbove = 75;
const metricWarnFrom = 50;

// Quota consumption reads the other way round: both bounds are inclusive.
const usageAlertFrom = 90;
const usageWarnFrom = 75;

// A temperature is only rendered once it is already hot, so its cool band is
// amber rather than normal text.
const temperatureAlertFrom = 85;

// Battery charge counts down, so the thresholds are upper bounds.
const batteryAlertAtMost = 10;
const batteryWarnAtMost = 25;

// Wi-Fi signal strength, also counting down, but with exclusive bounds.
const wifiAlertBelow = 20;
const wifiWarnBelow = 40;

// Severity levels shared by the bar and the cells: 0 normal, 1 warn, 2 alert.
// -1 means "no opinion", which defers to the percentage thresholds.
const normalLevel = 0;
const warnLevel = 1;
const alertLevel = 2;
const derivedLevel = -1;

// Colour for a plain percentage metric. `normalColor` is the theme's body text
// and is also what a missing reading renders as.
function valueColor(metric, normalColor) {
    if (metric === null || metric === undefined)
        return normalColor;
    if (metric > metricAlertAbove)
        return alertColor;
    if (metric >= metricWarnFrom)
        return warnColor;
    return normalColor;
}

// An explicit severity wins over the value; -1 falls back to valueColor.
function severityColor(metric, level, normalColor) {
    if (level === alertLevel)
        return alertColor;
    if (level === warnLevel)
        return warnColor;
    if (level === normalLevel)
        return normalColor;
    return valueColor(metric, normalColor);
}

function temperatureColor(temperature) {
    return temperature >= temperatureAlertFrom ? alertColor : warnColor;
}

// Quota percentage. A missing reading dims rather than falling back to body
// text, because the cell is showing "--" and should recede.
function usagePercentColor(percent, normalColor, dimColor) {
    if (percent === null || percent === undefined)
        return dimColor;
    if (percent >= usageAlertFrom)
        return alertColor;
    if (percent >= usageWarnFrom)
        return warnColor;
    return normalColor;
}

// The bar only shows a temperature when it is already hot, so there is no
// normal level here.
function temperatureSeverity(value) {
    return value >= temperatureAlertFrom ? alertLevel : warnLevel;
}

function batterySeverity(value) {
    if (value === null || value === undefined)
        return warnLevel;
    if (value <= batteryAlertAtMost)
        return alertLevel;
    if (value <= batteryWarnAtMost)
        return warnLevel;
    return normalLevel;
}

// A disconnected or unreadable radio warns rather than alerting: it is usually
// a deliberate state, not a fault.
function wifiSeverity(connected, value) {
    if (!connected || value === null || value === undefined)
        return warnLevel;
    if (value < wifiAlertBelow)
        return alertLevel;
    if (value < wifiWarnBelow)
        return warnLevel;
    return normalLevel;
}
