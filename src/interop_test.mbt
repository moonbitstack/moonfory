// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every fixture here is a message written by another language — Python,
/// through `pyfory` — and read back as the value it is. The last section is the
/// same road in the other direction: bytes this package wrote, which `pyfory`
/// reads.
fn read(text : String) -> String raise {
  let value : @moonfory.Value = @moonfory.loads(@moonfory.unhex(text))
  value.to_string()
}

///|
test "the integers Python writes" {
  inspect(read("01ff07fe01"), content="Int(127)")
  inspect(read("01ff0701"), content="Int(-1)")
  inspect(read("01ff0702"), content="Int(1)")
  inspect(read("01ff07808080808040"), content="Int(1099511627776)")
  inspect(read("01fd"), content="Null")
}

///|
test "the strings Python writes, in all three encodings" {
  inspect(read("01ff1500"), content="Str(\"\")")
  inspect(read("01ff15086162"), content="Str(\"ab\")")
  inspect(read("01ff1504e9"), content="Str(\"é\")")
  inspect(read("01ff1511164e4c75"), content="Str(\"世界\")")
}

///|
test "the containers Python writes" {
  inspect(read("01ff1600"), content="List(List, [])")
  inspect(read("01ff1800"), content="Map([])")
  inspect(
    read("01ff16030807020406"),
    content="List(List, [Int(1), Int(2), Int(3)])",
  )
  inspect(read("01ff170208070204"), content="List(Set, [Int(1), Int(2)])")
  inspect(read("01ff16020a07fdff02"), content="List(List, [Null, Int(1)])")
  inspect(read("01ff180100011507046102"), content="Map([(Str(\"a\"), Int(1))])")
  inspect(
    read("01ff180100011516046102000702150462"),
    content="Map([(Str(\"a\"), List(List, [Int(1), Str(\"b\")]))])",
  )
}

///|
test "the rest of what Python writes" {
  inspect(read("01ff0101"), content="Bool(true)")
  inspect(read("01ff14000000000000f83f"), content="Float(1.5)")
  inspect(read("01ff29026162"), content="Binary(6162)")
}

///|
/// The same messages this package writes, which `pyfory` reads back as the
/// same values.
test "what this package writes, read by another language" {
  let bytes = [
    (@moonfory.dumps(@moonfory.Value::Int(1L)), "01ff060100000000000000"),
    (@moonfory.dumps(@moonfory.Value::Str("ab")), "01ff150a6162"),
    (
      @moonfory.dumps(@moonfory.Value::Binary(@moonfory.unhex("6162"))),
      "01ff29026162",
    ),
    (@moonfory.dumps(@moonfory.Value::Bool(true)), "01ff0101"),
    (@moonfory.dumps(@moonfory.Value::Float(1.5)), "01ff14000000000000f83f"),
    (
      @moonfory.dumps(@moonfory.Value::List(@moonfory.TypeId::List, [])),
      "01ff1600",
    ),
    (@moonfory.dumps(@moonfory.Value::Null), "01fd"),
  ]
  for (wrote, text) in bytes {
    inspect(@moonfory.hex(wrote), content=text)
  }
}
