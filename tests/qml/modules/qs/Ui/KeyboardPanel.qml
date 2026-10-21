import QtQuick
import qs.Commons
import qs.Commons as Commons

// Test stand-in for the host KeyboardPanel (a layer-shell PanelWindow). It
// keeps the sizing contract plugin code reads: the card is contentWidth by
// contentHeight, and children sit inside padding plus the border.
Item {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property int borderWidth: Math.max(1, Style.space(2))
  property bool centerOnBar: false
  property bool open: false
  property int gap: Style.gapsOut
  property Item focusTarget: null
  property Component content: null
  property bool contentRequested: false
  readonly property Item loadedContent: contentLoader.item
  readonly property real loadedContentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
  readonly property real verticalContentInset: padding * 2 + borderWidth * 2

  default property alias contentItem: contentHolder.children

  function ensureContent() {
    contentRequested = true
  }

  function close() {
    open = false
  }

  width: contentWidth
  height: contentHeight

  onOpenChanged: {
    if (open && focusTarget)
      focusTarget.forceActiveFocus()
  }

  Rectangle {
    id: card
    anchors.fill: parent
    color: Commons.Color.popups.background
    border.color: Commons.Color.popups.border
    border.width: root.borderWidth
    radius: Style.cornerRadius

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.margins: root.padding + root.borderWidth

      Loader {
        id: contentLoader
        anchors.fill: parent
        active: !!root.content && (root.open || root.contentRequested)
        sourceComponent: root.content
      }
    }
  }
}
