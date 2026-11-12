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
    @moonfory.FieldMeta::new("userName", @moonfory.TypeId::Int32, tag=3).identifier(),
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
      @moonfory.FieldMeta::new("apple", @moonfory.TypeId::Int32, tag=0),
    ]),
    content="apple,zebra",
  )
  inspect(
    order([
      @moonfory.FieldMeta::new("b", @moonfory.TypeId::Int32, tag=2),
      @moonfory.FieldMeta::new("a", @moonfory.TypeId::Int32, tag=1),
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

///|
/// The three members a description has no word for are given when the field has
/// one and left out when it does not: `tag=3`, not `tag=Some(3)`, and no
/// `Some(None)` to mean the field simply has no tag.
test "a member is passed at the call, and absence is the argument left out" {
  let plain = @moonfory.FieldMeta::new("plain", @moonfory.TypeId::Int32)
  inspect(plain.tag == None, content="true")
  inspect(plain.child == None, content="true")
  inspect(plain.element == None, content="true")
  inspect(plain.identifier(), content="plain")

  let point = @moonfory.StructMeta::new("Point", 100, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::VarInt32),
  ])
  let given = @moonfory.FieldMeta::new(
    "home",
    @moonfory.TypeId::Struct,
    tag=7,
    child=point,
    element=@moonfory.TypeId::String,
  )
  inspect(given.tag == Some(7), content="true")
  inspect(given.child == Some(point), content="true")
  inspect(given.element == Some(@moonfory.TypeId::String), content="true")
  // A field with a tag is identified by the tag, whatever its name is.
  inspect(given.identifier(), content="7")
}

///|
test "the same three members, from a description" {
  let desc = @moonmodel.Field::new("id", @moonmodel.Int)
  let bare = @moonfory.FieldMeta::from(desc)
  inspect(bare.tag == None, content="true")
  inspect(bare.child == None, content="true")
  inspect(bare.element == None, content="true")
  inspect(bare.ty.to_string(), content="VarInt32")

  let point = @moonfory.StructMeta::new("Point", 100, [])
  let given = @moonfory.FieldMeta::from(
    desc,
    tag=3,
    track_ref=true,
    child=point,
    element=@moonfory.TypeId::VarInt32,
  )
  inspect(given.tag == Some(3), content="true")
  inspect(given.child == Some(point), content="true")
  inspect(given.element == Some(@moonfory.TypeId::VarInt32), content="true")
  inspect(given.track_ref, content="true")
}
