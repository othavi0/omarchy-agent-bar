pragma Singleton
import QtQuick

// Test stand-in for the host palette. Tests assign foreground, background,
// accent and urgent; the surface roles follow them like the host defaults.
// Qt 6.12 exports its own QtQuick `Color` singleton, which wins over this one
// for a bare `Color.` under qmltestrunner; reach this one as `Commons.Color`
// after `import qs.Commons as Commons`, as the host files do.
QtObject {
  id: root

  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"

  readonly property QtObject bar: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color active: root.urgent
  }
  readonly property QtObject popups: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.accent
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.foreground
  }
  readonly property QtObject menu: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color border: root.foreground
    property color scrim: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.5)
  }
}
