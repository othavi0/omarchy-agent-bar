import QtQuick

Item {
  property string label: ""
  property string description: ""
  property bool checked: false
  property color foreground: "#e6e6e6"
  property string fontFamily: ""
  signal clicked()
}
