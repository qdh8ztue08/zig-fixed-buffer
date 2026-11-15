//! Hex encoding into a `FixedBuf` tail, and decoding out of a borrowed slice.
//!
//! Encoding checks the full encoded length against `buf.remaining()` before the
//! first byte is written, so a short buffer never leaves half a payload behind.

const std = @import("std");

pub const Error = error{ NoSpaceLeft, InvalidHex };

const upper = "0123456789ABCDEF";
const lower = "0123456789abcdef";

pub fn encodedLen(byte_count: usize) usize {
    return byte_count * 2;
}

pub fn encodeUpper(buf: anytype, src: []const u8) Error!void {
    try encodeWith(buf, src, upper);
}

pub fn encodeLower(buf: anytype, src: []const u8) Error!void {
    try encodeWith(buf, src, lower);
}

fn encodeWith(buf: anytype, src: []const u8, comptime digits: *const [16]u8) Error!void {
    if (encodedLen(src.len) > buf.remaining()) return error.NoSpaceLeft;
    for (src) |byte| {
        try buf.append(digits[byte >> 4]);
        try buf.append(digits[byte & 0x0f]);
    }
}

fn nibble(char: u8) Error!u4 {
    return switch (char) {
        '0'...'9' => @intCast(char - '0'),
        'a'...'f' => @intCast(char - 'a' + 10),
        'A'...'F' => @intCast(char - 'A' + 10),
        else => error.InvalidHex,
    };
}

/// Writes decoded bytes into `dst` and returns the written prefix.
pub fn decode(dst: []u8, text: []const u8) Error![]u8 {
    if (text.len % 2 != 0) return error.InvalidHex;
    const count = text.len / 2;
    if (count > dst.len) return error.NoSpaceLeft;
    for (dst[0..count], 0..) |*slot, i| {
        slot.* = @as(u8, try nibble(text[i * 2])) << 4 | @as(u8, try nibble(text[i * 2 + 1]));
    }
    return dst[0..count];
}

test "roundtrip preserves bytes in both cases" {
    const fixed = @import("fixed_buffer");
    var buf = fixed.FixedBuf(16, 1).init();

    try encodeUpper(&buf, "Hi\x00\xff");
    try std.testing.expectEqualStrings("486900FF", buf.written());

    var raw: [8]u8 = undefined;
    const decoded = try decode(&raw, buf.written());
    try std.testing.expectEqualStrings("Hi\x00\xff", decoded);

    buf.clear();
    try encodeLower(&buf, "Hi");
    try std.testing.expectEqualStrings("4869", buf.written());
}

test "encode is all-or-nothing on a short buffer" {
    const fixed = @import("fixed_buffer");
    var buf = fixed.FixedBuf(4, 4).init();
    try std.testing.expectError(error.NoSpaceLeft, encodeUpper(&buf, "abc"));
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    try encodeUpper(&buf, "ab");
    try std.testing.expect(buf.isFull());
}

test "decode rejects odd length and bad digits" {
    var raw: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidHex, decode(&raw, "abc"));
    try std.testing.expectError(error.InvalidHex, decode(&raw, "zz"));
    try std.testing.expectError(error.NoSpaceLeft, decode(raw[0..1], "aabb"));
}
