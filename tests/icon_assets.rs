//! Guards the UX-049-approved icon assets against silent regression.
//!
//! `TestCase.grabImage()` in `qmltestrunner` was proven unusable under this
//! project's mandated `QT_QPA_PLATFORM=offscreen` runner (it returns a
//! constant blank image for any scene content, verified independently with
//! ImageMagick against a saved grab) — so mark-grade enforcement moves here,
//! to plain byte-level assertions against the shipped files. No new crates:
//! `std::fs::read` plus manual PNG header slicing is enough to distinguish
//! the approved Codex mark from the old app-icon puck deterministically.

use std::fs;

/// UX-049
#[test]
fn icon_assets_are_the_approved_mark_grade_assets() {
    let codex = fs::read("icons/codex.png").expect("read codex.png");

    assert_eq!(
        codex.len(),
        1179,
        "codex.png byte length drifted from the approved mark (old puck was 1315 bytes)"
    );

    const PNG_SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    assert_eq!(
        &codex[0..8],
        &PNG_SIGNATURE,
        "codex.png is missing the PNG signature"
    );

    // IHDR chunk: 4-byte length, "IHDR", then width/height as big-endian
    // u32 at offsets 16/20, bit depth at 24, color type at 25.
    let width = u32::from_be_bytes([codex[16], codex[17], codex[18], codex[19]]);
    let height = u32::from_be_bytes([codex[20], codex[21], codex[22], codex[23]]);
    assert_eq!(
        width, 64,
        "codex.png width drifted from the approved 64x64 mark"
    );
    assert_eq!(
        height, 64,
        "codex.png height drifted from the approved 64x64 mark"
    );

    let color_type = codex[25];
    assert_eq!(
        color_type, 6,
        "codex.png color type drifted from truecolor+alpha (6); the old puck was gray+alpha (4)"
    );

    let antigravity = fs::read("icons/antigravity.png").expect("read antigravity.png");
    assert_eq!(
        &antigravity[0..8],
        &PNG_SIGNATURE,
        "antigravity.png is missing the PNG signature"
    );
    let width = u32::from_be_bytes([
        antigravity[16],
        antigravity[17],
        antigravity[18],
        antigravity[19],
    ]);
    let height = u32::from_be_bytes([
        antigravity[20],
        antigravity[21],
        antigravity[22],
        antigravity[23],
    ]);
    assert_eq!(width, 48, "antigravity.png width drifted from 48x48");
    assert_eq!(height, 48, "antigravity.png height drifted from 48x48");
    assert_eq!(
        antigravity[24], 8,
        "antigravity.png bit depth drifted from 8"
    );
    assert_eq!(
        antigravity[25], 6,
        "antigravity.png color type drifted from truecolor+alpha (6)"
    );

    let grok = fs::read_to_string("icons/grok.svg").expect("read grok.svg");
    let white_fill_count = grok.matches(r#"fill="white""#).count();
    assert_eq!(
        white_fill_count, 2,
        "grok.svg must keep fill=\"white\" on both paths — it is the required \
         tintable-mask convention (spec §10 correction), not a defect to clean up"
    );
}
