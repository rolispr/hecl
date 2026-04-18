//! hecl_gterm: C API bridge to libghostty-vt for hecl.
//!
//! Exposes a flat C ABI that ECL/CFFI can load. No Emacs dependency.

const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

const Terminal = ghostty_vt.Terminal;
const TerminalStream = ghostty_vt.TerminalStream;
const Style = ghostty_vt.Style;
const color = ghostty_vt.color;
const page_mod = ghostty_vt.page;
const Allocator = std.mem.Allocator;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator: Allocator = gpa.allocator();

const GtermInstance = struct {
    terminal: Terminal,
    stream: TerminalStream,
    cols: u16,
    rows: u16,

    pub fn init(cols: u16, rows: u16) !*GtermInstance {
        const self = try allocator.create(GtermInstance);
        self.cols = cols;
        self.rows = rows;
        self.terminal = try Terminal.init(allocator, .{
            .cols = cols,
            .rows = rows,
            .default_modes = .{ .linefeed = true },
        });
        self.stream = self.terminal.vtStream();
        return self;
    }

    pub fn deinit(self: *GtermInstance) void {
        self.stream.deinit();
        self.terminal.deinit(allocator);
        allocator.destroy(self);
    }
};

// ── C API ────────────────────────────────────────────────────────────

export fn hecl_gterm_new(cols: c_int, rows: c_int) ?*GtermInstance {
    return GtermInstance.init(@intCast(cols), @intCast(rows)) catch null;
}

export fn hecl_gterm_free(term: ?*GtermInstance) void {
    if (term) |t| t.deinit();
}

export fn hecl_gterm_feed(term: ?*GtermInstance, data: [*]const u8, len: c_int) void {
    if (term) |t| t.stream.nextSlice(data[0..@intCast(len)]);
}

export fn hecl_gterm_resize(term: ?*GtermInstance, cols: c_int, rows: c_int) void {
    if (term) |t| {
        t.terminal.resize(allocator, @intCast(cols), @intCast(rows)) catch {};
        t.cols = @intCast(cols);
        t.rows = @intCast(rows);
    }
}

export fn hecl_gterm_cursor_row(term: ?*GtermInstance) c_int {
    if (term) |t| return @intCast(t.terminal.screens.active.cursor.y);
    return 0;
}

export fn hecl_gterm_cursor_col(term: ?*GtermInstance) c_int {
    if (term) |t| return @intCast(t.terminal.screens.active.cursor.x);
    return 0;
}

export fn hecl_gterm_cols(term: ?*GtermInstance) c_int {
    if (term) |t| return @intCast(t.cols);
    return 0;
}

export fn hecl_gterm_rows(term: ?*GtermInstance) c_int {
    if (term) |t| return @intCast(t.rows);
    return 0;
}

/// Cell style output struct — flat for easy CFFI access.
const CellStyle = extern struct {
    fg_r: u8 = 0,
    fg_g: u8 = 0,
    fg_b: u8 = 0,
    fg_set: u8 = 0,
    bg_r: u8 = 0,
    bg_g: u8 = 0,
    bg_b: u8 = 0,
    bg_set: u8 = 0,
    bold: u8 = 0,
    italic: u8 = 0,
    underline: u8 = 0,
    strikethrough: u8 = 0,
    inverse: u8 = 0,
};

/// Get cell character at (row, col). Returns Unicode codepoint.
export fn hecl_gterm_cell_char(term: ?*GtermInstance, row: c_int, col: c_int) u32 {
    const t = term orelse return 0;
    const screen = t.terminal.screens.active;
    const pin = screen.pages.pin(.{ .viewport = .{
        .x = @intCast(col),
        .y = @intCast(row),
    } }) orelse return 0;
    const p = pin.node.data;
    const cells = p.getCells(p.getRow(@intCast(row)));
    if (@as(usize, @intCast(col)) >= cells.len) return 0;
    return cells[@intCast(col)].codepoint();
}

