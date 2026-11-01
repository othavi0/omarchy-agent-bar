.pragma library

function focusNextIndex(current, direction, count) {
  var n = Math.floor(Number(count))
  if (!isFinite(n) || n <= 0)
    return -1
  var cur = Math.floor(Number(current))
  var dir = direction < 0 ? -1 : 1
  if (!isFinite(cur) || cur < 0 || cur >= n)
    return dir > 0 ? 0 : n - 1
  return (cur + dir + n * 100) % n
}

function maxContentY(contentHeight, viewportHeight) {
  var ch = Number(contentHeight)
  var vh = Number(viewportHeight)
  if (!isFinite(ch) || !isFinite(vh))
    return 0
  return Math.max(0, ch - vh)
}

function flickableInteractive(contentHeight, viewportHeight) {
  return maxContentY(contentHeight, viewportHeight) > 0
}

function fittedPopupContentHeight(bodyHeight, maxCap) {
  var body = Number(bodyHeight)
  var maxH = Number(maxCap)
  if (!isFinite(body) || body < 0)
    body = 0
  if (!isFinite(maxH) || maxH <= 0)
    maxH = body
  return Math.min(maxH, body)
}

function clampContentY(y, contentHeight, viewportHeight) {
  var max = maxContentY(contentHeight, viewportHeight)
  var n = Number(y)
  if (!isFinite(n) || n < 0)
    return 0
  if (n > max)
    return max
  return n
}

function pageScrollDelta(viewportHeight, lineHeight) {
  var line = Math.max(1, Number(lineHeight) || 1)
  var view = Math.max(line, Number(viewportHeight) || line)
  return Math.max(line, view - line)
}

function applyPageScroll(contentY, direction, viewportHeight, contentHeight, lineHeight) {
  var delta = pageScrollDelta(viewportHeight, lineHeight)
  var next = Number(contentY) + (direction > 0 ? delta : -delta)
  return clampContentY(next, contentHeight, viewportHeight)
}

function scrollHomeY() {
  return 0
}

function scrollEndY(contentHeight, viewportHeight) {
  return maxContentY(contentHeight, viewportHeight)
}

function contentYForItem(contentY, viewportHeight, contentHeight, itemY, itemHeight) {
  var y = Number(itemY)
  var h = Math.max(0, Number(itemHeight))
  var vh = Math.max(0, Number(viewportHeight))
  var cur = Number(contentY)
  if (!isFinite(y) || !isFinite(vh))
    return clampContentY(cur, contentHeight, viewportHeight)
  if (y < cur)
    return clampContentY(y, contentHeight, viewportHeight)
  if (y + h > cur + vh)
    return clampContentY(y + h - vh, contentHeight, viewportHeight)
  return clampContentY(cur, contentHeight, viewportHeight)
}
