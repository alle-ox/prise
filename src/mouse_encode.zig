const std = @import("std");
const ghostty = @import("ghostty-vt");
const key_parse = @import("key_parse.zig");

pub fn encode(
    writer: anytype,
    event: key_parse.MouseEvent,
    terminal: *const ghostty.Terminal,
) !void {
    const flags = terminal.flags;

    // Check if mouse reporting is enabled
    if (flags.mouse_event == .none) return;

    // Filter based on event type and enabled mode
    const report = switch (flags.mouse_event) {
        .x10 => event.type == .press, // X10 only reports press
        .normal => event.type == .press or event.type == .release,
        .button => event.type == .press or event.type == .release or event.type == .drag,
        .any => true, // Report everything including motion
        .none => false,
    };

    if (!report) return;

    // SGR encoding (1006)
    if (flags.mouse_format == .sgr or flags.mouse_format == .sgr_pixels) {
        try encodeSGR(writer, event);
        return;
    }

    // Fallback to X10/Normal (max 223 coords)
    // If coordinates are too large for X10, we skip reporting
    if (event.col > 222 or event.row > 222) return;

    try encodeX10(writer, event);
}

fn encodeSGR(writer: anytype, event: key_parse.MouseEvent) !void {
    var cb: u8 = 0;

    // Button mapping
    switch (event.button) {
        .left => cb = 0,
        .middle => cb = 1,
        .right => cb = 2,
        .wheel_up => cb = 64,
        .wheel_down => cb = 65,
        .wheel_left => cb = 66,
        .wheel_right => cb = 67,
        .none => if (event.type == .motion) {
            cb = 35;
        } else {
            cb = 0;
        },
    }

    // Modifiers
    if (event.mods.shift) cb |= 4;
    if (event.mods.alt) cb |= 8;
    if (event.mods.ctrl) cb |= 16;

    // Drag/Motion
    if (event.type == .drag) cb |= 32;
    if (event.type == .motion) cb |= 32;

    // Format: CSI < Cb ; Cx ; Cy M (or m for release)
    const char: u8 = if (event.type == .release) 'm' else 'M';

    try writer.print("\x1b[<{};{};{}{c}", .{ cb, event.col + 1, event.row + 1, char });
}

fn encodeX10(writer: anytype, event: key_parse.MouseEvent) !void {
    var cb: u8 = 0;
    switch (event.button) {
        .left => cb = 0,
        .middle => cb = 1,
        .right => cb = 2,
        .wheel_up => cb = 64,
        .wheel_down => cb = 65,
        .wheel_left => cb = 66,
        .wheel_right => cb = 67,
        .none => cb = 0,
    }

    if (event.type == .release) cb = 3;
    if (event.type == .drag) cb += 32;
    if (event.type == .motion) cb += 32;

    if (event.mods.shift) cb |= 4;
    if (event.mods.alt) cb |= 8;
    if (event.mods.ctrl) cb |= 16;

    try writer.print("\x1b[M{c}{c}{c}", .{ cb + 32, @as(u8, @intCast(event.col + 1)) + 32, @as(u8, @intCast(event.row + 1)) + 32 });
}
