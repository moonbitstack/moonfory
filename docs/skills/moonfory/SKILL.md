---
name: moonfory
description: Write and read Apache Fory's cross-language binary format and row format from MoonBit, including schemas, shared and circular values, and reading a single field without building the whole row. Use it when a MoonBit service exchanges data with a Java, Go, Python, Rust or C++ peer over Fory, or when a message has to be decoded field by field.
---

# moonfory

`moon add moonbitstack/moonfory`, then import the package in `moon.pkg`:

```moonbit
import {
  "moonbitstack/moonfory",
}
```

The package is `@moonfory`. Nothing here reads a clock, opens a file or keeps
state: a value goes in, bytes come out.

## Send a value and read it back

`dumps` writes one message; `loads` reads one and refuses anything left over.
The type at the call site is what the reader expects, and it may be narrower or
wider than what the writer chose:

```moonbit
let greeting = @moonfory.dumps("hello")
let back : String = @moonfory.loads(greeting)
assert_eq(back, "hello")

let numbers = @moonfory.dumps([1, 2, 3])
let same : Array[Int] = @moonfory.loads(numbers)
assert_eq(same, [1, 2, 3])
```

Several messages in one buffer use a `Buffer` and a `Reader`: `dump` writes a
head per message, so read a head before each `load`.

```moonbit
let stream = Buffer()
@moonfory.dump(1, stream)
@moonfory.dump(2, stream)
let cursor = @moonfory.Reader::new(stream.to_bytes())
cursor.read_head()
let first : Int = @moonfory.load(cursor)
cursor.read_head()
let second : Int = @moonfory.load(cursor)
assert_eq((first, second), (1, 2))
```

A type of your own joins in by implementing `Codec`. `write_data` writes the
body only; the type ID in front of it is what `ty` returns.

```moonbit
struct UserId(Int64)

pub impl @moonfory.Codec for UserId with fn ty(_self) -> @moonfory.TypeId {
  @moonfory.TypeId::Int64
}

pub impl @moonfory.Codec for UserId with fn write_data(
  self,
  w : @moonfory.Writer,
) -> Unit raise {
  w.write_i64(self.0)
}

pub impl @moonfory.Codec for UserId with fn read_data(
  r : @moonfory.Reader,
  _ty : @moonfory.TypeId,
) -> UserId raise {
  UserId(r.read_i64())
}
```

## A struct the other side has to recognise

A struct is a `StructMeta`: a user type ID, plus one `FieldMeta` per field with
the type ID it goes out as. Both ends build the same schema; the reader is
handed it through `schemas=`.

```moonbit
let point = @moonfory.StructMeta::new("Point", 100, [
  @moonfory.FieldMeta::new("x", @moonfory.TypeId::VarInt32),
  @moonfory.FieldMeta::new("y", @moonfory.TypeId::VarInt32),
])

let place = @moonfory.Value::Struct(point, [
  ("x", @moonfory.Value::Int(1L)),
  ("y", @moonfory.Value::Int(2L)),
])

let place_bytes = @moonfory.dumps(place)
let read_place : @moonfory.Value = @moonfory.loads(
  place_bytes, schemas=[point],
)
assert_eq(read_place, place)
assert_eq(@moonfory.dumps(read_place), place_bytes)
```

The fields go out in Fory order — primitives that cannot be absent first, then
the rest — not in the order they were listed, and they come back in that same
order. `point.ordered()` gives the order as a list, which is the quickest way to
see what a peer will read.

A value written twice, or a cycle, carries a key: `Shared(key, value)` writes it
once and `Pointer(key)` points at it. Both ends need `track_ref=true`, and a
cycle cannot be written without it.

```moonbit
let node = @moonfory.StructMeta::new("Node", 300, [
  @moonfory.FieldMeta::new("val", @moonfory.TypeId::VarInt32),
  @moonfory.FieldMeta::new("next", @moonfory.TypeId::Struct, track_ref=true),
])

let cyclic = @moonfory.Value::Struct(node, [
  ("val", @moonfory.Value::Int(1L)),
  ("next", @moonfory.Value::Pointer(0)),
])
let cyclic_bytes = @moonfory.dumps(cyclic, track_ref=true)
let back_node : @moonfory.Value = @moonfory.loads(
  cyclic_bytes, schemas=[node], track_ref=true,
)
assert_eq(back_node, cyclic)
```

## Read one field without reading the row

The row format puts every field in its own eight-byte slot, so a reader takes
the field it wants and never touches the others. Values are checked against the
schema when they are set, not when they are read.

```moonbit
let schema = @moonfory.RowSchema::new([
  { name: "id", ty: @moonfory.RowType::Int64, nullable: false },
  { name: "name", ty: @moonfory.RowType::String, nullable: false },
  { name: "age", ty: @moonfory.RowType::Int32, nullable: true },
])

let record = @moonfory.Row::new(schema)
record.set(0, @moonfory.RowValue::Int64(7L))
record.set(1, @moonfory.RowValue::String("ada"))
record.set(2, @moonfory.RowValue::Null)

let fields = @moonfory.RowCursor::new(record.finish()[:], schema)
assert_eq(fields.get_field(1), @moonfory.RowValue::String("ada"))
assert_eq(fields.is_null(2), true)
```

## What catches people out

- **The type at the call site is the contract.** `loads` needs to know what to
  build: `let n : Int = @moonfory.loads(bytes)`. The wire may hold a narrower or
  wider width of the same signedness and it is converted; a 64-bit value asked
  for as 32 bits is refused rather than truncated.
- **A struct without its schema is refused**, with `Unsupported(kind=struct 1)`
  naming the user type ID. Pass every struct the message can contain, children
  included, in `schemas=`.
- **`track_ref` has to match on both ends.** A reader that is not tracking reads
  the first body and then a flag it does not expect; a writer that is not
  tracking cannot write a cycle at all.
- **`loads` refuses trailing bytes.** Two messages in one buffer are a
  `Trailing` error, not a silent truncation: use `dump` and `load`.
- **The defaults are the Rust reference's**: nesting stops at 5 and a struct may
  declare 512 fields. Raise them per call with `depth=` and `fields=`.
- **Errors carry an offset.** `Truncated(at=3, want=4, got=2)` says where the
  read stopped, which is the only useful thing to log about a malformed message.
