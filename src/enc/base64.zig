//! Standard base64 (RFC 4648, `+/` alphabet, `=` padding) into a `FixedBuf`.
//!
//! Same all-or-nothing rule as the hex module: the padded output length is
//! checked before any byte is appended.

const std = @import("std");

pub const Error = error{ NoSpaceLeft, InvalidBase64 };

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn encodedLen(byte_count: usize) usize {
    return (byte_count + 2) / 3 * 4;
}

pub fn encode(buf: anytype, src: []const u8) Error!void {
    if (encodedLen(src.len) > buf.remaining()) return error.NoSpaceLeft;

    var i: usize = 0;
    while (i + 3 <= src.len) : (i += 3) {
        const triple = (@as(u24, src[i]) << 16) | (@as(u24, src[i + 1]) << 8) | src[i + 2];
        try buf.append(alphabet[triple >> 18 & 0x3f]);
        try buf.append(alphabet[triple >> 12 & 0x3f]);
        try buf.append(alphabet[triple >> 6 & 0x3f]);
        try buf.append(alphabet[triple & 0x3f]);
    }

    const rest = src.len - i;
    if (rest == 1) {
        const triple = @as(u24, src[i]) << 16;
        try buf.append(alphabet[triple >> 18 & 0x3f]);
        try buf.append(alphabet[triple >> 12 & 0x3f]);
        try buf.appendSlice("==");
    } else if (rest == 2) {
        const triple = (@as(u24, src[i]) << 16) | (@as(u24, src[i + 1]) << 8);
        try buf.append(alphabet[triple >> 18 & 0x3f]);
        try buf.append(alphabet[triple >> 12 & 0x3f]);
        try buf.append(alphabet[triple >> 6 & 0x3f]);
        try buf.append('=');
    }
}

fn sextet(char: u8) Error!u6 {
    return switch (char) {
        'A'...'Z' => @intCast(char - 'A'),
        'a'...'z' => @intCast(char - 'a' + 26),
        '0'...'9' => @intCast(char - '0' + 52),
        '+' => 62,
        '/' => 63,
        else => error.InvalidBase64,
    };
}

/// Decodes into `dst` and returns the written prefix. Padding is only accepted
/// as the final one or two characters.
pub fn decode(dst: []u8, text: []const u8) Error![]u8 {
    if (text.len % 4 != 0) return error.InvalidBase64;

    var pad: usize = 0;
    if (text.len != 0) {
        pad = if (text[text.len - 1] == '=') (if (text[text.len - 2] == '=') 2 else 1) else 0;
    }
    const count = text.len / 4 * 3 - pad;
    if (count > dst.len) return error.NoSpaceLeft;

    var out: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 4) {
        const last = i + 4 == text.len;
        const a = try sextet(text[i]);
        const b = try sextet(text[i + 1]);
        const c: u6 = if (last and pad >= 2) 0 else try sextet(text[i + 2]);
        const d: u6 = if (last and pad >= 1) 0 else try sextet(text[i + 3]);

        const triple = (@as(u24, a) << 18) | (@as(u24, b) << 12) | (@as(u24, c) << 6) | d;
        const chunk = [_]u8{ @intCast(triple >> 16), @intCast(triple >> 8 & 0xff), @intCast(triple & 0xff) };
        const take = if (last) 3 - pad else 3;
        @memcpy(dst[out..][0..take], chunk[0..take]);
        out += take;
    }
    return dst[0..out];
}

test "roundtrip covers all tail lengths" {
    const fixed = @import("fixed_buffer");
    var buf = fixed.FixedBuf(16, 8).init();
    var raw: [8]u8 = undefined;

    for ([_][]const u8{ "", "f", "fo", "foo", "foob", "fooba", "foobar" }) |src| {
        buf.clear();
        try encode(&buf, src);
        const decoded = try decode(&raw, buf.written());
        try std.testing.expectEqualStrings(src, decoded);
    }
}

test "matches known vectors" {
    const fixed = @import("fixed_buffer");
    var buf = fixed.FixedBuf(16, 1).init();
    try encode(&buf, "foobar");
    try std.testing.expectEqualStrings("Zm9vYmFy", buf.written());
    try std.testing.expectEqual(@as(usize, 8), encodedLen(4));
}

test "rejects short targets and malformed input" {
    const fixed = @import("fixed_buffer");
    var buf = fixed.FixedBuf(4, 4).init();
    try std.testing.expectError(error.NoSpaceLeft, encode(&buf, "abcd"));
    try std.testing.expectEqual(@as(usize, 0), buf.len);

    var raw: [4]u8 = undefined;
    try std.testing.expectError(error.InvalidBase64, decode(&raw, "abc"));
    try std.testing.expectError(error.InvalidBase64, decode(&raw, "ab!d"));
    try std.testing.expectError(error.NoSpaceLeft, decode(raw[0..2], "Zm9v"));
}
