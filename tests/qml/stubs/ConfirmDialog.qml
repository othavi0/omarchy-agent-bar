import QtQuick

Item {
  property bool opened: false
  property string title: ""
  property string message: ""
  property string cancelText: ""
  property string confirmText: ""
  property bool destructive: false
  property color foreground: "#e6e6e6"
  property string fontFamily: ""
  signal canceled()
  signal confirmed()
  visible: opened
}
