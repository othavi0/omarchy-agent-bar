import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "CoreView.js" as Core

Item {
  id: root

  property var providers: []
  property string selectedProviderId: ""
  property bool settingsActive: false
  property string displayMetric: "remaining"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property url iconBase: Qt.resolvedUrl("icons/")

  signal providerSelected(string providerId)
  signal settingsClicked()

  readonly property int slotSize: Style.space(32)
  readonly property int iconSize: 16
  readonly property int stackGap: Style.space(8)
  readonly property int spacerMin: Style.space(4)

  readonly property int railWidth: slotSize

  readonly property int minStackHeight: {
    var n = providers && providers.length ? providers.length : 0
    var slots = n + 1
    var gaps = n + 2
    return Style.spacing.popupPadding * 2
        + slots * slotSize
        + gaps * stackGap
        + spacerMin
        + 1
  }

  implicitWidth: railWidth
  width: railWidth
  implicitHeight: minStackHeight

  property var _railFocusItems: []

  function iconUrl(id) {
    var name = Core.iconFileName(id)
    if (!name.length)
      return ""
    return String(root.iconBase) + name
  }

  function collectFocusTargets() {
    var out = []
    for (var i = 0; i < _railFocusItems.length; i++) {
      if (_railFocusItems[i])
        out.push(_railFocusItems[i])
    }
    if (settingsItem)
      out.push(settingsItem)
    return out
  }

  function registerRailItem(item) {
    var next = _railFocusItems.slice()
    if (next.indexOf(item) < 0)
      next.push(item)
    _railFocusItems = next
  }

  function unregisterRailItem(item) {
    var next = []
    for (var i = 0; i < _railFocusItems.length; i++) {
      if (_railFocusItems[i] !== item)
        next.push(_railFocusItems[i])
    }
    _railFocusItems = next
  }

  ColumnLayout {
    id: stack
    anchors.fill: parent
    anchors.topMargin: Style.spacing.popupPadding
    anchors.bottomMargin: Style.spacing.popupPadding
    spacing: root.stackGap

    Repeater {
      model: root.providers

      Item {
        id: railItem
        required property int index
        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: root.slotSize
        Layout.maximumHeight: root.slotSize
        Layout.alignment: Qt.AlignHCenter
        activeFocusOnTab: true
        enabled: true
        clip: true

        readonly property var entry: {
          if (root.providers && index >= 0 && index < root.providers.length)
            return root.providers[index]
          return modelData
        }
        readonly property string pid: entry && entry.id ? String(entry.id) : ""
        readonly property bool selected: Core.railProviderSelected(
          root.settingsActive ? "settings" : "usage",
          railItem.pid,
          String(root.selectedProviderId || "").trim()
        )
        readonly property bool dimmed: entry ? Core.chipDimmed(entry) : true
        readonly property string label: entry
            ? Core.railTooltipText(entry, root.displayMetric)
            : Core.providerDisplayName(railItem.pid)
        readonly property string cue: entry ? Core.chipStateCue(entry) : ""

        function focusActivate() {
          root.providerSelected(railItem.pid)
        }

        Component.onCompleted: root.registerRailItem(railItem)
        Component.onDestruction: root.unregisterRailItem(railItem)

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: railItem.selected
              ? Style.selectedFill
              : "transparent"
          border.width: railItem.selected ? Style.selectedBorderWidth : 0
          border.color: railItem.selected
              ? Style.selectedBorderColor
              : "transparent"
        }

        Image {
          anchors.centerIn: parent
          source: root.iconUrl(railItem.pid)
          width: root.iconSize
          height: root.iconSize
          sourceSize.width: root.iconSize
          sourceSize.height: root.iconSize
          fillMode: Image.PreserveAspectFit
          opacity: railItem.dimmed ? 0.4 : (railItem.selected ? 1.0 : 0.65)
        }

        Text {
          visible: railItem.cue.length > 0
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: Style.spacing.xxs
          anchors.rightMargin: Style.spacing.xs
          text: railItem.cue
          color: entry && Core.chipSeverityUrgent(entry) ? Color.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          textFormat: Text.PlainText
          Accessible.ignored: true
        }

        MouseArea {
          id: railMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.providerSelected(railItem.pid)
        }

        Keys.onReturnPressed: railItem.focusActivate()
        Keys.onEnterPressed: railItem.focusActivate()
        Keys.onSpacePressed: railItem.focusActivate()

        Accessible.name: railItem.label
        Accessible.role: Accessible.Button
        Accessible.onPressAction: railItem.focusActivate()

        PanelToolTip {
          visible: railMouse.containsMouse
          text: railItem.label
          fontFamily: root.fontFamily
        }
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: root.spacerMin
      Layout.preferredWidth: 1
    }

    PanelSeparator {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(6)
      Layout.rightMargin: Style.space(6)
      foreground: root.foreground
    }

    Item {
      id: settingsItem
      Layout.fillWidth: true
      Layout.preferredHeight: root.slotSize
      Layout.maximumHeight: root.slotSize
      Layout.alignment: Qt.AlignHCenter
      activeFocusOnTab: true
      clip: true

      function focusActivate() {
        root.settingsClicked()
      }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: root.settingsActive
            ? Style.selectedFill
            : ((settingsItem.activeFocus || settingsMouse.containsMouse)
              ? Style.hoverFill
              : "transparent")
        border.width: settingsItem.activeFocus ? 1 : 0
        border.color: Color.accent
      }

      Text {
        anchors.centerIn: parent
        text: "󰒓"
        color: root.foreground
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      MouseArea {
        id: settingsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.settingsClicked()
      }

      Keys.onReturnPressed: settingsItem.focusActivate()
      Keys.onEnterPressed: settingsItem.focusActivate()
      Keys.onSpacePressed: settingsItem.focusActivate()

      Accessible.name: "Settings"
      Accessible.role: Accessible.Button
      Accessible.onPressAction: settingsItem.focusActivate()

      PanelToolTip {
        visible: settingsMouse.containsMouse
        text: "Settings"
        fontFamily: root.fontFamily
      }
    }
  }
}
