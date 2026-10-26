// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Everything this package does, in one run: `moon run src/examples/tour`.
///
/// A format is a promise about bytes, and a promise is checked by looking at
/// them, so every section prints what it wrote as hexadecimal next to what
/// came back.
#coverage.skip
fn main raise {
  section("one value, one message")
  show("Int 1", 1)
  show("Int64 1", 1L)
  show("String \"ab\"", "ab")
  show("Double 1.5", 1.5)
  show("Bool true", true)
  show("Bytes b\"ab\"", @utf8.encode("ab"))

  section("containers")
  show("Array [1, 2, 3]", [1, 2, 3])
  show("Map {\"a\": 1}", { "a": 1 })
  let empty : Array[Int32] = []
  show("empty Array", empty)
  show("nothing at all", @moonfory.Value::Null)

  section("a struct, written down once")
  let point = @moonfory.StructMeta::new("Point", 1, [
    @moonfory.FieldMeta::new("x", @moonfory.TypeId::Int32),
    @moonfory.FieldMeta::new("y", @moonfory.TypeId::Int32),
  ])
  let written = @moonfory.Value::Struct(point, [
    ("x", @moonfory.Value::Int(1L)),
    ("y", @moonfory.Value::Int(2L)),
  ])
  show("Point(1, 2)", written, schemas=[point])

  section("a value that is written more than once")
  let twice = [@moonfory.shared(7, "once"), @moonfory.shared(7, "once")]
  try {
    let tracked = @moonfory.dumps(twice, track_ref=true)
    let back : Array[@moonfory.Shared[String]] = @moonfory.loads(
      tracked,
      track_ref=true,
    )
    let values = back.map(fn(one) { one.value })
    println("  " + pad(@moonfory.hex(tracked), 40) + "  " + join(values))
  } catch {
    failure => println("  refused  " + failure.to_string())
  } noraise {
    _ => ()
  }

  section("a row, read by field")
  let schema = @moonfory.RowSchema::new([
    { name: "id", ty: @moonfory.RowType::Int64, nullable: false, },
    { name: "name", ty: @moonfory.RowType::String, nullable: false, },
    { name: "age", ty: @moonfory.RowType::Int32, nullable: true, },
  ])
  let row = @moonfory.Row::new(schema)
  row.set(0, @moonfory.RowValue::Int64(7L))
  row.set(1, @moonfory.RowValue::String("ada"))
  row.set(2, @moonfory.RowValue::Null)
  try {
    let row_bytes = row.finish()
    let cur = @moonfory.RowCursor::new(row_bytes[:], schema)
    println(
      "  " +
      pad("id, name, age", 18) +
      "  " +
      pad(@moonfory.hex(row_bytes), 40) +
      "  " +
      "\{@debug.Debug::to_repr(cur.get_field(1))}",
    )
  } catch {
    failure => println("  refused  " + failure.to_string())
  } noraise {
    _ => ()
  }

  section("the time types, through moondate")
  show("Date 19000d", @moonfory.date_of_days(19_000L))
  show("Moment 1.7e9", @moonfory.moment_of_parts(1_700_000_000L, 0))
  show("Span 3.5s", @moonfory.span_of_parts(3L, 500_000_000))

  section("a message written by another language")
  for
    line in [
      ("   1", "01ff07fe01"),
      ("  -1", "01ff0701"),
      (" \"世界\"", "01ff1511164e4c75"),
      (" [None, 1]", "01ff16020a07fdff02"),
      (" {\"a\": 1}", "01ff180100011507046102"),
    ] {
    let (label, text) = line
    println("  " + pad(label, 12) + "  " + pad(text, 26) + "  " + read(text))
  }

  section("a message that is refused")
  for
    line in [
      ("truncated", "01ff040100"),
      ("two values", "01ff070201ff0702"),
      ("no xlang flag", "00ff0702"),
    ] {
    let (label, text) = line
    println("  " + pad(label, 12) + "  " + pad(text, 26) + "  " + read(text))
  }
}

///|
fn[T : @moonfory.Codec + Debug] show(
  label : String,
  value : T,
  schemas~ : Array[@moonfory.StructMeta] = [],
) -> Unit {
  try {
    let bytes = @moonfory.dumps(value)
    let back : T = @moonfory.loads(bytes, schemas~)
    println(
      "  " +
      pad(label, 18) +
      "  " +
      pad(@moonfory.hex(bytes), 40) +
      "  " +
      "\{@debug.Debug::to_repr(back)}",
    )
  } catch {
    failure =>
      println("  " + pad(label, 18) + "  refused  " + failure.to_string())
  } noraise {
    _ => ()
  }
}

///|
fn read(text : String) -> String {
  try {
    let value : @moonfory.Value = @moonfory.loads(@moonfory.unhex(text))
    value.to_string()
  } catch {
    failure => "refused  " + failure.to_string()
  } noraise {
    text => text
  }
}

///|
fn join(texts : Array[String]) -> String {
  let out = StringBuilder()
  for i in 0..<texts.length() {
    if i > 0 {
      out.write_char(',')
    }
    out.write_char('"')
    for c in texts[i].to_array() {
      out.write_char(c)
    }
    out.write_char('"')
  }
  out.to_string()
}

///|
fn section(title : String) -> Unit {
  println("")
  println(title)
}

///|
fn pad(text : String, width : Int32) -> String {
  let out = StringBuilder()
  for c in text.to_array() {
    out.write_char(c)
  }
  let spaces = width - text.length()
  for _ in 0..<spaces {
    out.write_char(' ')
  }
  out.to_string()
}
