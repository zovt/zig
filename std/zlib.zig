
//const assert = @import("std").assert;
fn assert(b:bool) {
  if (!b) unreachable{}
}

const MOD_ADLER = 65521;

pub fn adler32(start: u32, data: []u8) -> u32 {
    var a = start & 0xffff;
    var b = start >> 16;
    for (data) |c| {
        a = (a + c) % MOD_ADLER;
        b = (b + a) % MOD_ADLER;
    }
    return (b << 16) | a;
}

#attribute("test")
fn test_adler32() {
  assert(adler32(0x56781234, "") == 0x56781234);
  assert(adler32(1, "\x00\x00\x00\x00") == 0x40001);
  assert(adler32(1, "Wikipedia") == 0x11E60398);

  var value: u32 = 0;
  // TODO: syntax to do something n times
  var do_it_n_times: u32 = 0;
  while (do_it_n_times < 0x1000) {
    value = adler32(value, "abCDe");
    do_it_n_times += 1;
  }
  assert(value == 0xff03f186);
}
