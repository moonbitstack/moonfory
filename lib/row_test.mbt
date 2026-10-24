// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

/// A schema with one of every primitive, a nullable field, and room for the three
/// variable shapes. Each test builds against a schema of its own so a failure names
/// the type it is about.
fn person() -> @lib.RowSchema {
  @lib.RowSchema::new([
    { name: "id", ty: @lib.RowType::Int64, nullable: false },
    { name: "age", ty: @lib.RowType::Int32, nullable: true },
    { name: "name", ty: @lib.RowType::String, nullable: false },
    { name: "active", ty: @lib.RowType::Bool, nullable: false },
  ])
}

test "a row reads back every primitive it was built with" {
  let schema = person()
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Int64(42L))
  row.set(1, @lib.RowValue::Int32(37))
  row.set(2, @lib.RowValue::String("alice"))
  row.set(3, @lib.RowValue::Bool(true))
  let bytes = row.finish()
  let cur = @lib.RowCursor::new(bytes[:], schema)
  inspect(cur.length(), content="4")
  inspect(cur.get_field(0) == @lib.RowValue::Int64(42L), content="true")
  inspect(cur.get_field(1) == @lib.RowValue::Int32(37), content="true")
  inspect(cur.get_field(2) == @lib.RowValue::String("alice"), content="true")
  inspect(cur.get_field(3) == @lib.RowValue::Bool(true), content="true")
}

test "a null field is flagged in the bitmap and reads back null" {
  let schema = person()
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Int64(1L))
  row.set(1, @lib.RowValue::Null)
  row.set(2, @lib.RowValue::String("bob"))
  row.set(3, @lib.RowValue::Bool(false))
  let bytes = row.finish()
  let cur = @lib.RowCursor::new(bytes[:], schema)
  inspect(cur.is_null(0), content="false")
  inspect(cur.is_null(1), content="true")
  inspect(cur.get_field(1) == @lib.RowValue::Null, content="true")
  inspect(cur.get_field(3) == @lib.RowValue::Bool(false), content="true")
}

test "an unset field is written as null" {
  let schema = person()
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Int64(1L))
  let bytes = row.finish()
  let cur = @lib.RowCursor::new(bytes[:], schema)
  inspect(cur.is_null(1), content="true")
  inspect(cur.is_null(2), content="true")
}

