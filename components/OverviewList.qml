import QtQuick
import qs.Commons
import qs.Commons as Commons

// One ProviderRow per visible provider. The Repeater model is the row count,
// not the rows array, so the 30 s clock tick re-binds each row's text without
// rebuilding delegates; focus and scroll position survive the tick.
Column {
  id: root

  property var overview: null
  // The first row meets the rounded border when nothing sits above it.
  property int topRadius: 0
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal selectRequested(string id)
  signal actionRequested(string id, var action)

  readonly property int rowCount: root.overview && root.overview.rows ? root.overview.rows.length : 0
  readonly property int builtCount: rowRepeater.count

  width: parent ? parent.width : implicitWidth

  function collectFocusTargets() {
    var out = []
    for (var i = 0; i < rowRepeater.count; i++) {
      var item = rowRepeater.itemAt(i)
      if (item)
        out = out.concat(item.collectFocusTargets())
    }
    return out
  }

  function rowItem(id) {
    for (var i = 0; i < rowRepeater.count; i++) {
      var item = rowRepeater.itemAt(i)
      if (item && item.rowId === String(id))
        return item
    }
    return null
  }

  function rowHead(id) {
    var item = rowItem(id)
    return item ? item.headItem : null
  }

  Repeater {
    id: rowRepeater
    model: root.rowCount

    ProviderRow {
      required property int index
      width: root.width
      row: root.overview && index < root.rowCount ? root.overview.rows[index] : null
      last: index === root.rowCount - 1
      topRadius: index === 0 ? root.topRadius : 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      onSelectRequested: function (id) { root.selectRequested(id) }
      onActionRequested: function (id, action) { root.actionRequested(id, action) }
    }
  }
}
