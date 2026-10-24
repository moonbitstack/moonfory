// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The names of a struct's fields in the order they go out on the wire.
fn order(fields : Array[@lib.FieldMeta]) -> String {
  let meta = @lib.StructMeta::new("T", 1, fields)
  let out = StringBuilder()
  let mut first = true
  for f in meta.ordered() {
    if !first {
      out.write_char(',')
    }
    out.write_string(f.name)
    first = false
  }
  out.to_string()
}

///|
test "a field's identifier is its tag when it has one, and its name otherwise" {
  inspect(
    @lib.FieldMeta::new("userName", @lib.TypeId::Int32).identifier(),
    content="user_name",
  )
  inspect(
    @lib.FieldMeta::new("HTTPServer", @lib.TypeId::Int32).identifier(),
    content="http_server",
  )
  inspect(
    @lib.FieldMeta::new("userName", @lib.TypeId::Int32, tag=Some(3)).identifier(),
    content="3",
  )
}

///|
test "a name that is already snake_case is its own identifier" {
  inspect(
    @lib.FieldMeta::new("already_snake", @lib.TypeId::Int32).identifier(),
    content="already_snake",
  )
}

///|
test "primitives that cannot be absent come first, then those that can, then the rest" {
  inspect(
    order([
      @lib.FieldMeta::new("text", @lib.TypeId::String),
      @lib.FieldMeta::new("maybe", @lib.TypeId::Int32, nullable=true),
      @lib.FieldMeta::new("sure", @lib.TypeId::Int32),
    ]),
    content="sure,maybe,text",
  )
}

///|
test "a fixed-width integer goes before a compressed one, whatever their widths" {
  inspect(
    order([
      @lib.FieldMeta::new("compressed", @lib.TypeId::VarInt64),
      @lib.FieldMeta::new("fixed", @lib.TypeId::Int8),
    ]),
    content="fixed,compressed",
  )
}

///|
test "within the fixed widths, the widest goes first" {
  inspect(
    order([
      @lib.FieldMeta::new("one", @lib.TypeId::Int8),
      @lib.FieldMeta::new("eight", @lib.TypeId::Int64),
      @lib.FieldMeta::new("four", @lib.TypeId::Int32),
      @lib.FieldMeta::new("two", @lib.TypeId::Int16),
    ]),
    content="eight,four,two,one",
  )
}

///|
test "of two fields the same width, the lower type ID goes first" {
  inspect(
    order([
      @lib.FieldMeta::new("b", @lib.TypeId::Float32),
      @lib.FieldMeta::new("a", @lib.TypeId::Int32),
    ]),
    content="a,b",
  )
  inspect(
    order([
      @lib.FieldMeta::new("a", @lib.TypeId::Int32),
      @lib.FieldMeta::new("b", @lib.TypeId::UInt32),
    ]),
    content="a,b",
  )
}

///|
test "a tagged field sorts before every untagged one" {
  inspect(
    order([
      @lib.FieldMeta::new("zebra", @lib.TypeId::Int32),
      @lib.FieldMeta::new("apple", @lib.TypeId::Int32, tag=Some(0)),
    ]),
    content="apple,zebra",
  )
  inspect(
    order([
      @lib.FieldMeta::new("b", @lib.TypeId::Int32, tag=Some(2)),
      @lib.FieldMeta::new("a", @lib.TypeId::Int32, tag=Some(1)),
    ]),
    content="a,b",
  )
}

///|
test "the fields that are not primitives go by identifier alone" {
  inspect(
    order([
      @lib.FieldMeta::new("zebra", @lib.TypeId::String),
      @lib.FieldMeta::new("apple", @lib.TypeId::List),
      @lib.FieldMeta::new("mango", @lib.TypeId::Binary),
    ]),
    content="apple,mango,zebra",
  )
}

///|
test "a field is found by name, which is how a reader reads the order it wants" {
  let meta = @lib.StructMeta::new("T", 1, [
    @lib.FieldMeta::new("x", @lib.TypeId::Int32),
  ])
  let found = meta.find("x")
  inspect(
    found == Some(@lib.FieldMeta::new("x", @lib.TypeId::Int32)),
    content="true",
  )
  inspect(meta.find("y") == None, content="true")
}