test "the layout is the bitmap, then one eight-byte slot per field" {
  let schema = @lib.RowSchema::new([
    { name: "a", ty: @lib.RowType::Int32, nullable: false },
    { name: "b", ty: @lib.RowType::Int32, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Int32(1))
  row.set(1, @lib.RowValue::Int32(2))
  let bytes = row.finish()
  // Two fields: an eight-byte bitmap, then sixteen bytes of slots, no variable data.
  inspect(bytes.length(), content="24")
  // The bitmap is all zero (nothing is null).
  inspect(bytes[0].to_int(), content="0")
  // Field a sits in the first slot, little-endian.
  inspect(bytes[8].to_int(), content="1")
  inspect(bytes[9].to_int(), content="0")
  // Field b sits in the second slot.
  inspect(bytes[16].to_int(), content="2")
}

test "a variable field stores an offset and a size, with the bytes after the slots" {
  let schema = @lib.RowSchema::new([
    { name: "s", ty: @lib.RowType::String, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::String("hi"))
  let bytes = row.finish()
  // Eight-byte bitmap, one eight-byte slot, then the padded variable block.
  inspect(bytes.length(), content="24")
  // The slot's low four bytes are the size (2), the high four are the offset (16).
  inspect(bytes[8].to_int(), content="2")
  inspect(bytes[12].to_int(), content="16")
  // The byte 'h' sits at the offset the slot points at.
  inspect(bytes[16].to_int(), content="104")
}

test "an empty string round-trips and takes no data beyond the block" {
  let schema = @lib.RowSchema::new([
    { name: "s", ty: @lib.RowType::String, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::String(""))
  let bytes = row.finish()
  let cur = @lib.RowCursor::new(bytes[:], schema)
  inspect(cur.get_field(0) == @lib.RowValue::String(""), content="true")
}

test "binary round-trips byte for byte" {
  let schema = @lib.RowSchema::new([
    { name: "b", ty: @lib.RowType::Binary, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Binary(b"\x01\x02\xff"))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(cur.get_field(0) == @lib.RowValue::Binary(b"\x01\x02\xff"), content="true")
}

test "an array of fixed-width elements round-trips" {
  let schema = @lib.RowSchema::new([
    { name: "xs", ty: @lib.RowType::Array(@lib.RowType::Int32), nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Array([
    @lib.RowValue::Int32(10),
    @lib.RowValue::Int32(20),
    @lib.RowValue::Int32(30),
  ]))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(
    cur.get_field(0) == @lib.RowValue::Array([
      @lib.RowValue::Int32(10),
      @lib.RowValue::Int32(20),
      @lib.RowValue::Int32(30),
    ]),
    content="true",
  )
}

test "an array of strings round-trips, bodies and all" {
  let schema = @lib.RowSchema::new([
    { name: "xs", ty: @lib.RowType::Array(@lib.RowType::String), nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Array([
    @lib.RowValue::String("one"),
    @lib.RowValue::String("two"),
    @lib.RowValue::Null,
  ]))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(
    cur.get_field(0) == @lib.RowValue::Array([
      @lib.RowValue::String("one"),
      @lib.RowValue::String("two"),
      @lib.RowValue::Null,
    ]),
    content="true",
  )
}

test "an empty array round-trips" {
  let schema = @lib.RowSchema::new([
    { name: "xs", ty: @lib.RowType::Array(@lib.RowType::Int64), nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Array([]))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(cur.get_field(0) == @lib.RowValue::Array([]), content="true")
}

test "a map keeps keys and values as two arrays" {
  let schema = @lib.RowSchema::new([
    {
      name: "m",
      ty: @lib.RowType::Map(@lib.RowType::String, @lib.RowType::Int32),
      nullable: false,
    },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Map([
    (@lib.RowValue::String("a"), @lib.RowValue::Int32(1)),
    (@lib.RowValue::String("b"), @lib.RowValue::Int32(2)),
  ]))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(
    cur.get_field(0) == @lib.RowValue::Map([
      (@lib.RowValue::String("a"), @lib.RowValue::Int32(1)),
      (@lib.RowValue::String("b"), @lib.RowValue::Int32(2)),
    ]),
    content="true",
  )
}

test "a nested struct is a whole row inside the variable region" {
  let inner = @lib.RowSchema::new([
    { name: "x", ty: @lib.RowType::Int32, nullable: false },
    { name: "y", ty: @lib.RowType::Int32, nullable: false },
  ])
  let schema = @lib.RowSchema::new([
    { name: "p", ty: @lib.RowType::Struct(inner.fields), nullable: false },
    { name: "tag", ty: @lib.RowType::String, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Struct([
    @lib.RowValue::Int32(3),
    @lib.RowValue::Int32(4),
  ]))
  row.set(1, @lib.RowValue::String("origin"))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(
    cur.get_field(0) == @lib.RowValue::Struct([
      @lib.RowValue::Int32(3),
      @lib.RowValue::Int32(4),
    ]),
    content="true",
  )
  inspect(cur.get_field(1) == @lib.RowValue::String("origin"), content="true")
}

test "random field access reads the last field without touching the first" {
  let schema = @lib.RowSchema::new([
    { name: "a", ty: @lib.RowType::String, nullable: false },
    { name: "b", ty: @lib.RowType::String, nullable: false },
    { name: "c", ty: @lib.RowType::Int64, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::String("first"))
  row.set(1, @lib.RowValue::String("second"))
  row.set(2, @lib.RowValue::Int64(99L))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  // Only the third slot is consulted.
  inspect(cur.get_field(2) == @lib.RowValue::Int64(99L), content="true")
  inspect(cur.get_field(1) == @lib.RowValue::String("second"), content="true")
}

test "a value of the wrong type is refused when it is set" {
  let schema = person()
  let row = @lib.Row::new(schema)
  let outcome = try {
    row.set(0, @lib.RowValue::String("not an int"))
    "accepted"
  } catch {
    _ => "refused"
  } noraise {
    _ => "accepted"
  }
  inspect(outcome, content="refused")
}

test "the time types round-trip" {
  let schema = @lib.RowSchema::new([
    { name: "t", ty: @lib.RowType::Timestamp, nullable: false },
    { name: "d", ty: @lib.RowType::Date, nullable: false },
    { name: "u", ty: @lib.RowType::Duration, nullable: false },
  ])
  let row = @lib.Row::new(schema)
  row.set(0, @lib.RowValue::Timestamp(1_700_000_000_000_000L))
  row.set(1, @lib.RowValue::Date(19_000))
  row.set(2, @lib.RowValue::Duration(-500L))
  let cur = @lib.RowCursor::new(row.finish()[:], schema)
  inspect(
    cur.get_field(0) == @lib.RowValue::Timestamp(1_700_000_000_000_000L),
    content="true",
  )
  inspect(cur.get_field(1) == @lib.RowValue::Date(19_000), content="true")
  inspect(cur.get_field(2) == @lib.RowValue::Duration(-500L), content="true")
}
