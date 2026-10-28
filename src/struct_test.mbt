// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The names of a struct's fields in the order they go out on the wire.
fn order(fields : Array[@moonfory.FieldMeta]) -> String {
  let meta = @moonfory.StructMeta::new("T", 1, fields)
  let out = StringBuilder()
  let mut first = true
  for f in meta.ordered() {
    if !first {
      out.write_char(',')
    }
    out.write_string(f.name())
    first = false
  }
  out.to_string()
}

///|
test "a field's identifier is its tag when it has one, and its name otherwise" {
  inspect(
    @moonfory.FieldMeta::new("userName", @moonfory.TypeId::Int32).identifier(),
    content="user_name",
  )
  inspect(
    @moonfory.FieldMeta::new("HTTPServer", @moonfory.TypeId::Int32).identifier(),
    content="http_server",
  )
  inspect(
    @moonfory.FieldMeta::new("userName", @moonfory.TypeId::Int32, tag=Some(3)).identifier(),
    content="3",
  )
}

///|
test "a name that is already snake_case is its own identifier" {
  inspect(
    @moonfory.FieldMeta::new("already_snake", @moonfory.TypeId::Int32).identifier(),
    content="already_snake",
  )
}

///|
test "primitives that cannot be absent come first, then those that can, then the rest" {
  inspect(
    order([
      @moonfory.FieldMeta::new("text", @moonfory.TypeId::String),
      @moonfory.FieldMeta::new("maybe", @moonfory.TypeId::Int32, nullable=true),
      @moonfory.FieldMeta::new("sure", @moonfory.TypeId::Int32),
    ]),
    content="sure,maybe,text",
  )
}

///|
test "a fixed-width integer goes before a compressed one, whatever their widths" {
  inspect(
    order([
      @moonfory.FieldMeta::new("compressed", @moonfory.TypeId::VarInt64),
      @moonfory.FieldMeta::new("fixed", @moonfory.TypeId::Int8),
    ]),
    content="fixed,compressed",
  )
}

///|
test "within the fixed widths, the widest goes first" {
  inspect(
    order([
      @moonfory.FieldMeta::new("one", @moonfory.TypeId::Int8),
      @moonfory.FieldMeta::new("eight", @moonfory.TypeId::Int64),
      @moonfory.FieldMeta::new("four", @moonfory.TypeId::Int32),
      @moonfory.FieldMeta::new("two", @moonfory.TypeId::Int16),
    ]),
    content="eight,four,two,one",
  )
}

///|
test "of two fields the same width, the lower type ID goes first" {
  inspect(
    order([
      @moonfory.FieldMeta::new("b", @moonfory.TypeId::Float32),
      @moonfory.FieldMeta::new("a", @moonfory.TypeId::Int32),
    ]),
    content="a,b",
  )
  inspect(
    order([
      @moonfory.FieldMeta::new("a", @moonfory.TypeId::Int32),
      @moonfory.FieldMeta::new("b", @moonfory.TypeId::UInt32),
    ]),
    content="a,b",
  )
}

///|
test "a tagged field sorts before every untagged one" {
  inspect(
    order([
      @moonfory.FieldMeta::new("zebra", @moonfory.TypeId::Int32),
      @moonfory.FieldMeta::new("apple", @moonfory.TypeId::Int32, tag=Some(0)),
    ]),
    content="apple,zebra",
  )
  inspect(
    order([
      @moonfory.FieldMeta::new("b", @moonfory.TypeId::Int32, tag=Some(2)),
      @moonfory.FieldMeta::new("a", @moonfory.TypeId::Int32, tag=Some(1)),
    ]),
    content="a,b",
  )
}

///|
test "the fields that are not primitives go by identifier alone" {
  inspect(
    order([
      @moonfory.FieldMeta::new("zebra", @moonfory.TypeId::String),
      @moonfory.FieldMeta::new("apple", @moonfory.TypeId::List),
      @moonfory.FieldMeta::new("mango", @moonfory.TypeId::Binary),
    ]),
    content="apple,mango,zebra",
  )
}

///|
test "a field is found by name, which is how a reader reads the order it wants" {
  let meta = @moonfory.StructMeta::new("T", 1, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::Int32),
  ])
  let found = meta.find("x")
  inspect(
    found == Some(@moonfory.FieldMeta::new("x", @moonfory.TypeId::Int32)),
    content="true",
  )
  inspect(meta.find("y") == None, content="true")
}
