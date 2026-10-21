import QtQuick

// Test stand-in for the host PanelKeyCatcher. Tests emit the signals
// directly instead of synthesizing key events.
Item {
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
}
