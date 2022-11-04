const Tty = @import("Tty.zig");

pub const TTY_COLOR_HIGHLIGHT = Tty.COLOR_YELLOW;
pub const TTY_SELECTION_UNDERLINE = false;

pub const SCORE_GAP_LEADING = -0.005;
pub const SCORE_GAP_TRAILING = -0.005;
pub const SCORE_GAP_INNER = -0.01;
pub const SCORE_MATCH_CONSECUTIVE = 1.0;
pub const SCORE_MATCH_SLASH = 0.9;
pub const SCORE_MATCH_WORD = 0.8;
pub const SCORE_MATCH_CAPITAL = 0.7;
pub const SCORE_MATCH_DOT = 0.6;

/// Time (in ms) to wait for additional bytes of an escape sequence
pub const KEYTIMEOUT = 25;

pub const DEFAULT_TTY = "/dev/tty";
pub const DEFAULT_PROMPT = "> ";
pub const DEFAULT_NUM_LINES = 10;
pub const DEFAULT_WORKERS = 0;
pub const DEFAULT_SHOW_INFO = false;
