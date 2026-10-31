import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../CoreView.js" as Core
import "Tokens.js" as Tokens

// One provider group, drawn as a slab in two columns. The left column has a
// fixed width: icon and name, plan, short notes, then the actions stacked.
// The right column stacks every window: a label line with the reset on the
// right, then a full-width bar with the percentage in a fixed column, so
// every bar in the popup shares one width. A band of popup floor ends every
// group but the last. Every field comes from the row model.
Item {
  id: root
  objectName: "providerRow"

  property var row: null
  property bool last: false
  property int topRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal selectRequested(string id)
  signal actionRequested(string id, var action)

  readonly property Item headItem: headHit
  readonly property string rowId: root.row ? root.row.id : ""
  readonly property bool selected: !!(root.row && root.row.selected)
  readonly property var windows: root.row && root.row.windows ? root.row.windows : []
  readonly property var notes: root.row && root.row.notes ? root.row.notes : []
  readonly property var actions: root.row && root.row.actions ? root.row.actions : []
  readonly property string detail: root.row ? root.row.detail : ""
  readonly property var tones: Tokens.surfaces(Commons.Color.popups.background, root.foreground)
  readonly property color plateColor: root.selected
      ? Tokens.mix(root.tones.slab, Commons.Color.accent, Tokens.GROUP_SELECTED)
      : root.tones.slab
  readonly property color secondary: Util.alpha(root.foreground, Tokens.TEXT_SECONDARY)
  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)
  readonly property color accentText: Tokens.readableAccent(
      Commons.Color.accent,
      Tokens.mix(root.plateColor, Commons.Color.accent, Tokens.PRIMARY_PRESS),
      root.foreground)
  readonly property int sideWidth: Style.space(Tokens.SIDE_COLUMN_PX)
  readonly property int inset: Style.spacing.popupPadding
  readonly property int gutter: Style.space(12)
  readonly property int percentWidth: Math.ceil(percentMetrics.advanceWidth("100%"))

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight
  height: implicitHeight

  function collectFocusTargets() {
    var out = []
    if (!root.row)
      return out
    out.push(headHit)
    for (var i = 0; i < actionRepeater.count; i++) {
      var button = actionRepeater.itemAt(i)
      if (button && button.visible && button.enabled)
        out.push(button)
    }
    return out
  }

  FontMetrics {
    id: percentMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.weight: Font.Medium
  }

  Rectangle {
    objectName: "rowPlate"
    anchors.fill: parent
    topLeftRadius: root.topRadius
    topRightRadius: root.topRadius
    color: root.plateColor
  }

  Column {
    id: body
    width: parent.width

    Item {
      id: group
      width: parent.width
      height: Math.max(side.implicitHeight, main.implicitHeight) + Style.space(12) * 2

      Rectangle {
        objectName: "rowHover"
        anchors.fill: parent
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        visible: headMouse.containsMouse && !root.selected
        color: Style.hoverFill
      }

      // The group is one focus stop. Enter runs its primary action; a click
      // selects it.
      Item {
        id: headHit
        objectName: "rowHead"
        anchors.fill: parent

        function focusActivate() {
          var action = Core.primaryAction(root.actions)
          if (action)
            root.actionRequested(root.rowId, action)
        }

        Keys.onReturnPressed: headHit.focusActivate()
        Keys.onEnterPressed: headHit.focusActivate()
        Keys.onSpacePressed: headHit.focusActivate()

        Accessible.role: Accessible.Button
        Accessible.name: root.row ? root.row.accessibleName : ""
        Accessible.description: root.detail
        Accessible.onPressAction: headHit.focusActivate()

        MouseArea {
          id: headMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.selectRequested(root.rowId)
        }

        Rectangle {
          objectName: "rowFocusRing"
          anchors.fill: parent
          anchors.margins: Style.space(4)
          radius: Style.cornerRadius
          color: "transparent"
          border.color: Commons.Color.accent
          border.width: Style.spacing.hairline
          visible: headHit.activeFocus
        }
      }

      Column {
        id: side
        objectName: "sideColumn"
        x: root.inset
        y: Style.space(12)
        width: root.sideWidth
        spacing: Style.space(4)

        Row {
          width: parent.width
          spacing: Style.space(8)

          ProviderIcon {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            providerId: root.rowId
            size: Style.font.iconLarge
            dimmed: !!(root.row && root.row.dimIcon)
            foreground: root.foreground
          }

          Text {
            objectName: "rowName"
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - icon.width - parent.spacing
            text: root.row ? root.row.name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }

        Text {
          objectName: "rowPlan"
          visible: text.length > 0
          width: parent.width
          text: root.row ? root.row.plan : ""
          color: root.tertiary
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          Accessible.ignored: true
        }

        Repeater {
          model: root.notes.length
          Text {
            required property int index
            objectName: "groupNote"
            width: side.width
            text: root.notes[index] || ""
            color: root.secondary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }

        Item {
          visible: root.actions.length > 0
          width: parent.width
          height: Style.space(4)
        }

        Repeater {
          id: actionRepeater
          model: root.actions.length

          // Tonal primary: the accent at a low share over the slab, its label
          // the accent pulled to readable contrast. A secondary action is
          // text alone. Both paint their own hover, focus and press tones.
          Button {
            id: actionButton
            required property int index
            readonly property var action: root.actions[index] || null
            readonly property bool primary: !!(action && action.primary)
            readonly property color fillTo: primary ? Commons.Color.accent : root.foreground
            objectName: primary ? "primaryAction" : "secondaryAction"
            visible: !!action
            enabled: !!(action && action.enabled)
            width: Math.min(actionButton.implicitWidth, root.sideWidth)
            height: Style.spacing.controlHeight
            text: action ? action.label : ""
            bordered: false
            focusable: true
            horizontalPadding: Style.space(8)
            fontSize: Style.font.bodySmall
            fontFamily: root.fontFamily
            foreground: !actionButton.enabled ? root.tertiary
                : (actionButton.primary ? root.accentText : root.secondary)
            background: !actionButton.primary ? "transparent"
                : (actionButton.enabled
                    ? Tokens.mix(root.plateColor, Commons.Color.accent, Tokens.PRIMARY_REST)
                    : Tokens.mix(root.plateColor, root.foreground, Tokens.BUTTON_OFF))
            color: !actionButton.enabled ? actionButton.background
                : actionPress.active
                    ? Tokens.mix(root.plateColor, actionButton.fillTo,
                                 actionButton.primary ? Tokens.PRIMARY_PRESS : Tokens.BUTTON_PRESS)
                : actionButton.hot || actionButton.activeFocus
                    ? Tokens.mix(root.plateColor, actionButton.fillTo,
                                 actionButton.primary ? Tokens.PRIMARY_HOT : Tokens.BUTTON_HOT)
                    : actionButton.background
            Accessible.name: text
            function focusActivate() {
              if (actionButton.action && actionButton.action.enabled)
                root.actionRequested(root.rowId, actionButton.action)
            }
            Accessible.onPressAction: focusActivate()
            onClicked: focusActivate()

            // Setting `color` replaces the host fill rule, press included, and
            // the host MouseArea is private. A passive handler above it sees
            // the press without taking the click.
            Item {
              anchors.fill: parent
              PointHandler { id: actionPress; acceptedButtons: Qt.LeftButton }
            }
          }
        }
      }

      Column {
        id: main
        objectName: "windowColumn"
        x: root.inset + root.sideWidth + root.gutter
        y: Style.space(12)
        width: Math.max(0, root.width - x - root.inset)
        spacing: Style.space(8)

        Repeater {
          model: root.windows.length

          Column {
            id: windowLine
            required property int index
            readonly property var line: root.windows[index] || null
            objectName: "windowLine"
            width: main.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: Math.max(windowLabel.implicitHeight, windowReset.implicitHeight)

              Text {
                id: windowLabel
                objectName: "windowLabel"
                width: parent.width - windowReset.implicitWidth
                    - (windowReset.text.length ? Style.space(8) : 0)
                text: windowLine.line ? windowLine.line.label : ""
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                textFormat: Text.PlainText
                Accessible.ignored: true
              }

              Text {
                id: windowReset
                objectName: "windowReset"
                anchors.right: parent.right
                anchors.baseline: windowLabel.baseline
                text: windowLine.line ? windowLine.line.resetText : ""
                color: root.tertiary
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.features: ({ "tnum": 1 })
                textFormat: Text.PlainText
                Accessible.ignored: true
              }
            }

            Item {
              width: parent.width
              height: Math.max(meter.implicitHeight, windowPercent.implicitHeight)

              UsageMeter {
                id: meter
                objectName: "windowMeter"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - root.percentWidth - Style.space(8)
                percent: windowLine.line ? windowLine.line.percent : -1
                critical: !!(windowLine.line && windowLine.line.critical)
                foreground: root.foreground
              }

              Text {
                id: windowPercent
                objectName: "windowPercent"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.percentWidth
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
