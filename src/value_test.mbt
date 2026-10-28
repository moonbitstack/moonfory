// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A value, written and read back: the answer is the value itself.
fn round_trip(v : @moonfory.Value) -> Bool raise {
  let bytes = @moonfory.dumps(v)
  let back : @moonfory.Value = @moonfory.loads(bytes)
  back == v
}

///|
test "every cross-language value comes back out of the bytes it went into" {
  let values = [
    @moonfory.Value::Null,
    @moonfory.Value::Bool(true),
    @moonfory.Value::Bool(false),
    @moonfory.Value::Int(0L),
    @moonfory.Value::Int(-1L),
    @moonfory.Value::Int(9_223_372_036_854_775_807L),
    @moonfory.Value::Int(-9_223_372_036_854_775_808L),
    @moonfory.Value::UInt(0UL),
    @moonfory.Value::UInt(18_446_744_073_709_551_615UL),
    @moonfory.Value::Float(1.5),
    @moonfory.Value::Float(-0.0),
    @moonfory.Value::Str(""),
    @moonfory.Value::Str("ab"),
    @moonfory.Value::Str("世界"),
    @moonfory.Value::Binary(@base16.decode("")),
    @moonfory.Value::Binary(@base16.decode("6162")),
    @moonfory.Value::List(@moonfory.TypeId::List, []),
    @moonfory.Value::List(@moonfory.TypeId::Set, []),
    @moonfory.Value::List(@moonfory.TypeId::List, [
      @moonfory.Value::Int(1L),
      @moonfory.Value::Str("b"),
    ]),
    @moonfory.Value::List(@moonfory.TypeId::List, [
      @moonfory.Value::Null,
      @moonfory.Value::Int(1L),
    ]),
    @moonfory.Value::Map([]),
    @moonfory.Value::Map([(@moonfory.Value::Str("a"), @moonfory.Value::Int(1L))]),
    @moonfory.Value::Map([(@moonfory.Value::Str("a"), @moonfory.Value::Null)]),
    @moonfory.Value::Timestamp(1L, 2),
    @moonfory.Value::Timestamp(-1L, 0),
    @moonfory.Value::Date(0L),
    @moonfory.Value::Date(-1L),
    @moonfory.Value::Duration(1L, 999_999_999),
    @moonfory.Value::Duration(-1L, 0),
    @moonfory.Value::Decimal(0, BigInt::from_int64(0L)),
    @moonfory.Value::Decimal(2, BigInt::from_int64(-12345L)),
    @moonfory.Value::Enum(3, 7),
  ]
  for v in values {
    inspect(round_trip(v), content="true")
  }
}

///|
test "a decimal is written small when it fits, and as bytes when it does not" {
  let small = @moonfory.dumps(
    @moonfory.Value::Decimal(2, BigInt::from_int64(-12345L)),
  )
  inspect(@base16.encode(small), content="01ff2804e28103")
  let big = BigInt::from_int64(4_611_686_018_427_387_903L) *
    BigInt::from_int64(1000L)
  let wide = @moonfory.dumps(@moonfory.Value::Decimal(0, big))
  let back : @moonfory.Value = @moonfory.loads(wide)
  inspect(back, content="Decimal(0, 4611686018427387903000)")
}

///|
test "a list with nothing in it writes no header, having nothing to say" {
  inspect(
    @base16.encode(
      @moonfory.dumps(@moonfory.Value::List(@moonfory.TypeId::List, [])),
    ),
    content="01ff1600",
  )
  inspect(
    @base16.encode(@moonfory.dumps(@moonfory.Value::Map([]))),
    content="01ff1800",
  )
}

///|
test "a list with a nothing in it says so, one flag per element" {
  let bytes = @moonfory.dumps(
    @moonfory.Value::List(@moonfory.TypeId::List, [
      @moonfory.Value::Null,
      @moonfory.Value::Int(1L),
    ]),
  )
  inspect(@base16.encode(bytes), content="01ff16020a06fdff0100000000000000")
}

///|
test "a struct is read by the schema its user type ID names" {
  let point = @moonfory.StructMeta::new("Point", 1, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::Int32),
    @moonfory.FieldMeta::new("y", @moonfory.TypeId::Int32),
  ])
  let v = @moonfory.Value::Struct(point, [
    ("x", @moonfory.Value::Int(1L)),
    ("y", @moonfory.Value::Int(2L)),
  ])
  let bytes = @moonfory.dumps(v)
  inspect(@base16.encode(bytes), content="01ff1b0194d631870100000002000000")
  let back : @moonfory.Value = @moonfory.loads(bytes, schemas=[point])
  inspect(back == v, content="true")
}

///|
test "a struct without its schema is refused rather than guessed at" {
  let point = @moonfory.StructMeta::new("Point", 1, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::Int32),
  ])
  let bytes = @moonfory.dumps(
    @moonfory.Value::Struct(point, [("x", @moonfory.Value::Int(1L))]),
  )
  let outcome = try {
    let _ : @moonfory.Value = @moonfory.loads(bytes)
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome, content="Unsupported(kind=struct 1)")
}

///|
test "a field is written in the width its schema names, not its own" {
  let mixed = @moonfory.StructMeta::new("Mixed", 2, [
    @moonfory.FieldMeta::new("small", @moonfory.TypeId::Int8),
    @moonfory.FieldMeta::new("wide", @moonfory.TypeId::Int64),
  ])
  let bytes = @moonfory.dumps(
    @moonfory.Value::Struct(mixed, [
      ("small", @moonfory.Value::Int(1L)),
      ("wide", @moonfory.Value::Int(1L)),
    ]),
  )
  inspect(@base16.encode(bytes), content="01ff1b0247de60d5010000000000000001")
}

///|
test "a nullable field carries a flag, and sorts after one that cannot be absent" {
  let nullable = @moonfory.StructMeta::new("Maybe", 3, [
    @moonfory.FieldMeta::new("a", @moonfory.TypeId::Int32, nullable=true),
    @moonfory.FieldMeta::new("b", @moonfory.TypeId::Int32),
  ])
  let bytes = @moonfory.dumps(
    @moonfory.Value::Struct(nullable, [
      ("a", @moonfory.Value::Int(7L)),
      ("b", @moonfory.Value::Int(8L)),
    ]),
  )
  inspect(@base16.encode(bytes), content="01ff1b031db9061208000000ff07000000")
}
