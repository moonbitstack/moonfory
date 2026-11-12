// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The two ends of the wire, one primitive at a time: what a fixed width does on
// a little-endian machine, what a varint does with a small number and a large
// one, and which of the two writes a length in front. The classes of message
// are covered elsewhere; this is the layer under them.

///|
/// One primitive, as the writer puts it on the wire.
fn written(body : (@moonfory.Writer) -> Unit) -> String {
  let w = @moonfory.Writer::new()
  body(w)
  @base16.encode(w.bytes())
}

///|
/// A reader over those bytes.
fn reader(bytes : String) -> @moonfory.Reader raise {
  @moonfory.Reader::new(@base16.decode(bytes))
}

///|
test "a fixed width is little-endian" {
  inspect(written(fn(w) { w.write_u8(0x7f) }), content="7f")
  inspect(written(fn(w) { w.write_i8(-2) }), content="fe")
  inspect(written(fn(w) { w.write_u16(0x1234) }), content="3412")
  inspect(written(fn(w) { w.write_i16(-2) }), content="feff")
  inspect(written(fn(w) { w.write_u32(0x12345678U) }), content="78563412")
  inspect(written(fn(w) { w.write_i32(-2) }), content="feffffff")
  inspect(
    written(fn(w) { w.write_u64(0x0102030405060708UL) }),
    content="0807060504030201",
  )
  inspect(written(fn(w) { w.write_i64(-2L) }), content="feffffffffffffff")
  inspect(written(fn(w) { w.write_f32(1.5) }), content="0000c03f")
  inspect(written(fn(w) { w.write_f64(1.5) }), content="000000000000f83f")
}

///|
test "each fixed width reads back as the value that was written" {
  let r = reader("3412feff78563412feffffff0807060504030201")
  inspect(r.read_u16(), content="4660")
  inspect(r.read_i16(), content="-2")
  inspect(r.read_u32().reinterpret_as_int().to_int64(), content="305419896")
  inspect(r.read_i32(), content="-2")
  inspect(r.read_u64().reinterpret_as_int64(), content="72623859790382856")
  inspect(r.is_done(), content="true")
}

///|
/// A signed small number is folded onto an unsigned one before it becomes a
/// varint, so `-1` is one byte and `-2` is one byte as well.
test "a small number is one byte, whatever its sign" {
  inspect(written(fn(w) { w.write_var_u32(1U) }), content="01")
  inspect(written(fn(w) { w.write_var_u32(300U) }), content="ac02")
  inspect(written(fn(w) { w.write_var_i32(1) }), content="02")
  inspect(written(fn(w) { w.write_var_i32(-1) }), content="01")
  inspect(written(fn(w) { w.write_var_i32(-2) }), content="03")
  inspect(written(fn(w) { w.write_var_i64(-1L) }), content="01")
  inspect(
    written(fn(w) { w.write_var_u64(0xffffffffffffffffUL) }),
    content="ffffffffffffffffff01",
  )
}

///|
test "a varint reads back as the value that was written" {
  let r = reader("ac02")
  inspect(r.read_var_u32().reinterpret_as_int().to_int64(), content="300")
  let signed = reader("03")
  inspect(signed.read_var_i32(), content="-2")
  let wide = reader("ffffffffffffffffff01")
  inspect(wide.read_var_u64().reinterpret_as_int64(), content="-1")
}

///|
/// `read_var_u36` is the string header's reader: one byte when the value fits,
/// and the general varint when it does not.
test "a thirty-six-bit varint crosses from one byte to two" {
  let small = reader("7f")
  inspect(small.read_var_u36().reinterpret_as_int64(), content="127")
  let large = reader("8001")
  inspect(large.read_var_u36().reinterpret_as_int64(), content="128")
  inspect(large.remaining(), content="0")
}

///|
/// A value with a length in front, and the same value without one.
test "a binary counts itself, and raw bytes do not" {
  inspect(written(fn(w) { w.write_binary(b"ab") }), content="026162")
  inspect(written(fn(w) { w.write_bytes(b"ab") }), content="6162")
  let counted = reader("026162")
  inspect(@base16.encode(counted.read_binary()), content="6162")
  let raw = reader("6162")
  inspect(@base16.encode(raw.read_bytes(2)), content="6162")
}

///|
/// A string is a length and an encoding in one varint, then the bytes.
test "a string says how long it is and which encoding it is in" {
  inspect(written(fn(w) { w.write_string("ab") }), content="0a6162")
  // An empty string still says which encoding it is in: UTF-8, so `2`.
  inspect(written(fn(w) { w.write_string("") }), content="02")
  let r = reader("0a6162")
  inspect(r.read_string(), content="ab")
}

///|
test "a type ID is one byte, and a user type carries its number after it" {
  inspect(
    written(fn(w) { w.write_type_id(@moonfory.TypeId::Int32) }),
    content="04",
  )
  inspect(
    written(fn(w) { w.write_user_type(@moonfory.TypeId::Struct, 100) }),
    content="1b64",
  )
  let r = reader("1b64")
  let (ty, user) = r.read_user_type()
  inspect(ty.to_string(), content="Struct")
  inspect(user, content="100")
}

///|
/// Reading past the end is a refusal with the offset, not a value.
test "a read past the end names where it stopped" {
  let empty = reader("")
  let outcome = try {
    ignore(empty.read_u16())
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome, content="Truncated(at=0, want=2, got=0)")
  let short = reader("61")
  let outcome = try {
    ignore(short.read_bytes(2))
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome, content="Truncated(at=0, want=2, got=1)")
}

///|
/// A negative count is not a count.
test "a negative length is refused before it is used" {
  let r = reader("6162")
  let outcome = try {
    ignore(r.read_bytes(-1))
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome.has_prefix("TooLarge"), content="true")
}

///|
/// Where the reader is, where it can go, and whether it is finished.
test "a reader knows where it is" {
  let r = reader("61626364")
  inspect(r.offset(), content="0")
  inspect(r.remaining(), content="4")
  ignore(r.read_byte())
  inspect(r.offset(), content="1")
  inspect(r.remaining(), content="3")
  r.seek(3)
  inspect(r.remaining(), content="1")
  inspect(r.is_done(), content="false")
  r.seek(4)
  inspect(r.is_done(), content="true")
}

///|
/// The kinds that carry a user's own type ID, and the ones that do not.
test "the types a user names by ID are the ones that carry one" {
  for
    ty in [
      @moonfory.TypeId::Struct,
      @moonfory.TypeId::CompatibleStruct,
      @moonfory.TypeId::NamedStruct,
      @moonfory.TypeId::NamedCompatibleStruct,
      @moonfory.TypeId::Enum,
    ] {
    inspect(ty.is_named_by_id(), content="true")
  }
  for
    ty in [
      @moonfory.TypeId::Int32,
      @moonfory.TypeId::List,
      @moonfory.TypeId::Map,
      @moonfory.TypeId::Binary,
    ] {
    inspect(ty.is_named_by_id(), content="false")
  }
}
