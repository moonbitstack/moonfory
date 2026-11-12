// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A struct described once and used as a codec: what `StructMeta::of` reads out
// of a `@moonmodel.Model`, and the wire the result produces.

///|
/// The field names of a struct value, in the order the value carries them.
fn names_of(value : @moonfory.Value) -> Array[String] {
  match value {
    @moonfory.Struct(_, fields) => fields.map(fn(pair) { pair.0 })
    _ => []
  }
}

///|
/// The description of `Point`, which the tests below use as a child schema.
fn point_model() -> @moonmodel.Model {
  @moonmodel.Model::new("Point", [
    @moonmodel.Field::new("x", @moonmodel.Int),
    @moonmodel.Field::new("y", @moonmodel.Int),
  ])
}

///|
test "the kinds of a description decide the type IDs the fields go out as" {
  let model = @moonmodel.Model::new("Every", [
    @moonmodel.Field::new("flag", @moonmodel.Bool),
    @moonmodel.Field::new("count", @moonmodel.Int),
    @moonmodel.Field::new("large", @moonmodel.Big),
    @moonmodel.Field::new("ratio", @moonmodel.Real),
    @moonmodel.Field::new("label", @moonmodel.Text),
    @moonmodel.Field::new("raw", @moonmodel.Bytes),
    @moonmodel.Field::new("at", @moonmodel.Stamp),
  ])
  let meta = @moonfory.StructMeta::of(model, user=200)
  let types = meta.fields().map(fn(f) { f.ty })
  assert_eq(types, [
    @moonfory.TypeId::Bool,
    @moonfory.TypeId::VarInt32,
    @moonfory.TypeId::VarInt64,
    @moonfory.TypeId::Float64,
    @moonfory.TypeId::String,
    @moonfory.TypeId::Binary,
    @moonfory.TypeId::Timestamp,
  ])
}

///|
test "a description hands the model back, so one definition serves both jobs" {
  let model = point_model()
  let meta = @moonfory.StructMeta::of(model, user=201)
  assert_eq(meta.model(), model)
  assert_eq(meta.name(), "Point")
  assert_eq(meta.user(), 201)
  assert_eq(meta.fields().map(fn(f) { f.name() }), ["x", "y"])
}

///|
test "a list field carries the element type its description names" {
  let model = @moonmodel.Model::new("Tags", [
    @moonmodel.Field::new("labels", @moonmodel.List(@moonmodel.Text)),
    // A list of a kind with no wire type says nothing about its elements, and
    // the header is left to carry the type instead.
    @moonmodel.Field::new("anything", @moonmodel.List(@moonmodel.Any)),
  ])
  let meta = @moonfory.StructMeta::of(model, user=202)
  assert_eq(
    meta.find("labels").unwrap().element,
    Some(@moonfory.TypeId::String),
  )
  assert_eq(meta.find("anything").unwrap().element is None, true)
}

///|
test "a ref field finds its schema by name, and a nested one by its model" {
  let point = @moonfory.StructMeta::of(point_model(), user=203)
  let by_ref = @moonmodel.Model::new("Home", [
    @moonmodel.Field::new("place", @moonmodel.Ref("Point"), nullable=true),
  ])
  let by_nest = @moonmodel.Model::new("Site", [
    @moonmodel.Field::new("place", @moonmodel.Nest(point_model())),
  ])
  let ref_meta = @moonfory.StructMeta::of(by_ref, user=204, children=[point])
  assert_eq(ref_meta.find("place").unwrap().child == Some(point), true)
  let nest_meta = @moonfory.StructMeta::of(by_nest, user=205, children=[point])
  assert_eq(nest_meta.find("place").unwrap().child == Some(point), true)
  // Without the child, the field is one this reader cannot follow.
  let alone = @moonfory.StructMeta::of(by_ref, user=206)
  assert_eq(alone.find("place").unwrap().child is None, true)
}

