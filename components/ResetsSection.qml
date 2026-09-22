import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// UX-070/071: a titled section; ProviderView hides it when there is nothing
// to reset. The header carries the title, the sum of available resets, and a
// claim button that only appears once a claimable entry exists.
Item {
  id: root

  property var rows: []
  property int availableTotal: 0
  property bool anyClaimable: false
  property bool busy: false
  property string outcomeText: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal useResetClicked()

  width: parent ? parent.width : implicitWidth
  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Style.spacing.md

    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "Resets"
        color: Util.alpha(root.foreground, 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        textFormat: Text.PlainText
        Accessible.role: Accessible.Heading
        Accessible.name: "Resets"
      }

      Text {
        visible: root.availableTotal > 0
        text: String(root.availableTotal)
        color: Util.alpha(root.foreground, 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      PanelSeparator {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        foreground: root.foreground
      }

      Button {
        visible: root.anyClaimable
        text: root.busy ? "Using reset…" : "Use reset"
        bordered: true
        focusable: true
        enabled: !root.busy
        foreground: root.foreground
        fontFamily: root.fontFamily
        Accessible.name: "Use reset"
        onClicked: root.useResetClicked()
      }
    }

    Column {
      width: parent.width
      spacing: Style.spacing.lg

      Repeater {
        model: root.rows
        Item {
          id: rowItem
          required property var modelData
          width: parent.width
          implicitHeight: rowCol.implicitHeight
          Accessible.role: Accessible.StaticText
          Accessible.name: modelData.accessibleName

          Column {
            id: rowCol
            width: parent.width
            spacing: Style.spacing.xxs

            Text {
              width: parent.width
              text: rowItem.modelData.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              textFormat: Text.PlainText
              Accessible.ignored: true
            }

            Text {
              width: parent.width
              text: [
                rowItem.modelData.clearsText.length
                    ? "Clears " + rowItem.modelData.clearsText
                    : "",
                rowItem.modelData.countText,
                rowItem.modelData.dateText
              ].filter(function (s) { return s.length > 0 }).join(" · ")
              color: Util.alpha(root.foreground, 0.72)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              Accessible.ignored: true
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.outcomeText.length > 0
      text: root.outcomeText
      color: Util.alpha(root.foreground, 0.72)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      Accessible.name: text
    }
  }
}
