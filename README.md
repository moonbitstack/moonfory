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
numbers and `moonbitstack/moondate` for the time types; nothing else.

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
| `hex(bytes)` / `unhex(text)` | bytes or text | the other, for reading a fixture |

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
| STRUCT | 27 | `StructMeta` + fields | user id, then fields in Fory order |
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

## Shared and circular values

MoonBit has no object identity to track, so a value that is meant to be shared is
marked explicitly, with a key you choose. The first write emits the body; later
writes emit a back-reference. A cycle read back is stitched together through the
reader's node table, and a cycle that cannot be resolved is a `Cyclic` refusal
rather than a hang.

```moonbit
let once = @moonfory.shared(7, "the same string")
let twice = [once, once]                    // two references, one body
let bytes = @moonfory.dumps(twice, track_ref=true)
```

Turn `track_ref` on for both ends, or neither: a reader that is not tracking
reads the first body and then a flag it does not expect.

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
| Writing a shared reference from a `Value` | `Value` has no identity to point at; use `Shared[T]` with an explicit key |
| Reading a struct without its schema | The schema is the user id's meaning; `loads(schemas=[...])` supplies it |

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

## Specifications

- [Fory cross-language serialization](https://fory.apache.org/docs/specification/fory_xlang_serialization_spec)
- [Fory row format](https://fory.apache.org/docs/specification/fory_row_format_spec)
- [Fory type mapping](https://fory.apache.org/docs/specification/fory_type_mapping)


## Licence

Apache-2.0. See [LICENSE](LICENSE).