/// Get cell style at (row, col).
export fn hecl_gterm_cell_style(term: ?*GtermInstance, row: c_int, col: c_int, out: *CellStyle) void {
    const t = term orelse return;
    const screen = t.terminal.screens.active;
    const pin = screen.pages.pin(.{ .viewport = .{
        .x = @intCast(col),
        .y = @intCast(row),
    } }) orelse return;
    const p = pin.node.data;
    const cells = p.getCells(p.getRow(@intCast(row)));
    if (@as(usize, @intCast(col)) >= cells.len) return;
    const cell = cells[@intCast(col)];
    const style = p.styles.get(p.memory, cell.style_id);
    const palette = &t.terminal.colors.palette.current;

    switch (style.fg_color) {
        .none => {
            out.fg_set = 0;
        },
        .palette => |idx| {
            const rgb = palette[idx];
            out.fg_r = rgb.r;
            out.fg_g = rgb.g;
            out.fg_b = rgb.b;
            out.fg_set = 1;
        },
        .rgb => |rgb| {
            out.fg_r = rgb.r;
            out.fg_g = rgb.g;
            out.fg_b = rgb.b;
            out.fg_set = 1;
        },
    }

    switch (style.bg_color) {
        .none => {
            out.bg_set = 0;
        },
        .palette => |idx| {
            const rgb = palette[idx];
            out.bg_r = rgb.r;
            out.bg_g = rgb.g;
            out.bg_b = rgb.b;
            out.bg_set = 1;
        },
        .rgb => |rgb| {
            out.bg_r = rgb.r;
            out.bg_g = rgb.g;
            out.bg_b = rgb.b;
            out.bg_set = 1;
        },
    }

    out.bold = @intFromBool(style.flags.bold);
    out.italic = @intFromBool(style.flags.italic);
    out.underline = if (style.flags.underline != .none) 1 else 0;
    out.strikethrough = @intFromBool(style.flags.strikethrough);
    out.inverse = @intFromBool(style.flags.inverse);
}

