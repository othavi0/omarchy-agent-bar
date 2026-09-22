import QtQuick

Item {
  property string text: ""
  property bool selected: false
  property bool bordered: false
  property bool focusable: false
  property color foreground: "#e6e6e6"
  property string fontFamily: ""
  signal clicked()
  implicitWidth: 80
  implicitHeight: 24
}
