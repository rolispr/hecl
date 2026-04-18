import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    objectName: "root"
    color: "#1e1e2e"
    focus: true
    width: 900
    height: 600

    property bool lispReady: false
    onLispReadyChanged: if (lispReady) reportSize()

    // ── Font metrics ──
    TextMetrics {
        id: charMetrics
        objectName: "charMetrics"
        font.family: "Menlo"
        font.pixelSize: 14
        text: "X"
    }

    property real cellW: charMetrics.width
    property real cellH: charMetrics.height

    // ── Modifier swap (macOS) ──
    function fixModifiers(mods) {
        if (Qt.platform.os !== "osx") return mods;
        var ctrl = 0x04000000, meta = 0x10000000;
        var hasCtrl = (mods & ctrl) !== 0, hasMeta = (mods & meta) !== 0;
        var result = mods & ~(ctrl | meta);
        if (hasCtrl) result |= meta;
        if (hasMeta) result |= ctrl;
        return result;
    }

    // ── Key handling ──
    Keys.onPressed: function(event) {
        if (statusInput.activeFocus) {
            var m = fixModifiers(event.modifiers);
            var isCancel = (event.key === Qt.Key_Escape) ||
                           (event.key === Qt.Key_G && (m & 0x04000000));
            var isDown = (event.key === Qt.Key_N && (m & 0x04000000));
            var isUp = (event.key === Qt.Key_P && (m & 0x04000000));
            if (isCancel || isDown || isUp) {
                Lisp.call(root, "hecl:on-key", event.key, m, event.text)
                event.accepted = true
                return
            }
            return
        }
        Lisp.call(root, "hecl:on-key", event.key, fixModifiers(event.modifiers), event.text)
        event.accepted = true
    }

    // ── Resize reporting ──
    onWidthChanged: reportSize()
    onHeightChanged: reportSize()

    function reportSize() {
        if (lispReady && cellW > 0 && cellH > 0) {
            var cols = Math.floor(width / cellW);
            var rows = Math.floor(displayClip.height / cellH);
            Lisp.call(root, "hecl.qml:report-resize", cols, rows)
        }
    }

    // ── Display area (clipped for smooth scroll) ──
    Item {
        id: displayClip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        clip: true

        Canvas {
            id: display
            objectName: "display"
            width: parent.width
            height: parent.height + cellH  // one extra row for smooth scroll
            y: 0

            property var frameData: []
            property int cursorRow: 0
            property int cursorCol: 0
            property real cellH: root.cellH
            property real scrollPixelY: 0  // scroll_top * cellH, set from C++
            property real prevScrollPixelY: 0

            onFrameDataChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            // When scroll position changes, animate Canvas y offset
            onScrollPixelYChanged: {
                var delta = scrollPixelY - prevScrollPixelY;
                prevScrollPixelY = scrollPixelY;
                if (Math.abs(delta) > 0 && Math.abs(delta) < cellH * 20) {
                    // Start offset at -delta (shows old position), animate to 0
                    scrollAnim.stop();
                    display.y = -delta;
                    scrollAnim.start();
                } else {
                    display.y = 0;
                }
                requestPaint();
            }

            NumberAnimation {
                id: scrollAnim
                target: display
                property: "y"
                to: 0
                duration: 100
                easing.type: Easing.OutCubic
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();

                // Clear background
                ctx.fillStyle = "#1e1e2e";
                ctx.fillRect(0, 0, width, height);

                ctx.textBaseline = "top";
                var cw = cellW, ch = cellH;
                var fd = frameData;
                if (!fd || fd.length === 0) return;

                // frameData is flat: [row, col, codepoint, fg_r, fg_g, fg_b, bg_r, bg_g, bg_b, bold, ...]
                var len = fd.length;
                var prevFont = "";
                for (var i = 0; i + 10 <= len; i += 10) {
                    var r = fd[i], c = fd[i+1], cp = fd[i+2];
                    var fr = fd[i+3], fg = fd[i+4], fb = fd[i+5];
                    var br = fd[i+6], bg = fd[i+7], bb = fd[i+8];
                    var bold = fd[i+9];
                    var x = c * cw, y = r * ch;

                    // Background
                    if (br >= 0) {
                        ctx.fillStyle = "rgb(" + br + "," + bg + "," + bb + ")";
                        ctx.fillRect(x, y, cw, ch);
                    }

                    // Text
                    if (cp > 32) {
                        var newFont = bold ? "bold 14px Menlo" : "14px Menlo";
                        if (newFont !== prevFont) {
                            ctx.font = newFont;
                            prevFont = newFont;
                        }
                        ctx.fillStyle = fr >= 0 ? "rgb("+fr+","+fg+","+fb+")" : "#cdd6f4";
                        ctx.fillText(String.fromCodePoint(cp), x, y);
                    }
                }

            }
        }

        // ── Cursor (inside clip container) ──
        Rectangle {
            id: cursor
            width: cellW
            height: cellH
            color: "#89b4fa"
            opacity: 0.75
            radius: 1
            visible: display.cursorRow >= 0 && display.cursorCol >= 0
            z: 1

            x: display.cursorCol * cellW
            y: display.cursorRow * cellH + display.y

            Behavior on x {
                NumberAnimation {
                    duration: 80
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: 80
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // ── Mouse wheel scrolling ──
    MouseArea {
        anchors.fill: displayClip
        acceptedButtons: Qt.NoButton
        onWheel: {
            if (root.lispReady) {
                // angleDelta.y: positive = scroll up, negative = scroll down
                // 120 units = 1 "click" on most mice
                var lines = -Math.round(wheel.angleDelta.y / 40);
                if (lines !== 0)
                    Lisp.call(root, "hecl.qml:on-scroll", lines)
            }
        }
    }

    // ── Completion area ──
    Rectangle {
        id: completionArea
        objectName: "completionArea"
        anchors.bottom: statusBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: completionText.contentHeight + 8
        color: "#181825"
        visible: false

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: "#89b4fa"
        }

        Text {
            id: completionText
            objectName: "completionText"
            anchors.fill: parent
            anchors.margins: 4
            anchors.topMargin: 5
            color: "#cdd6f4"
            font.family: "Menlo"
            font.pixelSize: 12
            text: ""
        }
    }

    // ── Status bar ──
    Rectangle {
        id: statusBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 28
        color: "#181825"

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: "#313244"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 0

            Rectangle {
                width: modeText.width + 14
                height: 18
                radius: 2
                color: Qt.rgba(0.537, 0.706, 0.98, 0.15)
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: modeText
                    objectName: "statusMode"
                    anchors.centerIn: parent
                    font.family: "Menlo"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: "#89b4fa"
                    text: "INSERT"
                }
            }

            Text {
                id: statusText
                objectName: "statusText"
                Layout.fillWidth: true
                Layout.leftMargin: 10
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
                color: "#6c7086"
                font.family: "Menlo"
                font.pixelSize: 10
                text: "hecl"
                elide: Text.ElideRight
            }

            TextInput {
                id: statusInput
                objectName: "statusInput"
                visible: false
                Layout.fillWidth: true
                Layout.leftMargin: 10
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
                color: "#cdd6f4"
                font.family: "Menlo"
                font.pixelSize: 11

                onAccepted: {
                    Lisp.call(this, "hecl:on-minibuffer-accept", text)
                    text = ""
                }

                onTextChanged: {
                    if (visible && root.lispReady)
                        Lisp.call(this, "hecl.qml:on-input-changed", text)
                }
            }
        }
    }
}