/// Render the entire screen as UTF-8 into the provided buffer.
/// Each row is separated by \n. Trailing spaces per row are trimmed.
/// Returns the number of bytes written, or -1 if buffer too small.
export fn hecl_gterm_render_text(term: ?*GtermInstance, out: [*]u8, out_len: c_int) c_int {
    const t = term orelse return 0;
    const screen = t.terminal.screens.active;
    var pos: usize = 0;
    const max: usize = @intCast(out_len);

    var row: u16 = 0;
    while (row < t.rows) : (row += 1) {
        if (row > 0) {
            if (pos >= max) return -1;
            out[pos] = '\n';
            pos += 1;
        }

        // Find last non-space column
        var last_nonspace: usize = 0;
        var col: u16 = 0;
        while (col < t.cols) : (col += 1) {
            const pin = screen.pages.pin(.{ .viewport = .{
                .x = col,
                .y = row,
            } }) orelse continue;
            const p = pin.node.data;
            const cells = p.getCells(p.getRow(row));
            if (col < cells.len) {
                const cp = cells[col].codepoint();
                if (cp != 0 and cp != 32) {
                    last_nonspace = col + 1;
                }
            }
        }

        // Write chars up to last non-space
        col = 0;
        while (col < last_nonspace) : (col += 1) {
            const pin = screen.pages.pin(.{ .viewport = .{
                .x = col,
                .y = row,
            } }) orelse {
                if (pos >= max) return -1;
                out[pos] = ' ';
                pos += 1;
                continue;
            };
            const p = pin.node.data;
            const cells = p.getCells(p.getRow(row));
            var cp: u21 = 0;
            if (col < cells.len) {
                cp = cells[col].codepoint();
            }
            if (cp == 0) cp = ' ';

            // UTF-8 encode
            if (cp < 0x80) {
                if (pos >= max) return -1;
                out[pos] = @intCast(cp);
                pos += 1;
            } else if (cp < 0x800) {
                if (pos + 1 >= max) return -1;
                out[pos] = @intCast(0xC0 | (cp >> 6));
                out[pos + 1] = @intCast(0x80 | (cp & 0x3F));
                pos += 2;
            } else if (cp < 0x10000) {
                if (pos + 2 >= max) return -1;
                out[pos] = @intCast(0xE0 | (cp >> 12));
                out[pos + 1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
                out[pos + 2] = @intCast(0x80 | (cp & 0x3F));
                pos += 3;
            } else {
                if (pos + 3 >= max) return -1;
                out[pos] = @intCast(0xF0 | (cp >> 18));
                out[pos + 1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
                out[pos + 2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
                out[pos + 3] = @intCast(0x80 | (cp & 0x3F));
                pos += 4;
            }
        }
    }

    return @intCast(pos);
}

/// Render the screen as HTML with color spans.
/// Each cell gets a <span> with fg/bg color styles.
/// Returns bytes written, or -1 if buffer too small.
export fn hecl_gterm_render_cells16(term: ?*GtermInstance, out: [*]u8, out_len: c_int) c_int {
    const t = term orelse return 0;
    const screen = t.terminal.screens.active;
    const palette = &t.terminal.colors.palette.current;
    var pos: usize = 0;
    const max: usize = @intCast(out_len);
    const cell_size: usize = 16;

    var row: u16 = 0;
    while (row < t.rows) : (row += 1) {
        const pin = screen.pages.pin(.{ .viewport = .{
            .x = 0,
            .y = row,
        } }) orelse continue;

        const page = pin.node.data;
        const page_row = page.getRow(pin.y);
        const page_cells = page.getCells(page_row);

        // Find last non-empty col
        var last_col: u16 = 0;
        for (0..@min(t.cols, @as(u16, @intCast(page_cells.len)))) |c| {
            const cp = page_cells[c].codepoint();
            if (cp != 0 and cp != 32) last_col = @intCast(c + 1);
        }

        var col: u16 = 0;
        while (col < last_col) : (col += 1) {
            if (col >= page_cells.len) continue;
            const cell = page_cells[col];
            var cp = cell.codepoint();
            if (cp == 0) cp = 32; // treat null as space

            if (pos + cell_size > max) return -1;

            // Row, Col (u16 LE)
            std.mem.writeInt(u16, out[pos..][0..2], row, .little);
            std.mem.writeInt(u16, out[pos + 2 ..][0..2], col, .little);
            // Codepoint (u32 LE)
            std.mem.writeInt(u32, out[pos + 4 ..][0..4], cp, .little);

            // Defaults
            var fg_r: u8 = 205;
            var fg_g: u8 = 214;
            var fg_b: u8 = 244;
            var bg_r: u8 = 0;
            var bg_g: u8 = 0;
            var bg_b: u8 = 0;
            var bold_val: u8 = 0;
            var has_bg: u8 = 0;

            if (cell.style_id != 0 and cell.style_id < page.styles.layout.cap) {
                const items = page.styles.items.ptr(page.memory);
                const item = &items[cell.style_id];
                // Check ref count > 0 before accessing (avoid assertion)
                if (item.meta.ref > 0) {
                    const s: *const Style = @ptrCast(&item.value);
                    var fg_color = s.fg_color;
                    var bg_color = s.bg_color;
                    if (s.flags.inverse) {
                    const tmp = fg_color;
                    fg_color = bg_color;
                    bg_color = tmp;
                }
                switch (fg_color) {
                    .none => {},
                    .palette => |idx| {
                        const rgb = palette[idx];
                        fg_r = rgb.r;
                        fg_g = rgb.g;
                        fg_b = rgb.b;
                    },
                    .rgb => |rgb| {
                        fg_r = rgb.r;
                        fg_g = rgb.g;
                        fg_b = rgb.b;
                    },
                }
                switch (bg_color) {
                    .none => {},
                    .palette => |idx| {
                        const rgb = palette[idx];
                        bg_r = rgb.r;
                        bg_g = rgb.g;
                        bg_b = rgb.b;
                        has_bg = 1;
                    },
                    .rgb => |rgb| {
                        bg_r = rgb.r;
                        bg_g = rgb.g;
                        bg_b = rgb.b;
                        has_bg = 1;
                    },
                }
                    bold_val = @intFromBool(s.flags.bold);
                }
            }

            out[pos + 8] = fg_r;
            out[pos + 9] = fg_g;
            out[pos + 10] = fg_b;
            out[pos + 11] = bg_r;
            out[pos + 12] = bg_g;
            out[pos + 13] = bg_b;
            out[pos + 14] = bold_val;
            out[pos + 15] = has_bg;

            pos += cell_size;
        }
    }

    return @intCast(pos / cell_size);
}

export fn hecl_gterm_scroll(term: ?*GtermInstance, delta: c_int) void {
    if (term) |t| {
        t.terminal.scrollViewport(.{ .delta = @intCast(delta) });
    }
}

export fn hecl_gterm_mode(term: ?*GtermInstance, mode: c_int) c_int {
    if (term) |t| {
        return @intFromBool(t.terminal.modes.get(@enumFromInt(@as(u16, @intCast(mode)))));
    }
    return 0;
}
