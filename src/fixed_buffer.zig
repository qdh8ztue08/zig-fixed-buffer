//! Comptime-validated fixed-capacity byte buffer.
//!
//! Backing storage lives inside the value: no allocator appears anywhere in
//! this file. Capacity, alignment, and the capacity/alignment relationship are
//! all checked inside a `comptime` block, so an impossible instantiation fails
//! to compile instead of panicking on a full buffer later.
//!
//! Intended for protocol framing, small syscall payloads, and archive headers
//! where the maximum size is known from a spec.

const std = @import("std");

pub const Error = error{NoSpaceLeft};

/// Returns a buffer struct with exactly `capacity` bytes of inline storage,
/// aligned to `alignment`.
///
/// `capacity` must be non-zero and at most `maxInt(u32)`; `alignment` must be
/// a power of two and divide `capacity` evenly, so that an aligned record never
/// straddles the usable end of the buffer.
pub fn FixedBuf(comptime capacity: usize, comptime alignment: usize) type {
    comptime {
        if (capacity == 0) @compileError("FixedBuf: capacity must be greater than zero");
        if (capacity > std.math.maxInt(u32)) @compileError("FixedBuf: capacity must fit in u32");
        if (!std.mem.isValidAlign(alignment)) @compileError("FixedBuf: alignment must be a power of two");
        if (capacity % alignment != 0) @compileError("FixedBuf: capacity must be a whole multiple of alignment");
    }

    return struct {
        const Self = @This();

        pub const cap: usize = capacity;
        pub const alignment_bytes: usize = alignment;

        bytes: [capacity]u8 align(alignment) = undefined,
        len: usize = 0,

        pub fn init() Self {
            return .{};
        }

        /// Leaves every byte of the backing array set to `byte`. Used when the
        /// unused tail must be deterministic, e.g. before hashing a dump.
        pub fn initFill(byte: u8) Self {
            return .{ .bytes = @splat(byte) };
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        /// Bytes written so far.
        pub fn written(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        /// Unwritten tail, for direct writes followed by `commit`.
        pub fn spare(self: *Self) []u8 {
            return self.bytes[self.len..];
        }

        pub fn remaining(self: *const Self) usize {
            return capacity - self.len;
        }

        pub fn isFull(self: *const Self) bool {
            return self.len == capacity;
        }

        pub fn append(self: *Self, byte: u8) Error!void {
            if (self.len == capacity) return error.NoSpaceLeft;
            self.bytes[self.len] = byte;
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, src: []const u8) Error!void {
            if (src.len > self.remaining()) return error.NoSpaceLeft;
            @memcpy(self.bytes[self.len..][0..src.len], src);
            self.len += src.len;
        }

        /// Bulk append of `count` copies of `byte`.
        pub fn appendByteNTimes(self: *Self, byte: u8, count: usize) Error!void {
            if (count > self.remaining()) return error.NoSpaceLeft;
            @memset(self.bytes[self.len..][0..count], byte);
            self.len += count;
        }

        /// `std.Io.Writer` over the spare capacity. The writer buffers into the
        /// tail; call `commit` after draining it so the bytes count as written.
        pub fn writer(self: *Self) std.Io.Writer {
            return .fixed(self.spare());
        }

        pub fn commit(self: *Self, w: *const std.Io.Writer) void {
            self.len += w.end;
        }
    };
}

test "append and appendSlice stop at capacity" {
    var buf = FixedBuf(8, 1).init();
    try buf.appendSlice("abc");
    try buf.appendByteNTimes('x', 5);
    try std.testing.expect(buf.isFull());
    try std.testing.expectEqualStrings("abcxxxxx", buf.written());
    try std.testing.expectError(error.NoSpaceLeft, buf.append('!'));
    try std.testing.expectError(error.NoSpaceLeft, buf.appendSlice("!"));

    buf.clear();
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    try std.testing.expectEqual(@as(usize, 8), buf.remaining());
}

test "appendSlice is all-or-nothing" {
    var buf = FixedBuf(4, 4).init();
    try std.testing.expectError(error.NoSpaceLeft, buf.appendSlice("abcde"));
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    try std.testing.expectEqualStrings("", buf.written());
}

test "initFill sets the whole backing array" {
    const buf = FixedBuf(4, 2).initFill(0xAA);
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    try std.testing.expectEqualSlices(u8, &.{ 0xAA, 0xAA, 0xAA, 0xAA }, &buf.bytes);
}

test "writer fills spare capacity and commit advances len" {
    var buf = FixedBuf(16, 1).init();
    var w = buf.writer();
    try w.writeAll("hello");
    try std.testing.expectEqual(@as(usize, 0), buf.len);
    buf.commit(&w);
    try std.testing.expectEqualStrings("hello", buf.written());

    var w2 = buf.writer();
    try w2.splatByteAll('.', buf.remaining());
    buf.commit(&w2);
    try std.testing.expect(buf.isFull());
}

test "declared headers are honoured" {
    const Buf = FixedBuf(32, 8);
    try std.testing.expectEqual(@as(usize, 32), Buf.cap);
    try std.testing.expectEqual(@as(usize, 8), Buf.alignment_bytes);
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Buf));
}