///|
test "a field named in refs is tracked, and a tag replaces its identifier" {
  let model = @moonmodel.Model::new("Node", [
    @moonmodel.Field::new("val", @moonmodel.Int),
    @moonmodel.Field::new("next", @moonmodel.Ref("Node"), nullable=true),
  ])
  let meta = @moonfory.StructMeta::of(model, user=207, tags=Map([("val", 4)]), refs=[
    "next",
  ])
  let val = meta.find("val").unwrap()
  assert_eq(val.track_ref, false)
  assert_eq(val.identifier(), "4")
  let next = meta.find("next").unwrap()
  assert_eq(next.track_ref, true)
  assert_eq(next.identifier(), "next")
}

///|
test "a description this format cannot carry is refused, not dropped" {
  let model = @moonmodel.Model::new("Open", [
    @moonmodel.Field::new("whatever", @moonmodel.Any),
  ])
  let refused = try {
    let _ = @moonfory.StructMeta::of(model, user=208)
    "built"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "built"
  }
  assert_eq(refused, "Unsupported(kind=model kind any)")
}

///|
test "a struct from a description writes the bytes the same struct built by hand does" {
  let model = @moonmodel.Model::new("Account", [
    @moonmodel.Field::new("id", @moonmodel.Int),
    @moonmodel.Field::new("nick", @moonmodel.Text),
  ])
  let from_model = @moonfory.StructMeta::of(model, user=210)
  let by_hand = @moonfory.StructMeta::new("Account", 210, [
    @moonfory.FieldMeta::new("id", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new("nick", @moonfory.TypeId::String),
  ])
  // Same schema, so the same fingerprint and the same field order.
  assert_eq(from_model.hash(), by_hand.hash())
  let from_description = @moonfory.dumps(
    @moonfory.Value::Struct(from_model, [
      ("id", @moonfory.Value::Int(7L)),
      ("nick", @moonfory.Value::Str("ada")),
    ]),
  )
  let written_by_hand = @moonfory.dumps(
    @moonfory.Value::Struct(by_hand, [
      ("id", @moonfory.Value::Int(7L)),
      ("nick", @moonfory.Value::Str("ada")),
    ]),
  )
  assert_eq(from_description, written_by_hand)
}

///|
test "fields come back in the order the schema declares, not the wire's" {
  let home = @moonfory.StructMeta::new("Home", 212, [
    @moonfory.FieldMeta::new("city", @moonfory.TypeId::String),
  ])
  let meta = @moonfory.StructMeta::new("Mixed", 211, [
    @moonfory.FieldMeta::new("name", @moonfory.TypeId::String),
    @moonfory.FieldMeta::new("age", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new("home", @moonfory.TypeId::Struct, child=home),
  ])
  let value = @moonfory.Value::Struct(meta, [
    ("name", @moonfory.Value::Str("ada")),
    ("age", @moonfory.Value::Int(36L)),
    (
      "home",
      @moonfory.Value::Struct(home, [("city", @moonfory.Value::Str("Oslo"))]),
    ),
  ])
  let bytes = @moonfory.dumps(value)
  // The wire puts the primitive first; the value that comes back is the one
  // that went in, declaration order and all.
  let back : @moonfory.Value = @moonfory.loads(bytes, schemas=[meta, home])
  assert_eq(names_of(back), ["name", "age", "home"])
  assert_eq(back, value)
  // And writing it again is the same bytes, because the writer re-sorts.
  assert_eq(@moonfory.dumps(back), bytes)
}

///|
test "a cycle is reordered as a whole, so the node it points at agrees" {
  // `next` sorts before `tag` on the wire, so the wire order is not the order
  // the schema declares: a reference reaches a struct that is still being read,
  // and that struct has to end up in the same order as the one that points here.
  let node = @moonfory.StructMeta::new("Ring", 213, [
    @moonfory.FieldMeta::new("tag", @moonfory.TypeId::String),
    @moonfory.FieldMeta::new("next", @moonfory.TypeId::Struct, track_ref=true),
  ])
  let ring = @moonfory.Value::Struct(node, [
    ("tag", @moonfory.Value::Str("root")),
    ("next", @moonfory.Value::Pointer(0)),
  ])
  let bytes = @moonfory.dumps(ring, track_ref=true)
  let back : @moonfory.Value = @moonfory.loads(
    bytes,
    schemas=[node],
    track_ref=true,
  )
  assert_eq(back, ring)
  assert_eq(@moonfory.dumps(back, track_ref=true), bytes)
}
