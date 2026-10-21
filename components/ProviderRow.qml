import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tokens.js" as Tokens

// UX-077/078: one provider. The head is the accordion toggle; the detail
// shows only while the row is open. Every field comes from the row model.
Item {
  id: root
  objectName: "providerRow"

  property var row: null
  property bool last: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal toggleRequested(string id)
  signal actionRequested(string id, string kind, var target)
  signal refreshRequested(string id)
  signal resetRequested(string id, string resetId)

  readonly property Item headItem: headHit
  readonly property string rowId: root.row ? root.row.id : ""
  readonly property string kind: root.row ? root.row.kind : "loading"
  readonly property bool reading: root.kind === "reading"
  readonly property bool statusKind: root.kind === "status"
  readonly property bool critical: !!(root.row && root.row.critical)
  readonly property var action: root.row && root.row.action ? root.row.action : null
  readonly property int bigIcon: Math.round(Style.font.iconLarge * Tokens.ROW_ICON_SCALE)
  readonly property color tertiary: Util.alpha(root.foreground, Tokens.TEXT_TERTIARY)

  width: parent ? parent.width : implicitWidth
  implicitHeight: body.implicitHeight
  height: implicitHeight

  function collectFocusTargets() {
    var out = []
    if (!root.row)
      return out
    if (root.row.openable)
      out.push(headHit)
    if (actionButton.visible)
      out.push(actionButton)
    if (root.row.open)
      out = out.concat(detail.collectFocusTargets())
    return out
  }

  // UX-020B: the selected or open row, detail included, sits on the normal
  // fill; a closed head shows the hover fill under the pointer.
  Rectangle {
    anchors.fill: parent
    color: root.row && (root.row.selected || root.row.open) ? Style.normalFill : "transparent"
  }

  Column {
    id: body
    width: parent.width

    Item {
      id: head
      width: parent.width
      height: Math.max(grid.implicitHeight, Style.spacing.popupRowHeight) + Style.space(24)

      Rectangle {
        anchors.fill: parent
        visible: headMouse.containsMouse && !!root.row && root.row.openable && !root.row.open
        color: Style.hoverFill
      }

      Item {
        id: headHit
        objectName: "rowHead"
        anchors.fill: parent

        function focusActivate() {
          if (root.row && root.row.openable)
            root.toggleRequested(root.row.id)
        }

        Keys.onReturnPressed: headHit.focusActivate()
        Keys.onEnterPressed: headHit.focusActivate()
        Keys.onSpacePressed: headHit.focusActivate()

        Accessible.role: Accessible.Button
        Accessible.name: root.row ? root.row.accessibleName : ""
        Accessible.description: root.row ? root.row.tickDescription : ""
        Accessible.expandable: !!(root.row && root.row.openable)
        Accessible.expanded: !!(root.row && root.row.open)
        Accessible.onPressAction: headHit.focusActivate()

        MouseArea {
          id: headMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.row && root.row.openable ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: headHit.focusActivate()
        }

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: Commons.Color.accent
          border.width: Style.spacing.hairline
          visible: headHit.activeFocus
        }
      }

      RowLayout {
        id: grid
        x: Style.spacing.popupPadding
        width: parent.width - Style.spacing.popupPadding * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)

        ProviderIcon {
          Layout.alignment: Qt.AlignVCenter
          providerId: root.rowId
          size: root.bigIcon
          dimmed: !!(root.row && root.row.dimIcon)
          foreground: root.foreground
        }

        ColumnLayout {
          Layout.preferredWidth: Math.round(Style.font.body * Tokens.NAME_COLUMN_EMS)
          Layout.maximumWidth: Math.round(Style.font.body * Tokens.NAME_COLUMN_EMS)
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(4)

          Text {
            id: nameText
            Layout.fillWidth: true
            text: root.row ? root.row.name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Text {
            Layout.fillWidth: true
            text: root.row ? root.row.plan : ""
            color: root.tertiary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: Style.space(4)

          Item {
            Layout.fillWidth: true
            implicitHeight: nameText.implicitHeight

            UsageMeter {
              visible: root.reading
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              percent: root.reading && root.row.primary ? root.row.primary.percent : -1
              critical: root.critical
              tickPercent: root.reading && root.row.primary ? root.row.primary.tickPercent : -1
              foreground: root.foreground
            }

            Row {
              visible: root.statusKind
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                visible: text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.row ? root.row.statusGlyph : ""
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
                textFormat: Text.PlainText
                Accessible.ignored: true
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.row ? root.row.statusWord : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                textFormat: Text.PlainText
                Accessible.ignored: true
              }
            }
          }

          Flow {
            visible: root.reading
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              width: Math.min(implicitWidth, parent.width)
              text: root.row ? root.row.subText : ""
              color: root.tertiary
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              Accessible.ignored: true
            }

            HeaderTag {
              label: root.row ? root.row.subTag : ""
              kind: root.critical ? "urgent" : "accent"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
          }

          Text {
            visible: root.statusKind && text.length > 0
            Layout.fillWidth: true
            text: root.row ? root.row.statusBody : ""
            color: root.tertiary
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            Accessible.ignored: true
          }
        }

        ColumnLayout {
          Layout.preferredWidth: actionButton.visible
              ? actionButton.implicitWidth
              : Math.round(Style.font.title * Tokens.VALUE_COLUMN_EMS)
          Layout.alignment: Qt.AlignVCenter
          spacing: 0

          Row {
            visible: !actionButton.visible
            Layout.alignment: Qt.AlignRight
            spacing: Style.space(4)

            // Any critical window raises the glyph, the main one or not, as
            // on the bar chip.
            Text {
              objectName: "rowAlert"
              visible: !!(root.row && root.row.alert)
              anchors.verticalCenter: parent.verticalCenter
              text: Tokens.GLYPH_ALERT
              color: Commons.Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
              textFormat: Text.PlainText
              Accessible.ignored: true
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.row ? root.row.valueText : ""
              color: root.critical
                  ? Commons.Color.urgent
                  : (root.reading ? root.foreground : root.tertiary)
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              textFormat: Text.PlainText
              Accessible.ignored: true
            }
          }

          Text {
            visible: !actionButton.visible && text.length > 0
            Layout.alignment: Qt.AlignRight
            text: root.row ? root.row.unitText : ""
            color: root.tertiary
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            Accessible.ignored: true
          }

          Button {
            id: actionButton
            visible: root.statusKind && !!root.action
            Layout.alignment: Qt.AlignRight
            text: root.action ? root.action.label : ""
            iconText: root.action && root.action.kind === "view_installation" ? Tokens.GLYPH_EXTERNAL : ""
            bordered: true
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            Accessible.name: text
            function focusActivate() {
              if (root.action)
                root.actionRequested(root.rowId, String(root.action.kind), root.action.target)
            }
            Accessible.onPressAction: focusActivate()
            onClicked: focusActivate()
          }
        }
      }
    }

    RowDetail {
      id: detail
      width: parent.width
      visible: !!(root.row && root.row.open)
      row: root.row
      foreground: root.foreground
      fontFamily: root.fontFamily
      onRefreshRequested: root.refreshRequested(root.rowId)
      onResetRequested: function (resetId) { root.resetRequested(root.rowId, resetId) }
    }

    PanelSeparator {
      objectName: "edgeRule"
      width: parent.width
      visible: !root.last
      foreground: root.foreground
    }
  }
}
