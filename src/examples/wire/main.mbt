// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One message per class, as `name` and the bytes this package wrote for it, in
/// hexadecimal — the input of `scripts/check_peer_reads.py` and
/// `scripts/check_peer_reads/main.go`.
///
///     moon run src/examples/wire
///
/// The classes are the ones another language has a type for, so a peer can read
/// each message into that type and say whether it holds the value below. A
/// width is chosen rather than left to the value: `42` goes out as `INT32`
/// because the field of a peer is an `int32`, and a peer that expects one width
/// refuses another.
///
/// The two `varint` cases are the same numbers in the compressed form, which is
/// the form a Go or a Java peer reads for its own `int32` and `int64`. A value
/// alone picks the fixed width (`Int` answers `INT32`); a caller that knows the
/// peer has to say which, and these two do it through the writer.
#coverage.skip
fn main raise {
  let point = @moonfory.StructMeta::new("Point", 100, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new("y", @moonfory.TypeId::VarInt32),
  ])
  let cases : Array[(String, Bytes)] = [
    ("bool", @moonfory.dumps(true)),
    ("int32", @moonfory.dumps(42)),
    ("int64", @moonfory.dumps(42L)),
    (
      "varint32",
      named(@moonfory.TypeId::VarInt32, fn(w) { w.write_var_i32(42) }),
    ),
    (
      "varint64",
      named(@moonfory.TypeId::VarInt64, fn(w) { w.write_var_i64(42L) }),
    ),
    ("float64", @moonfory.dumps(1.5)),
    ("string", @moonfory.dumps("世界")),
    ("binary", @moonfory.dumps(b"ab")),
    ("list_int", @moonfory.dumps([1, 2, 3])),
    ("list_str", @moonfory.dumps(["a", "b"])),
    ("map_str_int", @moonfory.dumps({ "a": 1 })),
    (
      "int32_array",
      @moonfory.dumps(
        @moonfory.Value::List(@moonfory.TypeId::Int32Array, [
          @moonfory.Value::Int(1L),
          @moonfory.Value::Int(2L),
          @moonfory.Value::Int(3L),
        ]),
      ),
    ),
    (
      "decimal",
      @moonfory.dumps(
        @moonfory.Value::Decimal(2, @bigint.BigInt::from_int64(12345L)),
      ),
    ),
    ("timestamp", @moonfory.dumps(@moonfory.moment_of_parts(1L, 500_000_000))),
    ("date", @moonfory.dumps(@moonfory.date_of_days(1L))),
    ("duration", @moonfory.dumps(@moonfory.span_of_parts(90L, 500_000))),
    (
      "struct_point",
      @moonfory.dumps(
        @moonfory.Value::Struct(point, [
          ("x", @moonfory.Value::Int(1L)),
          ("y", @moonfory.Value::Int(2L)),
        ]),
      ),
    ),
  ]
  for pair in cases {
    let (name, bytes) = pair
    println(name + "\t" + @base16.encode(bytes))
  }
}

///|
/// A message whose type the caller names: the head, the root's flag, the type
/// ID, then whatever the body writes — which is what `dumps` does when the
/// value can answer for its own type, spelled out here for a value that cannot.
fn named(
  ty : @moonfory.TypeId,
  body : (@moonfory.Writer) -> Unit raise,
) -> Bytes raise {
  let w = @moonfory.Writer::new()
  w.write_head()
  w.write_byte(0xFF)
  w.write_type_id(ty)
  body(w)
  w.bytes()
}
