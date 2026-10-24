// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A value, written and read back: the answer is the value itself.
fn round_trip(v : @lib.Value) -> Bool raise {
  let bytes = @lib.dumps(v)
  let back : @lib.Value = @lib.loads(bytes)
  back == v
}

///|
test "every cross-language value comes back out of the bytes it went into" {
  let values = [
    @lib.Value::Null,
    @lib.Value::Bool(true),
    @lib.Value::Bool(false),
    @lib.Value::Int(0L),
    @lib.Value::Int(-1L),
    @lib.Value::Int(9_223_372_036_854_775_807L),
    @lib.Value::Int(-9_223_372_036_854_775_808L),
    @lib.Value::UInt(0UL),
    @lib.Value::UInt(18_446_744_073_709_551_615UL),
    @lib.Value::Float(1.5),
    @lib.Value::Float(-0.0),
    @lib.Value::Str(""),
    @lib.Value::Str("ab"),
    @lib.Value::Str("世界"),
    @lib.Value::Binary(@lib.unhex("")),
    @lib.Value::Binary(@lib.unhex("6162")),
    @lib.Value::List(@lib.TypeId::List, []),
    @lib.Value::List(@lib.TypeId::Set, []),
    @lib.Value::List(@lib.TypeId::List, [
      @lib.Value::Int(1L),
      @lib.Value::Str("b"),
    ]),
    @lib.Value::List(@lib.TypeId::List, [@lib.Value::Null, @lib.Value::Int(1L)]),
    @lib.Value::Map([]),
    @lib.Value::Map([(@lib.Value::Str("a"), @lib.Value::Int(1L))]),
    @lib.Value::Map([(@lib.Value::Str("a"), @lib.Value::Null)]),
    @lib.Value::Timestamp(1L, 2),
    @lib.Value::Timestamp(-1L, 0),
    @lib.Value::Date(0L),
    @lib.Value::Date(-1L),
    @lib.Value::Duration(1L, 999_999_999),
    @lib.Value::Duration(-1L, 0),
    @lib.Value::Decimal(0, BigInt::from_int64(0L)),
    @lib.Value::Decimal(2, BigInt::from_int64(-12345L)),
    @lib.Value::Enum(3, 7),
  ]
  for v in values {
    inspect(round_trip(v), content="true")
  }
}

///|
test "a decimal is written small when it fits, and as bytes when it does not" {
  let small = @lib.dumps(@lib.Value::Decimal(2, BigInt::from_int64(-12345L)))
  inspect(@lib.hex(small), content="01ff2804e28103")
  let big = BigInt::from_int64(4_611_686_018_427_387_903L) *
    BigInt::from_int64(1000L)
  let wide = @lib.dumps(@lib.Value::Decimal(0, big))
  let back : @lib.Value = @lib.loads(wide)
  inspect(back, content="Decimal(0, 4611686018427387903000)")
}

///|
test "a list with nothing in it writes no header, having nothing to say" {
  inspect(
    @lib.hex(@lib.dumps(@lib.Value::List(@lib.TypeId::List, []))),
    content="01ff1600",
  )
  inspect(@lib.hex(@lib.dumps(@lib.Value::Map([]))), content="01ff1800")
}

///|
test "a list with a nothing in it says so, one flag per element" {
  let bytes = @lib.dumps(
    @lib.Value::List(@lib.TypeId::List, [@lib.Value::Null, @lib.Value::Int(1L)]),
  )
  inspect(@lib.hex(bytes), content="01ff16020a06fdff0100000000000000")
}

///|
test "a struct is read by the schema its user type ID names" {
  let point = @lib.StructMeta::new("Point", 1, [
    @lib.FieldMeta::new("x", @lib.TypeId::Int32),
    @lib.FieldMeta::new("y", @lib.TypeId::Int32),
  ])
  let v = @lib.Value::Struct(point, [
    ("x", @lib.Value::Int(1L)),
    ("y", @lib.Value::Int(2L)),
  ])
  let bytes = @lib.dumps(v)
  inspect(@lib.hex(bytes), content="01ff1b010100000002000000")
  let back : @lib.Value = @lib.loads(bytes, schemas=[point])
  inspect(back == v, content="true")
}

///|
test "a struct without its schema is refused rather than guessed at" {
  let point = @lib.StructMeta::new("Point", 1, [
    @lib.FieldMeta::new("x", @lib.TypeId::Int32),
  ])
  let bytes = @lib.dumps(
    @lib.Value::Struct(point, [("x", @lib.Value::Int(1L))]),
  )
  let outcome = try {
    let _ : @lib.Value = @lib.loads(bytes)
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
  let mixed = @lib.StructMeta::new("Mixed", 2, [
    @lib.FieldMeta::new("small", @lib.TypeId::Int8),
    @lib.FieldMeta::new("wide", @lib.TypeId::Int64),
  ])
  let bytes = @lib.dumps(
    @lib.Value::Struct(mixed, [
      ("small", @lib.Value::Int(1L)),
      ("wide", @lib.Value::Int(1L)),
    ]),
  )
  inspect(@lib.hex(bytes), content="01ff1b02010000000000000001")
}

///|
test "a nullable field carries a flag, and sorts after one that cannot be absent" {
  let nullable = @lib.StructMeta::new("Maybe", 3, [
    @lib.FieldMeta::new("a", @lib.TypeId::Int32, nullable=true),
    @lib.FieldMeta::new("b", @lib.TypeId::Int32),
  ])
  let bytes = @lib.dumps(
    @lib.Value::Struct(nullable, [
      ("a", @lib.Value::Int(7L)),
      ("b", @lib.Value::Int(8L)),
    ]),
  )
  inspect(@lib.hex(bytes), content="01ff1b0308000000ff07000000")
}
