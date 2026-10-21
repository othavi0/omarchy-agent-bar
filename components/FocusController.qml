import QtQuick
import "../CoreScroll.js" as Core

Item {
  id: root

  property var targets: []
  property int index: -1
  property var flickable: null
  property int lineHeight: 18
  property bool focusBlocked: false

  readonly property int count: targets && targets.length ? targets.length : 0
  readonly property var current: {
    if (index < 0 || index >= count)
      return null
    return targets[index]
  }

  function isTargetLive(item) {
    if (!item)
      return false
    if (item.visible === false)
      return false
    if (item.enabled === false)
      return false
    if (item.opacity === 0)
      return false
    return true
  }

  function liveTargets() {
    var out = []
    if (!targets)
      return out
    for (var i = 0; i < targets.length; i++) {
      if (isTargetLive(targets[i]))
        out.push(targets[i])
    }
    return out
  }

  // Every target leaves Qt's own Tab chain: an item that keeps
  // activeFocusOnTab moves focus itself on Tab, the catcher never sees the
  // key, and index goes stale. A spin box takes focus on its text input
  // (contentItem), so that item leaves the chain too.
  function leaveTabChain(item) {
    if (!item)
      return
    if (item.activeFocusOnTab)
      item.activeFocusOnTab = false
    if (item.contentItem && item.contentItem.activeFocusOnTab)
      item.contentItem.activeFocusOnTab = false
  }

  function setTargets(list) {
    var previousCurrent = current
    targets = list || []
    for (var t = 0; t < targets.length; t++)
      leaveTabChain(targets[t])
    if (count === 0) {
      index = -1
      return
    }

    var preservedIndex = -1
    if (previousCurrent) {
      for (var i = 0; i < count; i++) {
        if (targets[i] === previousCurrent) {
          preservedIndex = i
          break
        }
      }
    }
    if (preservedIndex >= 0)
      index = preservedIndex
    else if (index < 0 || index >= count)
      index = 0
    if (!focusBlocked)
      focusCurrent()
  }

  function move(direction) {
    var live = liveTargets()
    if (!live.length) {
      index = -1
      return null
    }
    var curLive = -1
    if (current) {
      for (var i = 0; i < live.length; i++) {
        if (live[i] === current) {
          curLive = i
          break
        }
      }
    }
    var nextLive = Core.focusNextIndex(curLive, direction, live.length)
    var item = live[nextLive]
    for (var j = 0; j < targets.length; j++) {
      if (targets[j] === item) {
        index = j
        break
      }
    }
    focusCurrent()
    return item
  }

  function focusItem(item) {
    if (!item || !targets)
      return false
    for (var i = 0; i < targets.length; i++) {
      if (targets[i] === item) {
        index = i
        focusCurrent()
        return true
      }
    }
    return false
  }

  function focusCurrent() {
    var item = current
    if (!item)
      return
    if (typeof item.forceActiveFocus === "function")
      item.forceActiveFocus()
    ensureVisible(item)
  }

  function activate() {
    var item = current
    if (!item || !isTargetLive(item))
      return false
    if (typeof item.focusActivate === "function") {
      item.focusActivate()
      return true
    }
    if (typeof item.clicked === "function") {
    }
    if (item.Accessible && typeof item.Accessible.pressAction === "function") {
      item.Accessible.pressAction()
      return true
    }
    if (typeof item.pressAction === "function") {
      item.pressAction()
      return true
    }
    return false
  }

  function scrolledBy(item) {
    for (var cur = item; cur; cur = cur.parent) {
      if (cur === flickable.contentItem)
        return true
    }
    return false
  }

  // Pinned targets (banners, band, footers) sit outside the Flickable; only
  // a target inside the scrolled content may move it.
  function ensureVisible(item) {
    if (!flickable || !item || !scrolledBy(item))
      return
    var y = 0
    var h = item.height || 0
    try {
      if (flickable.contentItem && item.mapToItem) {
        var p = item.mapToItem(flickable.contentItem, 0, 0)
        y = p.y
      } else if (typeof item.y === "number") {
        y = item.y
      }
    } catch (e) {
      return
    }
    flickable.contentY = Core.contentYForItem(
      flickable.contentY,
      flickable.height,
      flickable.contentHeight,
      y,
      h
    )
  }

  function scrollPage(direction) {
    if (!flickable)
      return
    flickable.contentY = Core.applyPageScroll(
      flickable.contentY,
      direction,
      flickable.height,
      flickable.contentHeight,
      root.lineHeight
    )
  }

  function scrollHome() {
    if (!flickable)
      return
    flickable.contentY = Core.scrollHomeY()
  }

  function scrollEnd() {
    if (!flickable)
      return
    flickable.contentY = Core.scrollEndY(flickable.contentHeight, flickable.height)
  }

  function clampScroll() {
    if (!flickable)
      return
    flickable.contentY = Core.clampContentY(
      flickable.contentY,
      flickable.contentHeight,
      flickable.height
    )
  }
}
