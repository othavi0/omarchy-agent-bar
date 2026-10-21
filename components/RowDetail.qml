import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-079: the open row's drawer, top to bottom: the pace line, the other
// windows, the reset facts, then one action line. Every section shares the
// left column under the row name and the right edge under the chevron, and
// a full-bleed hairline separates it from the section above.
Column {
  id: root
  objectName: "rowDetail"

  property var row: null
  property int indent: Style.spacing.popupPadding
      + Math.round(Style.font.iconLarge * Tokens.ROW_ICON_SCALE) + Style.space(12)
  property int edge: Style.spacing.popupPadding
  property color well: Commons.Color.popups.background
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
  readonly property int contentWidth: Math.max(0, root.width - root.indent - root.edge)
  readonly property int sectionPadding: Style.space(10)
  readonly property int lineHeight: Style.spacing.controlHeight
  readonly property color secondary: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)

  // The window labels and the reset labels share one column, at least
  // LABEL_COLUMN_EMS wide, so the meters and the reset facts start together.
  readonly property int labelWidth: {
    var widest = Math.round(Style.font.bodySmall * Tokens.LABEL_COLUMN_EMS)
    for (var i = 0; i < root.windows.length; i++)
      widest = Math.max(widest, Math.ceil(labelMetrics.advanceWidth(String(root.windows[i].label))))
    for (var r = 0; r < root.resets.length; r++)
      widest = Math.max(widest, Math.ceil(labelMetrics.advanceWidth(String(root.resets[r].label))))
    return widest
  }

  // Both action buttons take the width of the widest label either can show,
  // so they stay twins and Refreshing never resizes Refresh.
  readonly property int buttonWidth: {
    var labels = ["Refresh", "Refreshing", root.row ? String(root.row.refreshLabel) : "",
                  "Use reset", String(root.useReset.text)]
    var widest = 0
    for (var i = 0; i < labels.length; i++)
      widest = Math.max(widest, buttonMetrics.advanceWidth(labels[i]))
    var glyph = Math.max(glyphMetrics.advanceWidth(Tokens.GLYPH_REFRESH),
                         glyphMetrics.advanceWidth(Tokens.GLYPH_BOLT))
    return Math.ceil(widest + glyph) + Style.spacing.controlGap
        + Style.space(12) * 2 + Style.spacing.hairline * 2
  }

  width: parent ? parent.width : implicitWidth

  function collectFocusTargets() {
    var out = []
    if (useResetButton.visible)
      out.push(useResetButton)
    out.push(refreshButton)
    return out
  }

  FontMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  FontMetrics {
    id: buttonMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  FontMetrics {
    id: glyphMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.icon
  }

  Item {
    id: paceSection
    visible: !!root.pace
    width: parent.width
    height: paceRow.height + root.sectionPadding * 2

    RowLayout {
      id: paceRow
      x: root.indent
      y: root.sectionPadding
      width: root.contentWidth
      height: Math.max(implicitHeight, root.lineHeight)
      spacing: Style.space(10)

      Text {
        objectName: "paceGlyph"
        Layout.alignment: Qt.AlignVCenter
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
        objectName: "paceKey"
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
    id: windowsSection
    visible: root.windows.length > 0
    width: parent.width
    height: windowGrid.implicitHeight + root.sectionPadding * 2

    PanelSeparator {
      objectName: "drawerRule"
      visible: paceSection.visible
      width: parent.width
      foreground: root.foreground
      strength: Tokens.DRAWER_RULE
    }

    GridLayout {
      id: windowGrid
      x: root.indent
      y: root.sectionPadding
      width: root.contentWidth
      flow: GridLayout.TopToBottom
      rows: Math.max(1, root.windows.length)
      columnSpacing: Style.space(12)
      rowSpacing: 0

      Repeater {
        model: root.windows.length
        Text {
          required property int index
          readonly property var line: root.windows[index]
          objectName: "windowLabel"
          Layout.preferredWidth: root.labelWidth
          Layout.minimumHeight: root.lineHeight
          verticalAlignment: Text.AlignVCenter
          text: line ? line.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }

      Repeater {
        model: root.windows.length
        UsageMeter {
          required property int index
          readonly property var line: root.windows[index]
          objectName: "windowMeter"
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
          readonly property bool critical: !!(line && line.critical)
          objectName: "windowValue"
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
          spacing: Style.space(4)

          Text {
            visible: parent.critical
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
            color: parent.critical ? Commons.Color.urgent : root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: parent.critical
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }
      }

      Repeater {
        model: root.windows.length
        Text {
          required property int index
          objectName: "windowReset"
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
    id: resetsSection
    visible: root.resets.length > 0 || root.outcomeText.length > 0
    width: parent.width
    height: resetColumn.implicitHeight + root.sectionPadding * 2

    PanelSeparator {
      objectName: "drawerRule"
      visible: paceSection.visible || windowsSection.visible
      width: parent.width
      foreground: root.foreground
      strength: Tokens.DRAWER_RULE
    }

    Column {
      id: resetColumn
      x: root.indent
      y: root.sectionPadding
      width: root.contentWidth

      Repeater {
        model: root.resets.length
        RowLayout {
          id: resetLine
          required property int index
          readonly property var line: root.resets[index]
          width: parent.width
          spacing: Style.space(12)

          Text {
            objectName: "resetLabel"
            Layout.preferredWidth: root.labelWidth
            Layout.minimumHeight: root.lineHeight
            Layout.alignment: Qt.AlignTop
            verticalAlignment: Text.AlignVCenter
            text: resetLine.line ? resetLine.line.label : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Text {
            objectName: "resetFacts"
            Layout.fillWidth: true
            Layout.minimumHeight: root.lineHeight
            verticalAlignment: Text.AlignVCenter
            text: resetLine.line ? resetLine.line.facts.join(" · ") : ""
            color: root.tertiary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            Accessible.ignored: true
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
    id: actionSection
    width: parent.width
    height: actionRow.height + root.sectionPadding * 2

    PanelSeparator {
      objectName: "drawerRule"
      visible: paceSection.visible || windowsSection.visible || resetsSection.visible
      width: parent.width
      foreground: root.foreground
      strength: Tokens.DRAWER_RULE
    }

    RowLayout {
      id: actionRow
      x: root.indent
      y: root.sectionPadding
      width: root.contentWidth
      height: Math.max(implicitHeight, root.lineHeight)
      spacing: Style.space(12)

      Row {
        Layout.fillWidth: true
        Layout.preferredHeight: root.lineHeight
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(6)
        visible: updatedText.text.length > 0

        Text {
          objectName: "updatedClock"
          anchors.verticalCenter: parent.verticalCenter
          text: Tokens.GLYPH_CLOCK
          color: root.tertiary
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
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

      Row {
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(8)

        // Tonal, borderless twins. A claimable reset is the accent primary;
        // a spent or busy one rests on the faint disabled tone.
        Button {
          id: useResetButton
          objectName: "useResetButton"
          visible: root.useReset.visible
          enabled: root.useReset.enabled
          width: root.buttonWidth
          height: root.lineHeight
          text: root.useReset.text
          iconText: Tokens.GLYPH_BOLT
          bordered: false
          focusable: true
          horizontalPadding: Style.space(12)
          fontSize: Style.font.bodySmall
          foreground: useResetButton.enabled ? root.foreground : root.tertiary
          fontFamily: root.fontFamily
          background: useResetButton.enabled
              ? Tokens.mix(root.well, Commons.Color.accent, Tokens.PRIMARY_REST)
              : Tokens.mix(root.well, root.foreground, Tokens.BUTTON_OFF)
          color: useResetButton.enabled && (useResetButton.hot || useResetButton.activeFocus)
              ? Tokens.mix(root.well, Commons.Color.accent, Tokens.PRIMARY_HOT)
              : useResetButton.background
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
          width: root.buttonWidth
          height: root.lineHeight
          iconText: Tokens.GLYPH_REFRESH
          iconSpinning: root.refreshing
          text: root.refreshing ? "Refreshing" : (root.row ? root.row.refreshLabel : "Refresh")
          bordered: false
          focusable: true
          horizontalPadding: Style.space(12)
          fontSize: Style.font.bodySmall
          foreground: root.foreground
          fontFamily: root.fontFamily
          background: Tokens.mix(root.well, root.foreground, Tokens.BUTTON_REST)
          color: refreshButton.hot || refreshButton.activeFocus
              ? Tokens.mix(root.well, root.foreground, Tokens.BUTTON_HOT)
              : refreshButton.background
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
}
