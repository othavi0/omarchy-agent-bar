import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host segmented control.
Row {
  id: root

  property var options: []
  property string value: ""
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property bool focusable: true
  property int cursorIndex: -1

  signal changed(string value)
  signal hovered(int index, bool isHovered)

  function optionValue(o) { return typeof o === "object" ? String(o.value) : String(o) }
  function optionLabel(o) { return typeof o === "object" ? String(o.label || o.value) : String(o) }

  function selectedOptionIndex() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value)
        return i
    }
    return -1
  }

  function activateFocused() {
    if (cursorIndex >= 0 && cursorIndex < options.length)
      changed(optionValue(options[cursorIndex]))
  }

  spacing: 0
  activeFocusOnTab: focusable

  Repeater {
    model: root.options

    Button {
      required property var modelData
      text: root.optionLabel(modelData)
      selected: root.optionValue(modelData) === root.value
      bordered: true
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      onClicked: root.changed(root.optionValue(modelData))
    }
  }
}
