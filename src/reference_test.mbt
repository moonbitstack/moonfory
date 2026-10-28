// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// References and cycles: what a value that appears twice, or that contains
// itself, looks like on the wire and after it comes back.
//
// The bytes here are the ones Go's `fory` writes for the same schema, because a
// cycle is the one shape Python's `pyfory` cannot write at all: its serializer
// recurses. Go writes one, so Go is the peer this file is checked against.

///|
/// `Node { val: int32, next: Node }`, where `next` may be shared: the schema the
/// fixtures in this file are written under.
fn node_schema() -> @moonfory.StructMeta {
  @moonfory.StructMeta::new("Node", 300, [
    @moonfory.FieldMeta::new("val", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new("next", @moonfory.TypeId::Struct, track_ref=true),
  ])
}

///|
test "a struct that contains itself keeps its shape on the wire" {
  let meta = node_schema()
  let value = @moonfory.Value::Struct(meta, [
    ("val", @moonfory.Value::Int(1L)),
    // Reference zero is the root, which this value is.
    ("next", @moonfory.Value::Pointer(0)),
  ])
  let bytes = @moonfory.dumps(value, track_ref=true)
  // `fory.Node{Val: 1, Next: <itself>}` as Go writes it: the root's `0x00` flag,
  // the STRUCT type, the user type ID, the schema's fingerprint, the field, and
  // the reference back to id zero.
  inspect(@base16.encode(bytes), content="01001bac02eecb234f02fe00")
  let back : @moonfory.Value = @moonfory.loads(
    bytes,
    schemas=[meta],
    track_ref=true,
  )
  inspect(back, content="Struct(300, [val: Int(1), next: Pointer(0)])")
  // And the value that came back goes out as the bytes that made it.
  inspect(
    @base16.encode(@moonfory.dumps(back, track_ref=true)),
    content="01001bac02eecb234f02fe00",
  )
}

///|
/// A pair of structs, both pointing at the same node: what sharing is.
fn pair_schema() -> @moonfory.StructMeta {
  @moonfory.StructMeta::new("Pair", 301, [
    @moonfory.FieldMeta::new("left", @moonfory.TypeId::Struct, track_ref=true),
    @moonfory.FieldMeta::new("right", @moonfory.TypeId::Struct, track_ref=true),
  ])
}

///|
test "a value written twice is written once and pointed at after" {
  let node = node_schema()
  let pair = pair_schema()
  let once = @moonfory.Value::Struct(node, [
    ("val", @moonfory.Value::Int(7L)),
    ("next", @moonfory.Value::Null),
  ])
  let value = @moonfory.Value::Struct(pair, [
    ("left", @moonfory.Value::Shared(1, once)),
    // The same key again: a reference to what was just written, not a second
    // copy of it.
    ("right", @moonfory.Value::Pointer(1)),
  ])
  let bytes = @moonfory.dumps(value, track_ref=true)
  let back : @moonfory.Value = @moonfory.loads(
    bytes,
    schemas=[node, pair],
    track_ref=true,
  )
  inspect(
    back,
    content="Struct(301, [left: Shared(1, Struct(300, [val: Int(7), next: Null])), right: Pointer(1)])",
  )
  // One node on the wire, whatever the value graph looks like: the schema, the
  // node and its field, then the two bytes of a reference to it.
  inspect(
    @base16.encode(bytes),
    content="01001bad02e6c71ba4001bac02eecb234f0efdfe01",
  )
  inspect(
    @base16.encode(@moonfory.dumps(back, track_ref=true)),
    content=@base16.encode(bytes),
  )
}

///|
test "a reference to a value that was never written is refused" {
  let pair = pair_schema()
  let value = @moonfory.Value::Struct(pair, [
    ("left", @moonfory.Value::Pointer(9)),
    ("right", @moonfory.Value::Null),
  ])
  let outcome = try {
    let _ = @moonfory.dumps(value, track_ref=true)
    "written"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "written"
  }
  inspect(outcome, content="BadRef(at=9, got=9)")
}

///|
test "a struct whose schema says nothing may be shared writes the plain flag" {
  // The same shape, with tracking off: every field is preceded by the
  // not-tracked flag, and the value that contains itself cannot be written at
  // all — which is what turning tracking off costs.
  let meta = node_schema()
  let value = @moonfory.Value::Struct(meta, [
    ("val", @moonfory.Value::Int(1L)),
    ("next", @moonfory.Value::Null),
  ])
  let bytes = @moonfory.dumps(value)
  inspect(@base16.encode(bytes), content="01ff1bac02eecb234f02fd")
}
