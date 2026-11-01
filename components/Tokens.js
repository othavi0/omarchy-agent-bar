.pragma library

var TEXT_SECONDARY = 0.72
var TEXT_TERTIARY = 0.55
var TRACK = 0.12
var DIMMED = 0.45
var LOCKED = 0.55
var URGENT_RULE = 0.55

var GLYPH_ALERT = "\u{F0026}"
var GLYPH_SETTINGS = "\u{F0493}"
var GLYPH_REFRESH = "\u{F0450}"
var GLYPH_BACK = "\u{F0141}"
var GLYPH_UP = "\u{F0143}"
var GLYPH_DOWN = "\u{F0140}"

// Gaveta surfaces. Dark themes lift the group slabs toward the foreground and
// keep the popup background as the floor; light themes keep the slabs on the
// background and sink the floor toward the foreground. Depth always reads
// darker, and no tone mixes toward a fixed black.
var SLAB_LIFT = 0.06
var FLOOR_SINK = 0.2
var RIM = 0.1
var BUTTON_HOT = 0.16
var BUTTON_PRESS = 0.24
var BUTTON_OFF = 0.04
var PRIMARY_REST = 0.16
var PRIMARY_HOT = 0.24
var PRIMARY_PRESS = 0.34
var MIN_TEXT_CONTRAST = 4.5

function mix(base, over, amount) {
  return Qt.tint(base, Qt.rgba(over.r, over.g, over.b, amount))
}

function isLight(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b > 0.5
}

function surfaces(background, foreground) {
  if (isLight(background))
    return { floor: mix(background, foreground, FLOOR_SINK), slab: background }
  return { floor: background, slab: mix(background, foreground, SLAB_LIFT) }
}

function luminance(c) {
  function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

function contrast(a, b) {
  var la = luminance(a)
  var lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// The accent as text on a tonal fill: walk it toward the theme foreground in
// tenths until it reads at MIN_TEXT_CONTRAST, so dark themes lighten it and
// light themes darken it. The foreground itself is the floor.
function readableAccent(accent, fill, foreground) {
  for (var step = 0; step <= 10; step++) {
    var c = mix(accent, foreground, step / 10)
    if (contrast(c, fill) >= MIN_TEXT_CONTRAST)
      return c
  }
  return foreground
}
