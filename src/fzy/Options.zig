const config = @import("config.zig");

/// Run the match algorithm NUM times
benchmark: u32 = 0,
/// Output the sorted matches of QUERY
filter: ?[]const u8 = null,
/// Use QUERY as the initial search string
init_search: ?[]const u8 = null,
/// Show the scores of each match
show_scores: bool = false,
scrolloff: usize = 1,
/// Specify file to use as TTY device (default /dev/tty)
tty_filename: []const u8 = config.DEFAULT_TTY,
/// Specify how many lines of results to show (default 10)
num_lines: usize = config.DEFAULT_NUM_LINES,
/// Input prompt (default '> ')
prompt: []const u8 = config.DEFAULT_PROMPT,
/// Use NUM workers for searching. (default is # of CPUs)
workers: usize = config.DEFAULT_WORKERS,
/// Read input delimited by ASCII NUL characters
input_delimiter: u8 = '\n',
/// Show selection info line
show_info: bool = config.DEFAULT_SHOW_INFO,
/// Read choices from FILE instead of stdin
input_file: []const u8,
/// Sort matches or not
sort: bool = true,
