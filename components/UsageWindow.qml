import QtQuick
import qs.Commons

Item {
  id: root

  property string label: ""
  property string percentText: "—"
  property real percent: -1
  property string resetCountdown: ""
  property string resetClock: ""
  property string resetPhrase: ""
  property string unitText: "left"
  property string severity: ""
  property bool emphasis: true
  property bool dimmed: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  readonly property bool hasPercent: root.percent >= 0 && root.percent <= 100
  readonly property real fillRatio: hasPercent
      ? Math.max(0, Math.min(1, root.percent / 100))
      : 0
  readonly property bool isCritical: root.severity === "critical"
  readonly property color valueColor: root.isCritical ? Color.urgent : root.foreground
  readonly property color fillColor: root.isCritical
      ? Color.urgent
      : (root.dimmed ? root.foreground : root.accent)
  readonly property real fillOpacity: root.dimmed ? 0.45 : (root.isCritical ? 1.0 : 0.9)
  readonly property color trackColor: Util.alpha(root.foreground, 0.12)

  width: parent ? parent.width : implicitWidth
  implicitHeight: root.emphasis ? bigCol.implicitHeight : compactRow.implicitHeight
  height: implicitHeight
  opacity: root.dimmed ? 0.6 : 1.0

  TextMetrics {
    id: countdownMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "23h 59m"
  }

  TextMetrics {
    id: valueMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    text: "100%"
  }

  Column {
    id: bigCol
    visible: root.emphasis
    width: parent.width
    spacing: Style.spacing.sm

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        id: leadLabel
        width: Math.min(implicitWidth,
                        Math.max(0, parent.width - leadReset.implicitWidth - Style.spacing.sm))
        text: root.resetPhrase.length > 0
            ? root.label + " · " + root.resetPhrase
            : root.label
        color: Util.alpha(root.foreground, 0.72)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        textFormat: Text.PlainText
        Accessible.ignored: true
      }

      Text {
        id: leadReset
        text: root.resetClock.length > 0
            ? root.resetCountdown + " " + root.resetClock
            : root.resetCountdown
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        Accessible.ignored: true
      }
    }

    Row {
      spacing: Style.spacing.md

      Text {
        id: bigNumeral
        text: root.percentText
        color: root.valueColor
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.body * 2.5)
        font.bold: true
        textFormat: Text.PlainText
        Accessible.ignored: true
      }

      Text {
        anchors.baseline: bigNumeral.baseline
        text: root.unitText
        color: Util.alpha(root.foreground, 0.72)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        Accessible.ignored: true
      }
    }

    Rectangle {
      width: parent.width
      height: Style.spacing.md
      radius: height / 2
      color: root.trackColor
      Accessible.ignored: true

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(root.hasPercent && root.fillRatio > 0 ? Style.spacing.md : 0,
                        parent.width * root.fillRatio)
        height: parent.height
        radius: parent.radius
        color: root.fillColor
        opacity: root.fillOpacity
        visible: root.hasPercent && root.fillRatio > 0
      }
    }
  }

  Row {
    id: compactRow
    visible: !root.emphasis
    width: parent.width
    spacing: Style.spacing.lg

    Text {
      id: compactLabel
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, Math.round(parent.width * 0.25))
      text: root.label
      color: Util.alpha(root.foreground, 0.72)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      textFormat: Text.PlainText
      Accessible.ignored: true
    }

    Rectangle {
      id: compactTrack
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width
                         - compactLabel.width
                         - compactValue.width
                         - compactReset.width
                         - Style.spacing.lg * 3)
      height: Style.spacing.sm
      radius: height / 2
      color: root.trackColor
      Accessible.ignored: true

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(root.hasPercent && root.fillRatio > 0 ? Style.spacing.sm : 0,
                        parent.width * root.fillRatio)
        height: parent.height
        radius: parent.radius
        color: root.fillColor
        opacity: root.fillOpacity
        visible: root.hasPercent && root.fillRatio > 0
      }
    }

    Text {
      id: compactValue
      anchors.verticalCenter: parent.verticalCenter
      width: valueMetrics.advanceWidth
      horizontalAlignment: Text.AlignRight
      text: root.percentText
      color: root.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      textFormat: Text.PlainText
      Accessible.ignored: true
    }

    Text {
      id: compactReset
      anchors.verticalCenter: parent.verticalCenter
      width: countdownMetrics.advanceWidth
      horizontalAlignment: Text.AlignRight
      text: root.resetCountdown
      color: Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      Accessible.ignored: true
    }
  }

  Accessible.name: {
    var parts = [root.label, root.percentText + " " + root.unitText]
    if (root.severity === "critical")
      parts.push("critical")
    else if (root.severity === "warning")
      parts.push("low")
    if (root.resetCountdown.length > 0)
      parts.push(root.resetClock.length > 0
          ? root.resetPhrase + " " + root.resetCountdown + " " + root.resetClock
          : root.resetPhrase + " " + root.resetCountdown)
    return parts.join(", ")
  }
  Accessible.role: Accessible.StaticText
}
