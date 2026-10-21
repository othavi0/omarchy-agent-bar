.pragma library

var TEXT_SECONDARY = 0.72
var TEXT_TERTIARY = 0.55
var TRACK = 0.12
var DIMMED = 0.45
var LOCKED = 0.55
var THIN_FILL = 0.6
var URGENT_RULE = 0.55

var ROW_ICON_SCALE = 1.2
var NAME_COLUMN_EMS = 8.5
var VALUE_COLUMN_EMS = 3.6
var PACE_MIN_ELAPSED = 0.1

var GLYPH_ALERT = "\u{F0026}"
var GLYPH_CLOCK = "\u{F0954}"
var GLYPH_CHECK = "\u{F012C}"
var GLYPH_REFRESH = "\u{F0450}"
var GLYPH_SETTINGS = "\u{F0493}"
var GLYPH_BACK = "\u{F0141}"
var GLYPH_UP = "\u{F0143}"
var GLYPH_DOWN = "\u{F0140}"
var GLYPH_EXTERNAL = "\u{F03CC}"
var GLYPH_PLUG = "\u{F06A5}"
var GLYPH_USER = "\u{F0004}"
var GLYPH_WIFI_OFF = "\u{F05AA}"

// Gaveta surfaces. Dark themes lift the row slabs toward the foreground and
// keep the popup background as the floor; light themes keep the slabs on the
// background and sink the well and the floor toward the foreground. Depth
// always reads darker, and no tone mixes toward a fixed black.
var SLAB_LIFT = 0.06
var WELL_LIFT = 0.015
var WELL_SINK = 0.07
var FLOOR_SINK = 0.2
var RIM = 0.1
var DRAWER_RULE = 0.08
var HEAD_OPEN = 0.15
var HEAD_SELECTED = 0.07
var BUTTON_REST = 0.1
var BUTTON_HOT = 0.16
var BUTTON_OFF = 0.04
var PRIMARY_REST = 0.24
var PRIMARY_HOT = 0.34
var LABEL_COLUMN_EMS = 8.5
var CHEVRON_OPEN_DEGREES = 90

var GLYPH_CHEVRON = "\u{F0142}"
var GLYPH_BOLT = "\u{F140B}"

function mix(base, over, amount) {
  return Qt.tint(base, Qt.rgba(over.r, over.g, over.b, amount))
}

function isLight(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b > 0.5
}

function surfaces(background, foreground) {
  if (isLight(background)) {
    return {
      floor: mix(background, foreground, FLOOR_SINK),
      slab: background,
      well: mix(background, foreground, WELL_SINK)
    }
  }
  return {
    floor: background,
    slab: mix(background, foreground, SLAB_LIFT),
    well: mix(background, foreground, WELL_LIFT)
  }
}
