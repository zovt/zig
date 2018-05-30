const assert = @import("std").debug.assert;
const mem = @import("std").mem;
const reflection = this;

test "reflection: array, pointer, nullable, error union type child" {
    comptime {
        assert(([10]u8).Child == u8);
        assert((&u8).Child == u8);
        assert((error!u8).Payload == u8);
        assert((?u8).Child == u8);
    }
}

test "reflection: function return type, var args, and param types" {
    comptime {
        assert(@typeOf(dummy).ReturnType == i32);
        assert(!@typeOf(dummy).is_var_args);
        assert(@typeOf(dummy_varargs).is_var_args);
        assert(@typeOf(dummy).arg_count == 3);
    }
}

fn dummy(a: bool, b: i32, c: f32) i32 {
    return 1234;
}
fn dummy_varargs(args: ...) void {}

test "reflection: @field" {
    var f = Foo{
        .one = 42,
        .two = true,
        .three = void{},
    };

    assert(f.one == f.one);
    assert(@field(f, "o" ++ "ne") == f.one);
    assert(@field(f, "t" ++ "wo") == f.two);
    assert(@field(f, "th" ++ "ree") == f.three);
    assert(@field(Foo, "const" ++ "ant") == Foo.constant);
    assert(@field(Bar, "O" ++ "ne") == Bar.One);
    assert(@field(Bar, "T" ++ "wo") == Bar.Two);
    assert(@field(Bar, "Th" ++ "ree") == Bar.Three);
    assert(@field(Bar, "F" ++ "our") == Bar.Four);
    assert(@field(reflection, "dum" ++ "my")(true, 1, 2) == dummy(true, 1, 2));
    @field(f, "o" ++ "ne") = 4;
    assert(f.one == 4);
}

const Foo = struct {
    const constant = 52;

    one: i32,
    two: bool,
    three: void,
};

const Bar = union(enum) {
    One: void,
    Two: i32,
    Three: bool,
    Four: f64,
};
