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

  signal actionRequested(string id, var action)

  readonly property int rowCount: root.overview && root.overview.rows ? root.overview.rows.length : 0
  readonly property int contentWidth: Math.max(0, root.width - Style.spacing.popupPadding * 2)

  // Window columns shared by every group, so the bars line up across the
  // popup. The label column fits the widest label, at least the widest
  // Antigravity family label and at most a third of the content; the reset
  // column fits the widest reset text.
  readonly property var columns: {
    var labelWidth = labelMetrics.advanceWidth("Claude/GPT · 7d")
    var resetWidth = 0
    for (var r = 0; r < root.rowCount; r++) {
      var windows = root.overview.rows[r].windows || []
      for (var w = 0; w < windows.length; w++) {
        labelWidth = Math.max(labelWidth, labelMetrics.advanceWidth(windows[w].label))
        resetWidth = Math.max(resetWidth, resetMetrics.advanceWidth(windows[w].resetText))
      }
    }
    return {
      label: Math.ceil(Math.min(labelWidth, root.contentWidth / 3)),
      percent: Math.ceil(percentMetrics.advanceWidth("100%")),
      reset: Math.ceil(resetWidth)
    }
  }

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

  FontMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  FontMetrics {
    id: percentMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.weight: Font.Medium
    font.features: ({ "tnum": 1 })
  }

  FontMetrics {
    id: resetMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.features: ({ "tnum": 1 })
  }

  Repeater {
    id: rowRepeater
    model: root.rowCount

    ProviderRow {
      required property int index
      width: root.width
      row: root.overview && index < root.rowCount ? root.overview.rows[index] : null
      columns: root.columns
      last: index === root.rowCount - 1
      topRadius: index === 0 ? root.topRadius : 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      onActionRequested: function (id, action) { root.actionRequested(id, action) }
    }
  }
}
