import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-079: the open row's detail, top to bottom: the pace line, the other
// windows, the reset facts, then one action line. Each block draws its own
// full-width rule and indents its content under the row name.
Column {
  id: root
  objectName: "rowDetail"

  property var row: null
  property int indent: Style.spacing.popupPadding
      + Math.round(Style.font.iconLarge * Tokens.ROW_ICON_SCALE) + Style.space(12)
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal refreshRequested()
  signal resetRequested(string resetId)

  readonly property var pace: root.row && root.row.pace ? root.row.pace : null
  readonly property var windows: root.row && root.row.windows ? root.row.windows : []
  readonly property var resets: root.row && root.row.resets ? root.row.resets : []
  readonly property var useReset: root.row && root.row.useReset
      ? root.row.useReset
      : ({ visible: false, enabled: false, resetId: null, text: "Use reset" })
  readonly property bool refreshing: !!(root.row && root.row.refreshing)
  readonly property string outcomeText: root.row ? root.row.outcomeText : ""
  readonly property int contentWidth: Math.max(0, root.width - root.indent - Style.spacing.popupPadding)
  readonly property color secondary: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)

  width: parent ? parent.width : implicitWidth

  function collectFocusTargets() {
    var out = []
    if (useResetButton.visible)
      out.push(useResetButton)
    out.push(refreshButton)
    return out
  }

  Item {
    id: paceBlock
    visible: !!root.pace
    width: parent.width
    height: paceRow.implicitHeight + Style.space(8) + Style.space(10)

    PanelSeparator {
      objectName: "edgeRule"
      width: parent.width
      foreground: root.foreground
    }

    RowLayout {
      id: paceRow
      x: root.indent
      y: Style.space(8)
      width: root.contentWidth
      spacing: Style.space(10)

      Text {
        Layout.alignment: Qt.AlignTop
        text: root.pace ? root.pace.glyph : ""
        color: root.pace && root.pace.critical
            ? Commons.Color.urgent
            : (root.pace && root.pace.kind === "runsOut" ? root.secondary : root.tertiary)
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
        textFormat: Text.PlainText
        Accessible.ignored: true
      }

      Flow {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter

        Text {
          visible: text.length > 0
          text: root.pace ? root.pace.text : ""
          width: Math.min(implicitWidth, parent.width)
          color: root.pace && root.pace.kind === "tooEarly" ? root.tertiary : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          Accessible.ignored: true
        }

        Text {
          visible: text.length > 0
          text: root.pace ? root.pace.strong : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          textFormat: Text.PlainText
          Accessible.ignored: true
        }

        Text {
          visible: text.length > 0
          text: root.pace ? root.pace.rest : ""
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }

      Row {
        visible: !!root.pace && root.pace.key.length > 0
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: Style.space(12)
        spacing: Style.space(4)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.spacing.hairline
          height: Style.font.icon
          color: root.tertiary
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.pace ? root.pace.key : ""
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }
    }
  }

  Item {
    id: windowsBlock
    visible: root.windows.length > 0
    width: parent.width
    height: windowGrid.implicitHeight + windowGrid.y + Style.space(12)

    PanelSeparator {
      objectName: "edgeRule"
      visible: !paceBlock.visible
      width: parent.width
      foreground: root.foreground
    }

    GridLayout {
      id: windowGrid
      x: root.indent
      y: paceBlock.visible ? 0 : Style.space(10)
      width: root.contentWidth
      flow: GridLayout.TopToBottom
      rows: Math.max(1, root.windows.length)
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(10)

      Repeater {
        model: root.windows.length
        Text {
          required property int index
          readonly property var line: root.windows[index]
          text: line ? line.label : ""
          color: root.secondary
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }

      Repeater {
        model: root.windows.length
        UsageMeter {
          required property int index
          readonly property var line: root.windows[index]
          Layout.fillWidth: true
          Layout.minimumWidth: Style.space(50)
          thin: true
          percent: line ? line.percent : -1
          critical: !!(line && line.critical)
          tickPercent: line ? line.tickPercent : -1
          foreground: root.foreground
        }
      }

      Repeater {
        model: root.windows.length
        Row {
          required property int index
          readonly property var line: root.windows[index]
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
          spacing: Style.space(4)

          Text {
            visible: !!(parent.line && parent.line.critical)
            anchors.verticalCenter: parent.verticalCenter
            text: Tokens.GLYPH_ALERT
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.iconSmall
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.line ? parent.line.percentText : ""
            color: parent.line && parent.line.critical ? Commons.Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }
      }

      Repeater {
        model: root.windows.length
        Text {
          required property int index
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
          text: root.windows[index] ? root.windows[index].resetCellText : ""
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }
    }
  }

  Item {
    id: resetsBlock
    visible: root.resets.length > 0 || root.outcomeText.length > 0
    width: parent.width
    height: resetColumn.implicitHeight + Style.space(16)

    PanelSeparator {
      objectName: "edgeRule"
      width: parent.width
      foreground: root.foreground
    }

    Column {
      id: resetColumn
      x: root.indent
      y: Style.space(8)
      width: root.contentWidth
      spacing: Style.space(6)

      Repeater {
        model: root.resets.length
        Flow {
          id: resetLine
          required property int index
          readonly property var line: root.resets[index]
          readonly property var facts: line ? line.facts : []
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: resetLine.line ? resetLine.line.label + (resetLine.facts.length ? " ·" : "") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Repeater {
            model: resetLine.facts.length
            Text {
              required property int index
              text: resetLine.facts.length > index
                  ? resetLine.facts[index] + (index < resetLine.facts.length - 1 ? " ·" : "")
                  : ""
              color: root.tertiary
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
              Accessible.ignored: true
            }
          }
        }
      }

      Text {
        visible: root.outcomeText.length > 0
        width: parent.width
        text: root.outcomeText
        color: root.secondary
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }
    }
  }

  Item {
    id: actionLine
    width: parent.width
    height: actionRow.implicitHeight + Style.space(8) + Style.space(16)

    PanelSeparator {
      objectName: "edgeRule"
      width: parent.width
      foreground: root.foreground
    }

    RowLayout {
      id: actionRow
      x: root.indent
      y: Style.space(8)
      width: root.contentWidth
      spacing: Style.space(8)

      Row {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(6)
        visible: updatedText.text.length > 0

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: Tokens.GLYPH_CLOCK
          color: root.tertiary
          font.family: Style.font.family
          font.pixelSize: Style.font.iconSmall
          textFormat: Text.PlainText
          Accessible.ignored: true
        }

        Text {
          id: updatedText
          anchors.verticalCenter: parent.verticalCenter
          text: root.row ? root.row.updatedText : ""
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }
      }

      Item {
        Layout.fillWidth: true
        visible: updatedText.text.length === 0
      }

      Button {
        id: useResetButton
        visible: root.useReset.visible
        enabled: root.useReset.enabled
        text: root.useReset.text
        bordered: true
        focusable: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Use reset"
        function focusActivate() {
          if (root.useReset.enabled && root.useReset.resetId)
            root.resetRequested(String(root.useReset.resetId))
        }
        Accessible.onPressAction: focusActivate()
        onClicked: focusActivate()
      }

      Button {
        id: refreshButton
        objectName: "refreshButton"
        iconText: Tokens.GLYPH_REFRESH
        iconSpinning: root.refreshing
        text: root.refreshing ? "Refreshing" : (root.row ? root.row.refreshLabel : "Refresh")
        bordered: true
        focusable: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: text
        function focusActivate() {
          root.refreshRequested()
        }
        Accessible.onPressAction: focusActivate()
        onClicked: focusActivate()
      }
    }
  }
}
