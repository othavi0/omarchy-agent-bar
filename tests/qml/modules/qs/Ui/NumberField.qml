import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host labelled spin box.
Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldWidth: Style.spacing.numberFieldWidth
  property bool hasCursor: false
  property alias field: spin

  signal modified(int value)
  signal hovered(bool on)

  spacing: Style.spacing.labelGap

  Text {
    visible: root.label.length > 0
    text: root.label
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  SpinBox {
    id: spin
    width: root.fieldWidth
    from: root.from
    to: root.to
    stepSize: root.stepSize
    value: root.value
    editable: true
    onValueModified: root.modified(value)
  }
}
