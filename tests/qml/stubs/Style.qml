pragma Singleton
import QtQuick

QtObject {
  property int cornerRadius: 0
  property var font: ({ family: "sans", body: 14, subtitle: 15, caption: 12 })
  property var spacing: ({ huge: 24 })
  function space(px) { return px }
  function selectedFillFor(foreground, accent) { return Qt.rgba(0, 0, 0, 0) }
}
