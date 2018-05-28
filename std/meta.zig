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

pub fn isSigned(comptime T: type) bool {
    const info = @typeInfo(T).Int;
    return info.is_signed;
}

test "std.meta.isSigned" {
    debug.assert(!isSigned(u8));
    debug.assert(isSigned(i8));
}

pub fn bits(comptime T: type) u8 {
    return switch (@typeInfo(T)) {
        TypeId.Int => |info| info.bits,
        TypeId.Float => |info| info.bits,
        else => @compileError("Expected int or float type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.bits" {
    debug.assert(bits(u8) == 8);
    debug.assert(bits(f32) == 32);
}

pub fn isConst(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        TypeId.Pointer => |info| info.is_const,
        TypeId.Slice => |info| info.is_const,
        else => @compileError("Expected pointer or slice type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.isConst" {
    debug.assert(!isConst(&u8));
    debug.assert(isConst(&const u8));
    debug.assert(!isConst([]u8));
    debug.assert(isConst([]const u8));
}

pub fn isVolatile(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        TypeId.Pointer => |info| info.is_volatile,
        TypeId.Slice => |info| info.is_volatile,
        else => @compileError("Expected pointer or slice type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.isConst" {
    debug.assert(!isVolatile(&u8));
    debug.assert(isVolatile(&volatile u8));
    debug.assert(!isVolatile([]u8));
    debug.assert(isVolatile([]volatile u8));
}

pub fn alignment(comptime T: type) u32 {
    return switch (@typeInfo(T)) {
        TypeId.Pointer => |info| info.alignment,
        TypeId.Slice => |info| info.alignment,
        else => @compileError("Expected pointer or slice type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.alignment" {
    debug.assert(alignment(&align(1) u8) == 1);
    debug.assert(alignment(&align(2) u8) == 2);
    debug.assert(alignment([]align(1) u8) == 1);
    debug.assert(alignment([]align(2) u8) == 2);
}

pub fn Child(comptime T: type) type {
    return switch (@typeInfo(T)) {
        TypeId.Array => |info| info.child,
        TypeId.Pointer => |info| info.child,
        TypeId.Slice => |info| info.child,
        TypeId.Nullable => |info| info.child,
        TypeId.Promise => |info| info.child,
        else => @compileError("Expected promis, pointer, nullable, array or slice type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.Child" {
    debug.assert(Child([1]u8) == u8);
    debug.assert(Child(&u8) == u8);
    debug.assert(Child([]u8) == u8);
    debug.assert(Child(?u8) == u8);
    debug.assert(Child(promise->u8) == u8);
}

pub fn len(comptime T: type) usize {
    const info = @typeInfo(T).Array;
    return info.len;
}

test "std.meta.len" {
    debug.assert(len([1]u8) == 1);
    debug.assert(len([2]u8) == 2);
}

pub fn containerLayout(comptime T: type) TypeInfo.ContainerLayout {
    return switch (@typeInfo(T)) {
        TypeId.Struct => |info| info.layout,
        TypeId.Enum => |info| info.layout,
        TypeId.Union => |info| info.layout,
        else => @compileError("Expected struct, enum or union type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.containerLayout" {
    const E1 = enum { A };
    const E2 = packed enum { A };
    const E3 = extern enum { A };
    const S1 = struct { };
    const S2 = packed struct { };
    const S3 = extern struct { };
    const U1 = union { a: u8 };
    const U2 = packed union { a: u8 };
    const U3 = extern union { a: u8 };

    debug.assert(containerLayout(E1) == TypeInfo.ContainerLayout.Auto);
    debug.assert(containerLayout(E2) == TypeInfo.ContainerLayout.Packed);
    debug.assert(containerLayout(E3) == TypeInfo.ContainerLayout.Extern);
    debug.assert(containerLayout(S1) == TypeInfo.ContainerLayout.Auto);
    debug.assert(containerLayout(S2) == TypeInfo.ContainerLayout.Packed);
    debug.assert(containerLayout(S3) == TypeInfo.ContainerLayout.Extern);
    debug.assert(containerLayout(U1) == TypeInfo.ContainerLayout.Auto);
    debug.assert(containerLayout(U2) == TypeInfo.ContainerLayout.Packed);
    debug.assert(containerLayout(U3) == TypeInfo.ContainerLayout.Extern);
}

pub fn definitions(comptime T: type) []TypeInfo.Definition {
    return switch (@typeInfo(T)) {
        TypeId.Struct => |info| info.defs,
        TypeId.Enum => |info| info.defs,
        TypeId.Union => |info| info.defs,
        else => @compileError("Expected struct, enum or union type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.definitions" {
    const E1 = enum {
        A,

        fn a() void { }
    };
    const S1 = struct {
        fn a() void { }
    };
    const U1 = union {
        a: u8,

        fn a() void { }
    };

    const defs = comptime [][]TypeInfo.Definition {
        definitions(E1),
        definitions(S1),
        definitions(U1),
    };

    inline for (defs) |def| {
        debug.assert(def.len == 1);
        debug.assert(comptime mem.eql(u8, def[0].name, "a"));
    }
}

pub fn defInfo(comptime T: type, comptime def_name: []const u8) TypeInfo.Definition {
    inline for (comptime definitions(T)) |def| {
        if (comptime mem.eql(u8, def.name, def_name))
            return def;
    }

    @compileError("'" ++ @typeName(T) ++ "' has no definition '" ++ def_name ++ "'");
}

test "std.meta.defInfo" {
    const E1 = enum {
        A,

        fn a() void { }
    };
    const S1 = struct {
        fn a() void { }
    };
    const U1 = union {
        a: u8,

        fn a() void { }
    };

    const infos = comptime []TypeInfo.Definition {
        defInfo(E1, "a"),
        defInfo(S1, "a"),
        defInfo(U1, "a"),
    };

    inline for (infos) |info| {
        debug.assert(comptime mem.eql(u8, info.name, "a"));
        debug.assert(!info.is_pub);
    }
}

pub fn fields(comptime T: type)
    switch (@typeInfo(T)) {
        TypeId.Struct => []TypeInfo.StructField,
        TypeId.Union => []TypeInfo.UnionField,
        TypeId.ErrorSet => []TypeInfo.Error,
        TypeId.Enum => []TypeInfo.EnumField,
        else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
    }
{
    return switch (@typeInfo(T)) {
        TypeId.Struct => |info| info.fields,
        TypeId.Union => |info| info.fields,
        TypeId.ErrorSet => |info| info.errors,
        TypeId.Enum => |info| info.fields,
        else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
    };
}

test "std.meta.fields" {
    const E1 = enum { A };
    const E2 = error { A };
    const S1 = struct { a: u8 };
    const U1 = union { a: u8 };

    const e1f = comptime fields(E1);
    const e2f = comptime fields(E2);
    const sf = comptime fields(S1);
    const uf = comptime fields(U1);

    debug.assert(e1f.len == 1);
    debug.assert(e2f.len == 1);
    debug.assert(sf.len == 1);
    debug.assert(uf.len == 1);
    debug.assert(mem.eql(u8, e1f[0].name, "A"));
    debug.assert(mem.eql(u8, e2f[0].name, "A"));
    debug.assert(mem.eql(u8, sf[0].name, "a"));
    debug.assert(mem.eql(u8, uf[0].name, "a"));
    debug.assert(comptime sf[0].field_type == u8);
    debug.assert(comptime uf[0].field_type == u8);
}

pub fn fieldInfo(comptime T: type, comptime field_name: []const u8)
    switch (@typeInfo(T)) {
        TypeId.Struct => TypeInfo.StructField,
        TypeId.Union => TypeInfo.UnionField,
        TypeId.ErrorSet => TypeInfo.Error,
        TypeId.Enum => TypeInfo.EnumField,
        else => @compileError("Expected struct, union, error set or enum type, found '" ++ @typeName(T) ++ "'"),
    }
{
    inline for (comptime fields(T)) |field| {
        if (comptime mem.eql(u8, field.name, field_name))
            return field;
    }

    @compileError("'" ++ @typeName(T) ++ "' has no field '" ++ field_name ++ "'");
}

test "std.meta.fieldInfo" {
    const E1 = enum { A };
    const E2 = error { A };
    const S1 = struct { a: u8 };
    const U1 = union { a: u8 };

    const e1f = comptime fieldInfo(E1, "A");
    const e2f = comptime fieldInfo(E2, "A");
    const sf = comptime fieldInfo(S1, "a");
    const uf = comptime fieldInfo(U1, "a");

    debug.assert(mem.eql(u8, e1f.name, "A"));
    debug.assert(mem.eql(u8, e2f.name, "A"));
    debug.assert(mem.eql(u8, sf.name, "a"));
    debug.assert(mem.eql(u8, uf.name, "a"));
    debug.assert(comptime sf.field_type == u8);
    debug.assert(comptime uf.field_type == u8);
}

pub fn ErrorSet(comptime T: type) type {
    const info = @typeInfo(T).ErrorUnion;
    return info.error_set;
}

test "std.meta.ErrorSet" {
    const E1 = error { };
    const E2 = error { A };
    debug.assert(ErrorSet(E1!u8) == E1);
    debug.assert(ErrorSet(E2!u8) == E2);
}

pub fn Payload(comptime T: type) type {
    const info = @typeInfo(T).ErrorUnion;
    return info.payload;
}

test "std.meta.Payload" {
    const E1 = error { };
    const E2 = error { A };
    debug.assert(Payload(E1!u8) == u8);
    debug.assert(Payload(E2!u16) == u16);
}

pub fn callConvention(comptime T: type) TypeInfo.CallingConvention {
    const info = @typeInfo(T).Fn;
    return info.calling_convention;
}

test "std.meta.callConvention" {
    const Funcs = struct {
        fn c() void { @setCold(true); }
    };

    debug.assert(callConvention(fn() void) == TypeInfo.CallingConvention.Unspecified);
    debug.assert(callConvention(extern fn() void) == TypeInfo.CallingConvention.C);

    // TODO: This fails, but im not sure why
    //debug.assert(callConvention(@typeOf(Funcs.c)) == TypeInfo.CallingConvention.Cold);

    debug.assert(callConvention(nakedcc fn() void) == TypeInfo.CallingConvention.Naked);
    debug.assert(callConvention(stdcallcc fn() void) == TypeInfo.CallingConvention.Stdcall);
    debug.assert(callConvention(async<&mem.Allocator> fn() void) == TypeInfo.CallingConvention.Async);
}

pub fn isGeneric(comptime T: type) bool {
    const info = @typeInfo(T).Fn;
    return info.is_generic;
}

test "std.meta.isGeneric" {
    const Funcs = struct {
        fn b(comptime T: type) void { }
    };

    debug.assert(!isGeneric(fn() void));
    debug.assert(isGeneric(@typeOf(Funcs.b)));
}

pub fn isVarArgs(comptime T: type) bool {
    const info = @typeInfo(T).Fn;
    return info.is_var_args;
}

test "std.meta.isVarArgs" {
    debug.assert(!isVarArgs(fn() void));
    debug.assert(isVarArgs(fn(...) void));
}

pub fn ReturnType(comptime T: type) type {
    const info = @typeInfo(T).Fn;
    return info.return_type;
}

test "std.meta.ReturnType" {
    debug.assert(ReturnType(fn() void) == void);
    debug.assert(ReturnType(fn() u8) == u8);
}

pub fn AsyncAllocatorType(comptime T: type) type {
    const info = @typeInfo(T).Fn;
    return info.async_allocator_type;
}

test "std.meta.AsyncAllocatorType" {
    debug.assert(AsyncAllocatorType(async<&mem.Allocator> fn() void) == &mem.Allocator);
}

pub fn args(comptime T: type) []TypeInfo.FnArg {
    const info = @typeInfo(T).Fn;
    return info.args;
}

test "std.meta.AsyncAllocatorType" {
    const aargs = comptime args(fn(u8) void);

    debug.assert(aargs.len == 1);
    debug.assert(comptime aargs[0].arg_type == u8);
    debug.assert(!aargs[0].is_generic);
    debug.assert(!aargs[0].is_noalias);
}
