/// Strip ANSI CSI/OSC sequences and non-whitespace C0 control characters.
///
/// Keeps TAB/LF/CR. Used at the process and adapter boundary so raw control
/// codes never enter logs, cache, or UI.
pub fn strip_ansi_and_controls(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        if b == 0x1b {
            i += 1;
            if i >= bytes.len() {
                break;
            }
            match bytes[i] {
                b'[' => {
                    // CSI: ESC [ ... final byte @-~
                    i += 1;
                    while i < bytes.len() {
                        let c = bytes[i];
                        i += 1;
                        if (0x40..=0x7e).contains(&c) {
                            break;
                        }
                    }
                }
                b']' => {
                    // OSC: ESC ] ... BEL or ST (ESC \)
                    i += 1;
                    while i < bytes.len() {
                        if bytes[i] == 0x07 {
                            i += 1;
                            break;
                        }
                        if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'\\' {
                            i += 2;
                            break;
                        }
                        i += 1;
                    }
                }
                _ => {
                    // Other ESC-fe sequences: drop ESC and next byte.
                    i += 1;
                }
            }
            continue;
        }
        if b < 0x20 {
            if matches!(b, b'\t' | b'\n' | b'\r') {
                out.push(b as char);
            }
            i += 1;
            continue;
        }
        if b == 0x7f {
            i += 1;
            continue;
        }
        let rest = &input[i..];
        if let Some(ch) = rest.chars().next() {
            out.push(ch);
            i += ch.len_utf8();
        } else {
            i += 1;
        }
    }
    out
}

pub fn redact_process_bytes(bytes: &[u8]) -> String {
    strip_ansi_and_controls(&String::from_utf8_lossy(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_ansi_color_and_controls() {
        let raw = "\u{1b}[31mred\u{1b}[0m\u{07}ok\tline\n";
        let clean = strip_ansi_and_controls(raw);
        assert_eq!(clean, "redok\tline\n");
        assert!(!clean.contains('\u{1b}'));
        assert!(!clean.contains('\u{07}'));
    }

    #[test]
    fn preserves_plain_utf8() {
        assert_eq!(strip_ansi_and_controls("café — ok"), "café — ok");
    }
}
