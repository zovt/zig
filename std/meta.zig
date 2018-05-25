const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const mem = std.mem;
const math = std.math;

const TypeId = builtin.TypeId;
const TypeInfo = builtin.TypeInfo;

pub fn tagName(value: var) []const u8 {
    const T = @typeOf(value);
    switch (@typeInfo(T)) {
        TypeId.Enum => |info| {
            const TagType = info.tag_type;
            inline for (info.fields) |field| {
                if (field.value == TagType(value))
                    return field.name;
            }

            unreachable;
        },
        // TODO: When https://github.com/ziglang/zig/issues/733 is a thing, we can have unions too.
        //TypeId.Union => |info| {
        //    const TagType = info.tag_type;
        //    if (TagType == @typeOf(undefined))
        //        @compileError("union has no associated enum");
        //
        //    inline for (info.fields) |field| {
        //        if ((??field.enum_field).value == TagType(value))
        //            return field.name;
        //    }
        //
        //    unreachable;
        //},
        TypeId.ErrorSet => |info| {
            inline for (info.errors) |err| {
                if (err.value == u64(value))
                    return err.name;
            }

            unreachable;
        },
        else => @compileError("expected enum, error set or union type, found '" ++ @typeName(T) ++ "'"),
    }
}

test "std.meta.tagName" {
    const E1 = enum {
        A,
        B,
    };
    const E2 = enum(u8) {
        C = 33,
        D,
    };
    const U1 = union(enum) {
        G: u8,
        H: u16,
    };
    const U2 = union(E1) {
        A: u8,
        B: u16,
    };

    var u1g = U1{ .G = 0 };
    var u1h = U1{ .H = 0 };
    var u2a = U2{ .A = 0 };
    var u2b = U2{ .B = 0 };

    debug.assert(mem.eql(u8, tagName(E1.A), "A"));
    debug.assert(mem.eql(u8, tagName(E1.B), "B"));
    debug.assert(mem.eql(u8, tagName(E2.C), "C"));
    debug.assert(mem.eql(u8, tagName(E2.D), "D"));
    debug.assert(mem.eql(u8, tagName(error.E), "E"));
    debug.assert(mem.eql(u8, tagName(error.F), "F"));

    //debug.assert(mem.eql(u8, tagName(u1g), "G"));
    //debug.assert(mem.eql(u8, tagName(u1h), "H"));
    //debug.assert(mem.eql(u8, tagName(u2a), "A"));
    //debug.assert(mem.eql(u8, tagName(u2b), "B"));
}
