// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The interop fixtures: messages another implementation wrote, read here, and
// written back.
//
// The bytes come from `scripts/interop.py` (Python, through `pyfory`) and
// `scripts/interop.go` (Go, through `fory`), and are checked in alongside this
// file. The scripts are run by hand; the tests need neither language installed,
// which is what makes a byte-level interop test affordable on every push.

///|
/// The structs the fixtures refer to, by the user type ID each is written under.
fn fixture_schemas() -> Array[@moonfory.StructMeta] {
  [fixture_point(), fixture_person()]
}

///|
/// `Point { x: int32, y: int32 }`, the schema Python and Go both wrote under
/// user type ID 100.
fn fixture_point() -> @moonfory.StructMeta {
  @moonfory.StructMeta::new("Point", 100, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new("y", @moonfory.TypeId::VarInt32),
  ])
}

///|
/// `Person { name: str, age: int32, tags: [str], home: Point? }`, under 101.
///
/// The two shapes a nested struct puts on the wire are both here: `tags` is a
/// list whose element type the writer left out because the schema declares it,
/// and `home` is a struct whose type the writer left out for the same reason.
fn fixture_person() -> @moonfory.StructMeta {
  @moonfory.StructMeta::new("Person", 101, [
    @moonfory.FieldMeta::new("name", @moonfory.TypeId::String),
    @moonfory.FieldMeta::new("age", @moonfory.TypeId::VarInt32),
    @moonfory.FieldMeta::new(
      "tags",
      @moonfory.TypeId::List,
      element=Some(@moonfory.TypeId::String),
    ),
    @moonfory.FieldMeta::new(
      "home",
      @moonfory.TypeId::Struct,
      nullable=true,
      child=Some(fixture_point()),
    ),
  ])
}

///|
/// What each fixture stands for, by the name the script gave it.
///
/// Written out rather than derived from the bytes, because a test that computes
/// its own expectation from the thing it is testing asserts nothing.
fn pyfory_expected() -> Map[String, String] {
  {
    "bool": "Bool(true)",
    "int32": "Int(42)",
    "uint8": "Int(200)",
    "float64": "Float(1.5)",
    "string_latin1": "Str(\"ab\")",
    "string_utf8": "Str(\"世界\")",
    "string_empty": "Str(\"\")",
    "binary": "Binary(6162)",
    "list_int": "List(List, [Int(1), Int(2), Int(3)])",
    "list_str": "List(List, [Str(\"a\"), Str(\"b\")])",
    "list_empty": "List(List, [])",
    "set_int": "List(Set, [Int(1), Int(2)])",
    "map_str_int": "Map([(Str(\"a\"), Int(1))])",
    "int32_array": "List(Int32Array, [Int(1), Int(2), Int(3)])",
    "float64_array": "List(Float64Array, [Float(1.5), Float(2.5)])",
    "decimal": "Decimal(2, 12345)",
    "timestamp": "Timestamp(1, 500000000)",
    "date": "Date(1)",
    "duration": "Duration(90, 500000)",
    "struct_point": "Struct(100, [x: Int(1), y: Int(2)])",
    "struct_person": "Struct(101, [age: Int(30), home: Struct(100, [x: Int(3), y: Int(4)]), name: Str(\"ann\"), tags: List(List, [Str(\"x\"), Str(\"y\")])])",
    "enum": "Enum(200, 1)",
  }
}

///|
test "every message Python wrote reads back as the value it stands for" {
  let expected = pyfory_expected()
  let mut seen = 0
  for (name, text) in pyfory_fixtures {
    let value : @moonfory.Value = @moonfory.loads(
      @base16.decode(text),
      schemas=fixture_schemas(),
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
  // A fixture list that lost its expectations would otherwise pass in silence.
  inspect(seen, content="22")
}

///|
/// The other direction, where the bytes can agree: a value that carries its own
/// type is written again as the bytes it came from.
///
/// A value read without a schema has no width to be — an `int32` and an `int64`
/// of the same number read alike and would be written alike — so the fixtures
/// that exercise a width are not in this list. They are checked in the direction
/// that matters: the value they stand for, above.
///
/// A string that is not Latin-1 goes out as UTF-8 here and as UTF-16 from
/// Python, and a date goes out as a plain varint where Python writes a tagged
/// one. Both are the writer's choice, and both are legal.
test "what this package writes is what the fixture holds" {
  let exact : Array[String] = [
    "bool", "float64", "binary", "list_empty", "int32_array", "float64_array", "decimal",
    "timestamp", "date", "duration", "struct_point", "enum",
  ]
  for name in exact {
    let text = fixture_named(name)
    let value : @moonfory.Value = @moonfory.loads(
      @base16.decode(text),
      schemas=fixture_schemas(),
    )
    let again = @base16.encode(@moonfory.dumps(value))
    if again != text {
      fail("\{name}: wrote \{again}, and the fixture is \{text}")
    }
  }
}

///|
/// A fixture by name, or a failure: a name the script no longer writes is a
/// test that would otherwise pass by doing nothing.
fn fixture_named(name : String) -> String raise {
  for (one, text) in pyfory_fixtures {
    if one == name {
      return text
    }
  }
  fail("no fixture named \{name}")
}

///|
/// The three fixtures whose bytes this package chooses differently from Python:
/// a string that fits in Latin-1, and an empty one. Both are UTF-8 here, which
/// the specification allows a writer to choose, and which is what Go writes.
///
/// The value is the same value; only the encoding of it differs.
test "a string is a string in whichever encoding it is written" {
  for name in ["string_latin1", "string_empty", "string_utf8"] {
    let text = fixture_named(name)
    let first : @moonfory.Value = @moonfory.loads(
      @base16.decode(text),
      schemas=fixture_schemas(),
    )
    let second : @moonfory.Value = @moonfory.loads(@moonfory.dumps(first))
    if second.to_string() != first.to_string() {
      fail("\{name}: read back \{second.to_string()}")
    }
  }
}
