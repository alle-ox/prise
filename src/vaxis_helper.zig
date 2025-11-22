const std = @import("std");
const vaxis = @import("vaxis");

pub fn vaxisKeyToString(allocator: std.mem.Allocator, key: vaxis.Key) ![]u8 {
    // Check for named keys by codepoint matching
    // Note: vaxis.Key constants are u21 codepoints in PUA range
    if (key.codepoint == vaxis.Key.enter) return try allocator.dupe(u8, "Enter");
    if (key.codepoint == vaxis.Key.tab) return try allocator.dupe(u8, "Tab");
    if (key.codepoint == vaxis.Key.backspace) return try allocator.dupe(u8, "Backspace");
    if (key.codepoint == vaxis.Key.escape) return try allocator.dupe(u8, "Escape");
    if (key.codepoint == vaxis.Key.space) return try allocator.dupe(u8, " ");
    if (key.codepoint == vaxis.Key.delete) return try allocator.dupe(u8, "Delete");
    if (key.codepoint == vaxis.Key.insert) return try allocator.dupe(u8, "Insert");
    if (key.codepoint == vaxis.Key.home) return try allocator.dupe(u8, "Home");
    if (key.codepoint == vaxis.Key.end) return try allocator.dupe(u8, "End");
    if (key.codepoint == vaxis.Key.page_up) return try allocator.dupe(u8, "PageUp");
    if (key.codepoint == vaxis.Key.page_down) return try allocator.dupe(u8, "PageDown");
    if (key.codepoint == vaxis.Key.up) return try allocator.dupe(u8, "ArrowUp");
    if (key.codepoint == vaxis.Key.down) return try allocator.dupe(u8, "ArrowDown");
    if (key.codepoint == vaxis.Key.left) return try allocator.dupe(u8, "ArrowLeft");
    if (key.codepoint == vaxis.Key.right) return try allocator.dupe(u8, "ArrowRight");
    if (key.codepoint == vaxis.Key.f1) return try allocator.dupe(u8, "F1");
    if (key.codepoint == vaxis.Key.f2) return try allocator.dupe(u8, "F2");
    if (key.codepoint == vaxis.Key.f3) return try allocator.dupe(u8, "F3");
    if (key.codepoint == vaxis.Key.f4) return try allocator.dupe(u8, "F4");
    if (key.codepoint == vaxis.Key.f5) return try allocator.dupe(u8, "F5");
    if (key.codepoint == vaxis.Key.f6) return try allocator.dupe(u8, "F6");
    if (key.codepoint == vaxis.Key.f7) return try allocator.dupe(u8, "F7");
    if (key.codepoint == vaxis.Key.f8) return try allocator.dupe(u8, "F8");
    if (key.codepoint == vaxis.Key.f9) return try allocator.dupe(u8, "F9");
    if (key.codepoint == vaxis.Key.f10) return try allocator.dupe(u8, "F10");
    if (key.codepoint == vaxis.Key.f11) return try allocator.dupe(u8, "F11");
    if (key.codepoint == vaxis.Key.f12) return try allocator.dupe(u8, "F12");

    // For regular keys, use the text
    if (key.text) |text| {
        return try allocator.dupe(u8, text);
    }

    // Fallback to codepoint
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(key.codepoint, &buf) catch return try allocator.dupe(u8, "Unidentified");
    return try allocator.dupe(u8, buf[0..len]);
}
