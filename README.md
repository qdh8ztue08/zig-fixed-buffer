# zig-fixed-buffer

Comptime-validated fixed-capacity byte buffer for Zig.

`FixedBuf(capacity, alignment)` gives you inline storage with the maximum size
and alignment pinned at compile time. If the numbers cannot work — zero
capacity, non-power-of-two alignment, a capacity that is not a whole multiple of
the alignment — the instantiation is a compile error, not a runtime panic in
production.

## Why

Protocol headers, syscall payloads and archive records have sizes fixed by a
spec. Allocating them on the heap buys nothing and costs a failure path. This
type keeps the buffer on the stack (or inside your struct), reports overflow as
`error.NoSpaceLeft`, and leaves no allocator parameter in any signature.

The validation exists because the interesting mistakes are arithmetic ones:
`FixedBuf(4096, 3)` compiles against a hand-copied number and only misbehaves
when an aligned record lands at offset 4095. Here it is rejected up front.

## Allocation strategy

Zero allocations. The backing array is a field of the returned struct, so the
buffer's lifetime and address are the struct's. Nothing here calls an allocator
and nothing here can fail for memory pressure. Copies are `@memcpy` into the
tail; appends are all-or-nothing, so a rejected `appendSlice` leaves `len`
untouched. `initFill` exists for the cases where the unwritten tail must be
deterministic before hashing or comparing a dump.

If you need growth, wrap this in a parent that upgrades to `std.ArrayList` on
`NoSpaceLeft`; the buffer itself stays fixed.

## Requirements

Zig **0.17.1** (`build.zig.zon` sets `minimum_zig_version`). No dependencies,
no C, any target.

## Install

As a package dependency:

```sh
zig fetch --save https://github.com/qdh8ztue08/zig-fixed-buffer/archive/refs/heads/main.tar.gz
```

then in `build.zig`:

```zig
const fixed = b.dependency("zig_fixed_buffer", .{ .target = target }).module("fixed_buffer");
exe.root_module.addImport("fixed_buffer", fixed);
```

Or vendor `src/fixed_buffer.zig` and import it directly.

## Usage

```zig
const fixed = @import("fixed_buffer");

const Header = fixed.FixedBuf(64, 8);

var hdr = Header.initFill(0);
try hdr.appendSlice("FBT1");          // magic
try hdr.append(0x02);                  // version
try hdr.appendSlice(&std.mem.toBytes(@as(u32, payload_len)));

std.debug.assert(hdr.remaining() == 64 - 8);

// std.Io.Writer view over the tail; commit counts the drained bytes.
var w = hdr.writer();
try w.print("{s}", .{checksum_hex});
hdr.commit(&w);
```

`append` / `appendSlice` / `appendByteNTimes` return `error.NoSpaceLeft` when
the write does not fit.

## Encodings

`src/enc/hex.zig` (`encodeUpper`, `encodeLower`, `decode`) and
`src/enc/base64.zig` (`encode`, `decode`) write into a `FixedBuf` tail. Both
compute the full encoded length first and return `error.NoSpaceLeft` before
touching the buffer, so a short tail never leaves a half-written payload.

```zig
try hex.encodeUpper(&hdr, tag_bytes);          // 2 bytes per input byte
const raw = try hex.decode(&raw_buf, hdr.written());
```

## API

- `FixedBuf(capacity, alignment)` — type constructor, all checks comptime
- `init()`, `initFill(byte)`, `clear()`
- `append`, `appendSlice`, `appendByteNTimes`
- `written()`, `spare()`, `remaining()`, `isFull()`
- `writer()`, `commit(w)`
- `cap`, `alignment_bytes` — the validated constants

## Layout

```
build.zig              module `fixed_buffer`, `fbuf` demo, test step
build.zig.zon          package manifest, pinned minimum Zig version
src/fixed_buffer.zig   the buffer type and its tests
src/main.zig           512-byte argv joiner used as a smoke test
src/enc/hex.zig        hex codec over `FixedBuf`
src/enc/base64.zig     standard base64 codec over `FixedBuf`
```

```sh
zig build test
zig build run -- hello world
```

## Status

Small on purpose; the test step covers capacity, all-or-nothing appends, fill
patterns and writer commit. `fbuf` is a demo, not a stable CLI.

## License

MIT, see `LICENSE`.
