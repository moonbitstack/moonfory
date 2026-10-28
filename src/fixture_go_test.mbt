// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The Go half of the interop fixtures: the same classes of message, written by a
// third implementation, plus the one shape Python cannot write.

///|
/// `Node { val: int32, next: Node }`, the schema the cyclic fixture arrives
/// under: user type ID 300, with `next` able to be shared.
fn fixture_node() -> @moonfory.StructMeta {
  @moonfory.StructMeta::new("Node", 300, [
    @moonfory.FieldMeta::new("val", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new("next", @moonfory.TypeId::Struct, track_ref=true),
  ])
}

///|
test "every message Go wrote reads back as the value it stands for" {
  let expected : Map[String, String] = {
    "bool": "Bool(true)",
    "float64": "Float(1.5)",
    "string_utf8": "Str(\"世界\")",
    "binary": "Binary(6162)",
    "int32_array": "List(Int32Array, [Int(1), Int(2), Int(3)])",
    "struct_point": "Struct(100, [x: Int(1), y: Int(2)])",
    "timestamp": "Timestamp(1, 500000000)",
    "cycle_node": "Struct(300, [val: Int(1), next: Pointer(0)])",
  }
  let mut seen = 0
  for (name, text) in go_fixtures {
    let value : @moonfory.Value = @moonfory.loads(
      @base16.decode(text),
      schemas=[fixture_point(), fixture_node()],
      track_ref=true,
    )
    let want = match expected.get(name) {
      Some(want) => want
      None => fail("the fixture \{name} has no expectation")
    }
    if value.to_string() != want {
      fail("\{name}: read \{value.to_string()}, wanted \{want}")
    }
    seen = seen + 1
  }
  inspect(seen, content="8")
}

///|
/// The direction that matters for a cycle: what came back goes out again as the
/// bytes Go wrote, so a value can be read, kept and forwarded without being
/// flattened.
test "the cycle Go wrote goes out as Go wrote it" {
  let mut text = ""
  for (name, bytes) in go_fixtures {
    if name == "cycle_node" {
      text = bytes
    }
  }
  if text == "" {
    fail("no cycle fixture")
  }
  let value : @moonfory.Value = @moonfory.loads(
    @base16.decode(text),
    schemas=[fixture_node()],
    track_ref=true,
  )
  inspect(@base16.encode(@moonfory.dumps(value, track_ref=true)), content=text)
}
