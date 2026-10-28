# moonfory

A MoonBit value, written in Apache Fory's two wire formats: the **cross-language
binary format** that Java, Go, Python, Rust and C++ already read, and the **row
format** that lets a reader take one field without building the object.

```moonbit
let bytes = @moonfory.dumps(42)          // 01 ff 04 2a 00 00 00
let back  : Int = @moonfory.loads(bytes)
```

The bytes are not this package's opinion. They are the ones
[the specification](https://fory.apache.org/docs/specification/fory_xlang_serialization_spec)
fixes, and the tests assert them one at a time — including the bytes `pyfory`
writes, which this package reads back unchanged.

## Install

```sh
moon add moonbitstack/moonfory
```

In `moon.pkg`:

```moonbit
import {
  "moonbitstack/moonfory",
}
```

Then `@lib` is the package. Dependencies are `moonbitstack/moonvar` for the
numbers, `moonbitstack/moondate` for the time types, and
`moonbitstack/moonmodel` for the description of a struct.

The tests need one more, `moonbitstack/moonbase/base16`, because a fixture is
read and written as hex and hex is not this package's business: it does not
export `hex` or `unhex`.

## Two entry points, four verbs

Every value goes in and comes out through `dumps` and `loads`. The `dump`/`load`
pair does the same thing over a `Buffer` or a `Reader` you already hold, which is
what you want when a message is one part of a larger stream.

```moonbit
// One value, all of it.
let bytes : Bytes = @moonfory.dumps(value)
let value : T     = @moonfory.loads(bytes)

// The same, without allocating a fresh buffer.
@moonfory.dump(value, buffer)
let value : T = @moonfory.load(reader)
```

| Function | Takes | Gives |
|:--|:--|:--|
| `dumps(value, ...)` | any `Codec` value | the whole message as `Bytes` |
| `loads(bytes, schemas?, ...)` | a message | the value, or a `Refused` |
| `dump(value, buffer, ...)` | a value and a buffer | writes into the buffer |
| `load(reader)` | a reader | one value |
| `write_message(w, value)` | a writer and a value | head, value, nothing else |
| `read_message(r)` | a reader | the one value the head announces |
| `write_value(w, v)` / `read_value(r)` | a `Value` | the dynamic form |

`loads` reads exactly one value and then insists the message is finished, so two
values in one buffer are a `Trailing` error rather than a silent truncation.

## Making a type travel

A type becomes serialisable by implementing `Codec`. `write_data` writes the
**body only** — the type ID belongs to whoever knows the schema, so a list
element and a struct field can each name their own type without the body
repeating it.

```moonbit
pub impl Codec for UserId with fn ty(_self) {
  TypeId::Int64
}

pub impl Codec for UserId with fn write_data(self, w) {
  w.write_i64(self.0)
}

pub impl Codec for UserId with fn read_data(r, _ty) {
  UserId(r.read_i64())
}
```

`Bool`, `Int`, `Int64`, `UInt`, `UInt64`, `Byte`, `Float`, `Double`, `String`,
`Bytes`, `Array[T]`, `Map[K, V]` and `Value` already implement it.

## The type table

| Fory type | Code | MoonBit | Written as |
|:--|--:|:--|:--|
| BOOL | 1 | `Bool` | one byte, `00` or `01` |
| INT8 / INT16 / INT32 | 2 / 3 / 4 | `Byte` / `Int` | two's complement, little-endian |
| INT64 | 6 | `Int64` | eight bytes |
| VARINT32 / VARINT64 | 5 / 7 | any signed width | zig-zag, base-128 |
| TAGGED_INT64 / UINT64 | 8 / 15 | `Int64` / `UInt64` | four bytes when small, else nine |
| FLOAT32 / FLOAT64 | 19 / 20 | `Float` / `Double` | IEEE 754, little-endian |
| STRING | 21 | `String` | length-and-encoding header, then UTF-8 |
| LIST / SET | 22 / 23 | `Array[T]` | count, element header, elements |
| MAP | 24 | `Map[K, V]` | total, then key/value chunks |
| STRUCT | 27 | `StructMeta` + fields | user id, schema fingerprint, then fields in Fory order |
| ENUM | 25 | ordinal | a varint |
| DURATION / TIMESTAMP / DATE | 37 / 38 / 39 | `@moondate.Span` / `Moment` / `Date` | see below |
| DECIMAL | 40 | `(Int, BigInt)` | scale, then the unscaled integer |
| BINARY | 41 | `Bytes` | length, then the bytes |
| BOOL_ARRAY … FLOAT64_ARRAY | 43 … 56 | `Array[T]` | raw little-endian, no header per element |

Strings are written as UTF-8. A reader also accepts LATIN1 and UTF-16, because
`pyfory` writes LATIN1 for ASCII and the format allows it; only the writer's
choice is fixed here.

## Numbers, in one place

`Int` is written as INT32, `Int64` as INT64, `UInt` as UINT32, `UInt64` as
UINT64. The reader is looser on purpose: it accepts **any** width of the same
signedness, so a peer's VARINT64 arrives as an `Int` without a byte of
conversion. A 64-bit value asked for as a 32-bit type is refused rather than
truncated.

## Configuration

Every knob has a default, and every default is the Rust `fory` crate's, because
that is the reference the specification names and a default nobody shares is a
default an interop test finds.

| Knob | Default | What it means |
|:--|:--|:--|
| `xlang` | `true` | the header carries the cross-language flag |
| `track_ref` | `false` | values written twice are sent once and pointed at |
| `check_string` | `true` | string bytes are checked as UTF-8 before becoming a `String` |
| `depth` | `5` | how deeply values may nest before the message is refused |
| `fields` | `512` | how many fields a struct may declare |
| `graph` | `134_217_728` | how many variable-length bytes one message may declare |

**Precedence.** A call has three places to say what it wants, and they are
resolved in one order. The library preset (`config`) is the floor. A `Config`
value passed as `config=` replaces it wholesale. The flat mirrors — `xlang=`,
`track_ref=`, `check_string=`, `depth=`, `fields=`, `graph=` — then override
single fields of that result. When a `Config` and a flat mirror disagree, the
flat mirror wins, unless `wins=Base` is passed, in which case the record wins.
A disagreement is silent by default; `clash=Panic` turns it into a `Clashed`
error, and `clash=Handle(f)` lets you arbitrate.

```moonbit
// The preset, with one field changed.
@moonfory.dumps(v, track_ref=true)

// A whole config, then one field overridden on top of it.
@moonfory.dumps(v, config=my_config, depth=8)

// Refuse rather than pick when the two disagree.
@moonfory.dumps(v, config=my_config, xlang=false, clash=Panic)
```

## Describing a struct

A struct's fields are a `@moonmodel` description — the same one an OpenAPI
document or a `CREATE TABLE` would be generated from — plus the three things the
wire needs that a description has no word for: the type ID the field goes out
as, the tag that identifies it when the schema configures one, and whether the
value may be shared.

```moonbit
let point = @moonfory.StructMeta::new("Point", 100, [
  @moonfory.FieldMeta::new("x", @moonfory.TypeId::VarInt32),
  @moonfory.FieldMeta::new("y", @moonfory.TypeId::VarInt32),
])

let person = @moonfory.StructMeta::new("Person", 101, [
  @moonfory.FieldMeta::new("name", @moonfory.TypeId::String),
  @moonfory.FieldMeta::new("age", @moonfory.TypeId::VarInt32),
  // A list says what it holds, because the writer may leave the element type
  // out of the header.
  @moonfory.FieldMeta::new(
    "tags", @moonfory.TypeId::List, element=Some(@moonfory.TypeId::String),
  ),
  // A field whose type is declared sends no type ID, so the schema has to say
  // which struct it is.
  @moonfory.FieldMeta::new(
    "home", @moonfory.TypeId::Struct, nullable=true, child=Some(point),
  ),
])
```

From a `#model.derive` model, `StructMeta::of` fills the type IDs from the
description's kinds, and takes the child schemas by name:

```moonbit
let meta = @moonfory.StructMeta::of(
  model, user=101, children=[point], refs=["home"],
)
```

A field's *description* is `FieldMeta::desc`, and `meta.model()` hands the whole
`@moonmodel.Model` back, so one description can be published as a schema and
used as a codec without being written twice. A kind with no wire type — `Any` —
is refused rather than guessed at.

## The schema fingerprint

Every struct carries a four-byte fingerprint of its schema, and a peer checks it
against its own before it trusts a field. It is `identifier,typeID,ref,nullable;`
per field, in identifier order, hashed with MurmurHash3 x64 128 seeded with 47.

Two conventions had to be picked, because the reference implementations differ:
a field of a user type writes `0` for its type ID and `0` for its ref flag
(neither can be compared across languages), and a list writes its element type as
`[type,0,0]`. Under those two rules the fingerprints this package computes are
the ones `pyfory` writes, byte for byte, and the all-primitive ones Go writes too.

## Shared and circular values

MoonBit has no object identity to track, so identity is a key you choose and the
value carries: `Shared(key, value)` says "this is the value filed under `key`",
and `Pointer(key)` says "the value already filed under `key`". The first one is
written out in full; the second is two bytes.

```moonbit
let node = @moonfory.StructMeta::new("Node", 300, [
  @moonfory.FieldMeta::new("val", @moonfory.TypeId::VarInt32),
  @moonfory.FieldMeta::new("next", @moonfory.TypeId::Struct, track_ref=true),
])

// A node whose `next` is itself. Reference zero is the root, which this is.
let value = @moonfory.Value::Struct(node, [
  ("val", @moonfory.Value::Int(1L)),
  ("next", @moonfory.Value::Pointer(0)),
])

@moonfory.dumps(value, track_ref=true)   // 01 00 1b ac02 eecb234f 02 fe 00
```

Those are the bytes Go's `fory` writes for `struct Node { Val int32; Next *Node }`,
byte for byte, and Go reads them back into a struct whose `Next` is itself. A
value that comes back from a peer is the same shape: the node it starts at is a
`Shared`, and the field that leads back to it is a `Pointer` to the same key, so
the value can be held without holding itself and written again unchanged.

A typed value is marked the same way, with `shared` for the writer's key:

```moonbit
let once = @moonfory.shared(7, "the same string")
let twice = [once, once]                    // two references, one body
let bytes = @moonfory.dumps(twice, track_ref=true)
```

Turn `track_ref` on for both ends, or neither: a reader that is not tracking
reads the first body and then a flag it does not expect. Python's `pyfory`
cannot write a cycle at all — its serializer recurses — so Go is the peer the
cyclic fixtures are checked against.

## The row format

The row format trades a little space for random access: eight bytes per field,
whether the field needs them or not, so field `i` is always at
`bitmap + i * 8`. A reader takes one field and leaves the rest alone.

```moonbit
let schema = @moonfory.RowSchema::new([
  { name: "id",   ty: @moonfory.RowType::Int64,  nullable: false },
  { name: "name", ty: @moonfory.RowType::String, nullable: false },
  { name: "age",  ty: @moonfory.RowType::Int32,  nullable: true  },
])

let row = @moonfory.Row::new(schema)
row.set(0, @moonfory.RowValue::Int64(7L))
row.set(1, @moonfory.RowValue::String("ada"))
row.set(2, @moonfory.RowValue::Null)

let bytes = row.finish()
let cur = @moonfory.RowCursor::new(bytes[:], schema)
cur.get_field(1)                 // RowValue::String("ada"), field 0 never read
cur.is_null(2)                   // true
```

The layout is the specification's standard variant: a null bitmap rounded to
eight bytes, one eight-byte slot per field, then the variable data. An array
keeps fixed-width elements at their natural width and variable ones as
offset-and-size pairs; a map is a key array and a value array; a nested struct is
a whole row inside the variable region. The compact variant is Java-only and is
not implemented here.

## Time

Through `moonbitstack/moondate`, so a MoonBit program never spells out epoch
seconds:

```moonbit
let date   = @moonfory.date_of_days(19_000L)                 // a Date, as DATE
let moment = @moonfory.moment_of_parts(1_700_000_000L, 0)    // a Moment, as TIMESTAMP
let span   = @moonfory.span_of_parts(3L, 500_000_000)        // a Span, as DURATION
@moonfory.dumps(moment)                                      // and back through loads
```

Nanoseconds are always the sub-second part, in `[0, 1e9)`, so a value of 1.5
seconds is `(1, 500_000_000)` and a negative span borrows a second rather than
carrying a negative nanosecond field.

## What is deliberately not here

| Thing | Why not |
|:--|:--|
| Compatible struct mode (28, 30) | It needs a schema registry to reconcile two type definitions; that belongs with `moonmodel`, not inside a codec |
| FLOAT8 / FLOAT8_ARRAY (16, 56) | No peer in reach writes them; when one does, the table has the code |
| Reading a struct without its schema | The schema is the user id's meaning; `loads(schemas=[...])` supplies it |
| inferring which value is shared | Identity is not in a MoonBit value; say `Shared`/`Pointer` and the wire follows |

Each refusal is a `Refused` variant with the offset that produced it, so a
malformed message names where it stopped rather than "invalid input".

## Errors

| Variant | When |
|:--|:--|
| `Truncated(at, want, got)` | the buffer ended before the value did |
| `TooLarge(at, limit, got)` | a declared length or count crossed a limit |
| `TooDeep(at, limit)` | nesting crossed `depth` |
| `BadType(at, got)` / `WantType(at, want, got)` | the type ID is unknown, or not the one asked for |
| `BadHeader(at, got)` | the header's flag bits are not this format's |
| `BadRef(at, got)` | a back-reference named an id never written |
| `BadEncoding(at, got)` | a string's encoding tag is not one of the three |
| `Cyclic(at, got)` | a cycle that cannot be resolved |
| `Trailing(at, got)` | bytes remain after the one message |
| `Unsupported(kind)` | the type has no counterpart here |

## Interop, as a test

Every class of message this package reads has been read from bytes another
implementation wrote, and the bytes that go the other way have been read by that
implementation. The two peers are `pyfory` for Python and `fory` for Go.

The fixtures are generated by `scripts/interop.py` and `scripts/interop.go`, run
by hand, and checked in as a MoonBit file the tests read. CI runs the tests and
needs neither language installed, so a byte-level interop test costs a second per
push rather than a toolchain.

```sh
python3 scripts/interop.py     # writes src/fixtures_pyfory_test.mbt
(cd scripts && go run .)       # writes src/fixtures_go_test.mbt
moon fmt                       # the generated files are formatted by the toolchain
```

A fixture is the bytes and nothing else: the MoonBit side says what the value is.
A test that could be made to pass by changing both sides at once is not one, so
the expectation for each fixture is written out by hand in `src/fixture_test.mbt`.

Three things the fixtures found, and this package now does: a nested struct goes
out as its fingerprint and its fields with no type ID in front, a list whose
element type the schema declares goes out without the type in its header, and a
dense array goes out as a byte count and raw elements rather than as a list.

## Specifications

- [Fory cross-language serialization](https://fory.apache.org/docs/specification/fory_xlang_serialization_spec)
- [Fory row format](https://fory.apache.org/docs/specification/fory_row_format_spec)
- [Fory type mapping](https://fory.apache.org/docs/specification/fory_type_mapping)


## Licence

Apache-2.0. See [LICENSE](LICENSE).
