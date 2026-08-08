import QtQuick

Item {
    id: root

    required property bool connected
    required property var strength
    required property color glyphColor

    readonly property int arcCount: {
        if (!connected)
            return 0;
        if (typeof strength !== "number" || !Number.isFinite(strength))
            return 3;
        if (strength >= 70)
            return 3;
        if (strength >= 35)
            return 2;
        return 1;
    }

    implicitWidth: 17
    implicitHeight: 15

    onConnectedChanged: canvas.requestPaint()
    onStrengthChanged: canvas.requestPaint()
    onGlyphColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        function drawSignal(context, count): void {
            const centerX = width / 2;
            const centerY = height - 2;
            context.beginPath();
            context.arc(centerX, centerY, 1.25, 0, Math.PI * 2);
            context.fill();
            const radii = [4.1, 7.4];
            for (let index = 0; index < count - 1; ++index) {
                context.beginPath();
                context.arc(
                    centerX,
                    centerY,
                    radii[index],
                    Math.PI * 1.16,
                    Math.PI * 1.84
                );
                context.stroke();
            }
        }

        onPaint: {
            const context = getContext("2d");
            context.reset();
            context.strokeStyle = root.glyphColor;
            context.fillStyle = root.glyphColor;
            context.lineWidth = 1.5;
            context.lineCap = "round";
            context.globalAlpha = root.connected ? 0.9 : 0.38;
            drawSignal(context, root.connected ? root.arcCount : 3);
            if (!root.connected) {
                context.beginPath();
                context.moveTo(3, 2);
                context.lineTo(width - 3, height - 2);
                context.stroke();
            }
        }
    }
}
