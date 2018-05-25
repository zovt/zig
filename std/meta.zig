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
                if (field.value == TagType(value)) return field.name;
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
                if (err.value == u64(value)) return err.name;
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

pub fn maxValue(comptime T: type) T {
    switch (@typeInfo(T)) {
        TypeId.Enum => |info| {
            const TagType = info.tag_type;
            var max = TagType(info.fields[0].value);
            inline for (info.fields[1..]) |field| {
                if (max < field.value) max = TagType(field.value);
            }

            return T(max);
        },
        TypeId.Int => |info| {
            if (info.is_signed) return T((1 << info.bits - 1) - 1);

            return T((1 << info.bits) - 1);
        },
        // TODO: Floats
        //TypeId.Float => |info| {
        //},
        else => @compileError("no max value available for type '" ++ @typeName(T) ++ "'"),
    }
}

test "std.meta.maxValue" {
    const E1 = enum {
        A,
        B,
    };
    const E2 = enum(u8) {
        C = 33,
        D = 22,
    };

    debug.assert(maxValue(E1) == E1.B);
    debug.assert(maxValue(E2) == E2.C);
    debug.assert(maxValue(u8) == 255);
    debug.assert(maxValue(i8) == 127);
    debug.assert(maxValue(u7) == 127);
    debug.assert(maxValue(i7) == 63);
}

pub fn minValue(comptime T: type) T {
    switch (@typeInfo(T)) {
        TypeId.Enum => |info| {
            const TagType = info.tag_type;
            var min = TagType(info.fields[0].value);
            inline for (info.fields[1..]) |field| {
                if (min > field.value) min = TagType(field.value);
            }

            return T(min);
        },
        TypeId.Int => |info| {
            if (info.is_signed) return T(-(1 << info.bits - 1));

            return T(0);
        },
        // TODO: Floats
        //TypeId.Float => |info| {
        //},
        else => @compileError("no max value available for type '" ++ @typeName(T) ++ "'"),
    }
}

test "std.meta.minValue" {
    const E1 = enum {
        A,
        B,
    };
    const E2 = enum(u8) {
        C = 33,
        D = 22,
    };

    debug.assert(minValue(E1) == E1.A);
    debug.assert(minValue(E2) == E2.D);
    debug.assert(minValue(u8) == 0);
    debug.assert(minValue(i8) == -128);
    debug.assert(minValue(u7) == 0);
    debug.assert(minValue(i7) == -64);
}
