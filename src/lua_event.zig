const std = @import("std");
const ziglua = @import("zlua");
const vaxis = @import("vaxis");
const Surface = @import("Surface.zig");
const msgpack = @import("msgpack.zig");

pub const Event = union(enum) {
    vaxis: vaxis.Event,
    pty_attach: struct {
        id: u32,
        surface: *Surface,
        app: *anyopaque,
        send_fn: *const fn (app: *anyopaque, id: u32, key: KeyData) anyerror!void,
    },
    pty_exited: struct {
        id: u32,
        status: u32,
    },
    init: void,
};

pub const KeyData = struct {
    key: []const u8,
    ctrl: bool,
    alt: bool,
    shift: bool,
    super: bool,
};

pub fn registerMetatable(lua: *ziglua.Lua) !void {
    _ = try lua.newMetatable("PrisePty");
    // Metatable is at -1
    _ = lua.pushString("__index");
    lua.pushFunction(ziglua.wrap(ptyIndex));
    lua.setTable(-3);
    lua.pop(1);
}

pub fn pushEvent(lua: *ziglua.Lua, event: Event) !void {
    lua.createTable(0, 2);

    switch (event) {
        .init => {
            _ = lua.pushString("init");
            lua.setField(-2, "type");
        },
        .pty_attach => |info| {
            std.log.info("pushEvent: pty_attach id={}", .{info.id});
            _ = lua.pushString("pty_attach");
            lua.setField(-2, "type");

            lua.createTable(0, 1);

            const pty = lua.newUserdata(PtyHandle, @sizeOf(PtyHandle));
            pty.* = .{
                .id = info.id,
                .surface = info.surface,
                .app = info.app,
                .send_fn = info.send_fn,
            };

            _ = lua.getMetatableRegistry("PrisePty");
            lua.setMetatable(-2);

            lua.setField(-2, "pty");

            lua.setField(-2, "data");
            std.log.info("pushEvent: pty_attach done", .{});
        },

        .pty_exited => |info| {
            _ = lua.pushString("pty_exited");
            lua.setField(-2, "type");

            lua.createTable(0, 2);
            lua.pushInteger(@intCast(info.id));
            lua.setField(-2, "id");
            lua.pushInteger(@intCast(info.status));
            lua.setField(-2, "status");
            lua.setField(-2, "data");
        },

        .vaxis => |vaxis_event| switch (vaxis_event) {
            .key_press => |key| {
                _ = lua.pushString("key_press");
                lua.setField(-2, "type");

                lua.createTable(0, 5);

                if (key.text) |text| {
                    _ = lua.pushString(text);
                    lua.setField(-2, "key");
                } else if (key.codepoint != 0) {
                    var buf: [5]u8 = undefined; // Increased size for null terminator
                    const len = std.unicode.utf8Encode(key.codepoint, buf[0..4]) catch 0;
                    if (len > 0) {
                        buf[len] = 0; // Manually add null terminator
                        _ = lua.pushString(buf[0..len :0]);
                        lua.setField(-2, "key");
                    }
                }

                lua.pushBoolean(key.mods.ctrl);
                lua.setField(-2, "ctrl");

                lua.pushBoolean(key.mods.alt);
                lua.setField(-2, "alt");

                lua.pushBoolean(key.mods.shift);
                lua.setField(-2, "shift");

                lua.pushBoolean(key.mods.super);
                lua.setField(-2, "super");

                lua.setField(-2, "data");
            },

            .winsize => |ws| {
                _ = lua.pushString("winsize");
                lua.setField(-2, "type");

                lua.createTable(0, 4);
                lua.pushInteger(@intCast(ws.rows));
                lua.setField(-2, "rows");
                lua.pushInteger(@intCast(ws.cols));
                lua.setField(-2, "cols");
                lua.pushInteger(@intCast(ws.x_pixel));
                lua.setField(-2, "width");
                lua.pushInteger(@intCast(ws.y_pixel));
                lua.setField(-2, "height");

                lua.setField(-2, "data");
            },

            else => {
                _ = lua.pushString("unknown");
                lua.setField(-2, "type");
            },
        },
    }
}

const PtyHandle = struct {
    id: u32,
    surface: *Surface,
    app: *anyopaque,
    send_fn: *const fn (app: *anyopaque, id: u32, key: KeyData) anyerror!void,
};

