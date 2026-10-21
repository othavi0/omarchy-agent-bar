import QtQuick

// Test stand-in for the host PanelKeyCatcher, with the host key handling, so
// tests can press real keys. The catcher only sees a key that the focused
// item did not consume.
Item {
  id: root

  property bool blocked: false
  property bool reorderable: false

  signal moveRequested(int dx, int dy)
  signal reorderRequested(int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text, int modifiers)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function (event) {
    if (blocked)
      return
    if (event.key === Qt.Key_Escape) {
      closeRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
    if (reorderable && (event.modifiers & Qt.ControlModifier)) {
      var up = event.key === Qt.Key_Up || event.key === Qt.Key_K
      var down = event.key === Qt.Key_Down || event.key === Qt.Key_J
      if (up || down) {
        reorderRequested(down ? 1 : -1); event.accepted = true; return
      }
    }
    if (event.key === Qt.Key_Down || event.text === "j") {
      moveRequested(0, 1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Up || event.text === "k") {
      moveRequested(0, -1); event.accepted = true; return
    }
    var right = event.key === Qt.Key_Right || event.text === "l"
    var left = event.key === Qt.Key_Left || event.text === "h"
    if (LayoutMirroring.enabled ? left : right) {
      moveRequested(1, 0); event.accepted = true; return
    }
    if (LayoutMirroring.enabled ? right : left) {
      moveRequested(-1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      returnRequested()
      activateRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Space) {
      activateRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Delete || event.text === "x" || event.text === "X") {
      deleteRequested(); event.accepted = true; return
    }
    if (event.text && event.text.length === 1)
      textKey(event.text, event.modifiers)
  }
}
