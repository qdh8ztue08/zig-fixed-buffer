//! Demo: join argv into a 512-byte line buffer and echo it back.

const std = @import("std");
const fixed = @import("fixed_buffer");

const Line = fixed.FixedBuf(512, 8);

pub fn main(init: std.process.Init) !void {
    var line = Line.initFill(0);

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..], 1..) |arg, index| {
        if (index > 1) try line.append(' ');
        try line.appendSlice(arg);
    }
    if (line.len == 0) try line.appendSlice("(no arguments)");
    try line.append('\n');

    var out_buffer: [256]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), init.io, &out_buffer);
    try out.interface.writeAll(line.written());
    try out.interface.flush();
}

test "argv join" {
    var line = Line.initFill(0);
    try line.appendSlice("zig build run -- a b");
    try std.testing.expectEqual(@as(usize, 20), line.len);
}
