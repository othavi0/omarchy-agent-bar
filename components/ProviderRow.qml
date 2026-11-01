import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// One provider group, drawn as a slab. A header line carries the icon, the
// name and the plan, with the short state note and the action buttons on its
// right. Under it each window takes one line: label, bar, percentage and
// reset, in the columns OverviewList shares with every group. A provider
// without a reading shows its state copy in place of the windows. A band of
// popup floor ends every group but the last. Every field comes from the row
// model; only the action buttons take focus.
Item {
  id: root
  objectName: "providerRow"

  property var row: null
  property var columns: ({ label: 0, percent: 0, reset: 0 })
  property bool last: false
  property int topRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal actionRequested(string id, var action)

  readonly property string rowId: root.row ? root.row.id : ""
  readonly property var windows: root.row && root.row.windows ? root.row.windows : []
  readonly property var actions: root.row && root.row.actions ? root.row.actions : []
  readonly property string note: root.row && root.row.note ? root.row.note : ""
  readonly property string detail: root.row ? root.row.detail : ""
  readonly property var tones: Tokens.surfaces(Commons.Color.popups.background, root.foreground)
  readonly property color secondary: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
  readonly property int inset: Style.spacing.popupPadding
  readonly property int gap: Style.space(8)
  readonly property int contentWidth: Math.max(0, root.width - root.inset * 2)
  readonly property int barX: root.columns.label + root.gap
  readonly property int resetRoom: root.columns.reset > 0 ? root.columns.reset + root.gap : 0
  readonly property int barWidth: Math.max(0, root.contentWidth - root.barX
      - root.gap - root.columns.percent - root.resetRoom)

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight
  height: implicitHeight

  Accessible.role: Accessible.Grouping
  Accessible.name: root.row ? root.row.accessibleName : ""
  Accessible.description: root.detail

  function collectFocusTargets() {
    var out = []
    for (var i = 0; i < actionRepeater.count; i++) {
      var button = actionRepeater.itemAt(i)
      if (button && button.visible && button.enabled)
        out.push(button)
    }
    return out
  }

  Rectangle {
    objectName: "rowPlate"
    anchors.fill: parent
    topLeftRadius: root.topRadius
    topRightRadius: root.topRadius
    color: root.tones.slab
  }

  Column {
    id: body
    width: parent.width

    Item {
      width: parent.width
      height: content.implicitHeight + Style.space(12) * 2

      Column {
        id: content
        x: root.inset
        y: Style.space(12)
        width: root.contentWidth
        spacing: Style.space(8)

        Item {
          id: header
          width: parent.width
          height: Math.max(icon.height, name.implicitHeight, noteText.implicitHeight,
                           actionRow.visible ? actionRow.implicitHeight : 0)

          ProviderIcon {
            id: icon
            objectName: "providerIcon"
            anchors.verticalCenter: parent.verticalCenter
            providerId: root.rowId
            size: Style.font.iconLarge
            dimmed: !!(root.row && root.row.dimIcon)
            foreground: root.foreground
          }

          Text {
            id: name
            objectName: "rowName"
            anchors.left: icon.right
            anchors.leftMargin: root.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.row ? root.row.name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          // The plan yields first: it elides before the note or an action
          // gives up room.
          Text {
            id: plan
            objectName: "rowPlan"
            readonly property int room: header.width - (name.x + name.width + root.gap)
                - (noteText.text.length ? noteText.width + root.gap : 0)
                - (actionRow.visible ? actionRow.width + root.gap : 0)
            visible: text.length > 0 && room >= Style.space(24)
            anchors.left: name.right
            anchors.leftMargin: root.gap
            anchors.baseline: name.baseline
            width: Math.min(implicitWidth, Math.max(0, room))
            text: root.row ? root.row.plan : ""
            color: root.tertiary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Text {
            id: noteText
            objectName: "groupNote"
            readonly property int room: header.width - (name.x + name.width + root.gap)
                - (actionRow.visible ? actionRow.width + root.gap : 0)
            visible: text.length > 0
            anchors.right: actionRow.visible ? actionRow.left : parent.right
            anchors.rightMargin: actionRow.visible ? root.gap : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, room))
            horizontalAlignment: Text.AlignRight
            text: root.note
            color: root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Row {
            id: actionRow
            visible: root.actions.length > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Repeater {
              id: actionRepeater
              model: root.actions.length

              ActionButton {
                required property int index
                readonly property var action: root.actions[index] || null
                objectName: "groupAction"
                visible: !!action
                enabled: !!(action && action.enabled)
                surface: root.tones.slab
                text: action ? action.label : ""
                fontFamily: root.fontFamily
                onActivated: root.actionRequested(root.rowId, action)
              }
            }
          }
        }

        Repeater {
          model: root.windows.length

          Item {
            id: windowLine
            required property int index
            readonly property var line: root.windows[index] || null
            objectName: "windowLine"
            width: content.width
            height: Math.max(windowLabel.implicitHeight, windowPercent.implicitHeight, meter.implicitHeight)

            Text {
              id: windowLabel
              objectName: "windowLabel"
              anchors.verticalCenter: parent.verticalCenter
              width: root.columns.label
              text: windowLine.line ? windowLine.line.label : ""
              color: root.secondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              textFormat: Text.PlainText
              Accessible.ignored: true
            }

            UsageMeter {
              id: meter
              objectName: "windowMeter"
              x: root.barX
              anchors.verticalCenter: parent.verticalCenter
              width: root.barWidth
              percent: windowLine.line ? windowLine.line.percent : -1
              critical: !!(windowLine.line && windowLine.line.critical)
              foreground: root.foreground
            }

            Text {
              id: windowPercent
              objectName: "windowPercent"
              x: root.barX + root.barWidth + root.gap
              anchors.verticalCenter: parent.verticalCenter
              width: root.columns.percent
              horizontalAlignment: Text.AlignRight
              text: windowLine.line ? windowLine.line.percentText : ""
              color: windowLine.line && windowLine.line.critical ? Commons.Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.weight: Font.Medium
              font.features: ({ "tnum": 1 })
              textFormat: Text.PlainText
              Accessible.ignored: true
            }

            Text {
              objectName: "windowReset"
              visible: root.columns.reset > 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: root.columns.reset
              horizontalAlignment: Text.AlignRight
              text: windowLine.line ? windowLine.line.resetText : ""
              color: root.tertiary
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.features: ({ "tnum": 1 })
              textFormat: Text.PlainText
              Accessible.ignored: true
            }
          }
        }

        Text {
          objectName: "groupDetail"
          visible: text.length > 0
          width: parent.width
          text: root.detail
          color: root.secondary
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          Accessible.ignored: true
        }
      }
    }

    Rectangle {
      objectName: "rowBand"
      width: parent.width
      height: Style.space(4)
      visible: !root.last
      color: root.tones.floor
    }

    PanelSeparator {
      objectName: "edgeRule"
      width: parent.width
      visible: !root.last
      foreground: root.foreground
      strength: Tokens.RIM
    }
  }
}
