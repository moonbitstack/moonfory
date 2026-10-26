// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Bytes as hexadecimal: every fixture below is the specification's, written
/// down.
fn wrote(f : (@moonfory.Writer) -> Unit) -> String {
  let w = @moonfory.Writer::new()
  f(w)
  @moonfory.hex(w.bytes())
}

///|
/// One character, `n` times.
fn repeated(c : Char, n : Int32) -> String {
  let out = StringBuilder()
  for _ in 0..<n {
    out.write_char(c)
  }
  out.to_string()
}

///|
test "the header byte carries the cross-language flag" {
  let xlang = @moonfory.Writer::new()
  xlang.write_head()
  inspect(@moonfory.hex(xlang.bytes()), content="01")
  let native = @moonfory.Writer::new(config=@moonfory.Config::new(xlang=false))
  native.write_head()
  inspect(@moonfory.hex(native.bytes()), content="00")
}

///|
test "a boolean is one byte" {
  inspect(wrote(fn(w) { w.write_bool(true) }), content="01")
  inspect(wrote(fn(w) { w.write_bool(false) }), content="00")
}

///|
test "fixed-width integers are little-endian" {
  inspect(wrote(fn(w) { w.write_i16(0x0102) }), content="0201")
  inspect(wrote(fn(w) { w.write_u16(0x0102) }), content="0201")
  inspect(wrote(fn(w) { w.write_i32(1) }), content="01000000")
  inspect(wrote(fn(w) { w.write_i32(-2) }), content="feffffff")
  inspect(wrote(fn(w) { w.write_i64(1L) }), content="0100000000000000")
  inspect(wrote(fn(w) { w.write_u64(1UL) }), content="0100000000000000")
  inspect(wrote(fn(w) { w.write_u8(255) }), content="ff")
  inspect(wrote(fn(w) { w.write_i8(-1) }), content="ff")
}

///|
test "floats are IEEE 754, little-endian" {
  inspect(wrote(fn(w) { w.write_f32(1.0) }), content="0000803f")
  inspect(wrote(fn(w) { w.write_f64(1.5) }), content="000000000000f83f")
}

///|
test "an unsigned varint is base 128, least significant group first" {
  inspect(wrote(fn(w) { w.write_var_u64(0UL) }), content="00")
  inspect(wrote(fn(w) { w.write_var_u64(127UL) }), content="7f")
  inspect(wrote(fn(w) { w.write_var_u64(128UL) }), content="8001")
  inspect(wrote(fn(w) { w.write_var_u64(300UL) }), content="ac02")
  inspect(wrote(fn(w) { w.write_var_u64(16_383UL) }), content="ff7f")
}

///|
test "a signed varint is zigzagged first, so a small negative stays one byte" {
  inspect(wrote(fn(w) { w.write_var_i64(0L) }), content="00")
  inspect(wrote(fn(w) { w.write_var_i64(-1L) }), content="01")
  inspect(wrote(fn(w) { w.write_var_i64(1L) }), content="02")
  inspect(wrote(fn(w) { w.write_var_i64(-2L) }), content="03")
  inspect(wrote(fn(w) { w.write_var_i64(63L) }), content="7e")
  inspect(wrote(fn(w) { w.write_var_i64(-64L) }), content="7f")
  inspect(wrote(fn(w) { w.write_var_i64(64L) }), content="8001")
}

///|
test "a tagged integer is four bytes while it fits, and nine when it does not" {
  inspect(wrote(fn(w) { w.write_tagged_i64(0L) }), content="00000000")
  inspect(wrote(fn(w) { w.write_tagged_i64(1L) }), content="02000000")
  inspect(wrote(fn(w) { w.write_tagged_i64(-1L) }), content="feffffff")
  inspect(
    wrote(fn(w) { w.write_tagged_i64(1_073_741_823L) }),
    content="feffff7f",
  )
  inspect(
    wrote(fn(w) { w.write_tagged_i64(1_073_741_824L) }),
    content="010000004000000000",
  )
  inspect(wrote(fn(w) { w.write_tagged_u64(0UL) }), content="00000000")
  inspect(
    wrote(fn(w) { w.write_tagged_u64(2_147_483_647UL) }),
    content="feffffff",
  )
  inspect(
    wrote(fn(w) { w.write_tagged_u64(2_147_483_648UL) }),
    content="010000008000000000",
  )
}

///|
test "a string is a header of size and encoding, then the bytes" {
  inspect(wrote(fn(w) { w.write_string("") }), content="02")
  inspect(wrote(fn(w) { w.write_string("ab") }), content="0a6162")
  inspect(wrote(fn(w) { w.write_string("世界") }), content="1ae4b896e7958c")
}

///|
test "the string header is one byte while it fits in seven bits" {
  let short = repeated('x', 31)
  inspect(
    wrote(fn(w) { w.write_string(short) }).has_prefix("7e"),
    content="true",
  )
  let long = repeated('x', 32)
  inspect(
    wrote(fn(w) { w.write_string(long) }).has_prefix("8201"),
    content="true",
  )
}

///|
test "binary is a length and then the bytes" {
  let two = @moonfory.unhex("6162")
  inspect(wrote(fn(w) { w.write_binary(two) }), content="026162")
  let none = @moonfory.unhex("")
  inspect(wrote(fn(w) { w.write_binary(none) }), content="00")
}

///|
test "a type ID is one byte, and a user type is followed by its ID" {
  inspect(
    wrote(fn(w) { w.write_type_id(@moonfory.TypeId::String) }),
    content="15",
  )
  inspect(
    wrote(fn(w) { w.write_user_type(@moonfory.TypeId::Struct, 1) }),
    content="1b01",
  )
  inspect(
    wrote(fn(w) { w.write_user_type(@moonfory.TypeId::Struct, 300) }),
    content="1bac02",
  )
}

///|
test "the null flag, and what a reference writes" {
  inspect(wrote(fn(w) { w.write_null_flag(true) }), content="fd")
  inspect(wrote(fn(w) { w.write_null_flag(false) }), content="ff")
  inspect(wrote(fn(w) { ignore(w.write_tracked(7)) }), content="00")
  inspect(
    wrote(fn(w) {
      ignore(w.write_tracked(7))
      ignore(w.write_tracked(7))
    }),
    content="00fe00",
  )
}
