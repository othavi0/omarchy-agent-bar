import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

ToolTip {
  property color panelForeground: Commons.Color.tooltip.text
  property color panelBackground: Commons.Color.tooltip.background
  property color panelBorder: Commons.Color.tooltip.border
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall

  delay: 400
}