fn ptyIndex(lua: *ziglua.Lua) i32 {
    const key = lua.toString(2) catch return 0;
    if (std.mem.eql(u8, key, "title")) {
        lua.pushFunction(ziglua.wrap(ptyTitle));
        return 1;
    }
    if (std.mem.eql(u8, key, "id")) {
        lua.pushFunction(ziglua.wrap(ptyId));
        return 1;
    }
    if (std.mem.eql(u8, key, "send_key")) {
        lua.pushFunction(ziglua.wrap(ptySendKey));
        return 1;
    }
    return 0;
}

fn ptyTitle(lua: *ziglua.Lua) i32 {
    const pty = lua.checkUserdata(PtyHandle, 1, "PrisePty");
    const title = pty.surface.getTitle();
    _ = lua.pushString(title);
    return 1;
}

fn ptyId(lua: *ziglua.Lua) i32 {
    const pty = lua.checkUserdata(PtyHandle, 1, "PrisePty");
    lua.pushInteger(@intCast(pty.id));
    return 1;
}

fn ptySendKey(lua: *ziglua.Lua) i32 {
    const pty = lua.checkUserdata(PtyHandle, 1, "PrisePty");
    lua.checkType(2, .table);

    _ = lua.getField(2, "key");
    const key_str = lua.toString(-1) catch "";
    lua.pop(1);

    _ = lua.getField(2, "ctrl");
    const ctrl = lua.toBoolean(-1);
    lua.pop(1);

    _ = lua.getField(2, "alt");
    const alt = lua.toBoolean(-1);
    lua.pop(1);

    _ = lua.getField(2, "shift");
    const shift = lua.toBoolean(-1);
    lua.pop(1);

    _ = lua.getField(2, "super");
    const super = lua.toBoolean(-1);
    lua.pop(1);

    const key = KeyData{
        .key = key_str,
        .ctrl = ctrl,
        .alt = alt,
        .shift = shift,
        .super = super,
    };

    pty.send_fn(pty.app, pty.id, key) catch |err| {
        lua.raiseErrorStr("Failed to send key: %s", .{@errorName(err).ptr});
    };
    return 0;
}

pub fn luaToMsgpack(lua: *ziglua.Lua, index: i32, allocator: std.mem.Allocator) !msgpack.Value {
    const type_ = lua.typeOf(index);
    switch (type_) {
        .nil => return .nil,
        .boolean => return .{ .boolean = lua.toBoolean(index) },
        .number => {
            if (lua.isInteger(index)) {
                return .{ .integer = try lua.toInteger(index) };
            } else {
                return .{ .float = try lua.toNumber(index) };
            }
        },
        .string => return .{ .string = try allocator.dupe(u8, lua.toString(index) catch "") },
        .table => {
            const len = lua.rawLen(index);
            if (len > 0) {
                var arr = try allocator.alloc(msgpack.Value, len);
                errdefer allocator.free(arr);
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    _ = lua.rawGetIndex(index, @intCast(i + 1));
                    arr[i] = try luaToMsgpack(lua, -1, allocator);
                    lua.pop(1);
                }
                return .{ .array = arr };
            } else {
                var map_items = std.ArrayList(msgpack.Value.KeyValue).empty;
                errdefer map_items.deinit(allocator);

                const table_idx = if (index < 0) index - 1 else index;

                lua.pushNil();
                while (lua.next(table_idx)) {
                    const key = try luaToMsgpack(lua, -2, allocator);
                    const value = try luaToMsgpack(lua, -1, allocator);
                    try map_items.append(allocator, .{ .key = key, .value = value });
                    lua.pop(1);
                }
                return .{ .map = try map_items.toOwnedSlice(allocator) };
            }
        },
        else => return .nil,
    }
}

pub fn getPtyId(lua: *ziglua.Lua, index: i32) !u32 {
    if (lua.typeOf(index) == .number) {
        return @intCast(try lua.toInteger(index));
    }

    if (lua.isUserdata(index)) {
        lua.getMetatable(index) catch return error.InvalidPty;

        _ = lua.getMetatableRegistry("PrisePty");
        const equal = lua.compare(-1, -2, .eq);
        lua.pop(2);

        if (equal) {
            const pty = try lua.toUserdata(PtyHandle, index);
            return pty.id;
        }
    }

    return error.InvalidPty;
}
