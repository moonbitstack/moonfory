# moonfory

A MoonBit value, written in Apache Fory's two wire formats: the **cross-language
binary format** that Java, Go, Python, Rust and C++ already read, and the **row
format** that lets a reader take one field without building the object.

```moonbit
let bytes : Bytes = @moonfory.dumps(42)
assert_eq(bytes, b"\x01\xff\x04\x2a\x00\x00\x00")
let back : Int = @moonfory.loads(bytes)
assert_eq(back, 42)
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

The package is reached as `@moonfory`. Its dependencies are
`moonbitstack/moonvar` for the numbers, `moonbitstack/moondate` for the time
types, and `moonbitstack/moonmodel` for the description of a struct.

The tests need one more, `moonbitstack/moonbase/base16`, because a fixture is
read and written as hex and hex is not this package's business: it does not
export `hex` or `unhex`.

## Documentation

- [The site](https://moonbitstack.github.io/moonfory/) — the front page and the
  annotated byte examples.
- [The guide](https://moonbitstack.github.io/moonfory/docs.html) — the whole
  interface on one page, install to errors.
- [API reference](https://moonbitstack.github.io/moonfory/api/) — one page per
  public item, generated from the interface and the doc comments below.
- [mooncakes](https://mooncakes.io/docs/moonbitstack/moonfory) — the published
  module and its versions.
- [The skill](https://mooncakes.io/skills/moonbitstack/moonfory) — the same
  knowledge, written for the agent that is about to call it.

## Two entry points, four verbs

Every value goes in and comes out through `dumps` and `loads`. The `dump`/`load`
pair does the same thing over a `Buffer` or a `Reader` you already hold, which is
what you want when a message is one part of a larger stream.

```moonbit
// One value, all of it.
let message : Bytes = @moonfory.dumps(42)
let value : Int = @moonfory.loads(message)
assert_eq(value, 42)

// The same, without allocating a fresh buffer.
let sink = Buffer()
@moonfory.dump(value, sink)
let source = @moonfory.Reader::new(sink.to_bytes())
source.read_head()
let replayed : Int = @moonfory.load(source)
assert_eq(replayed, 42)
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

The type is now a message of its own, and the type ID in front of it is the one
`ty` returned:

```moonbit
let user = UserId(7L)
let id_bytes = @moonfory.dumps(user)
assert_eq(id_bytes, b"\x01\xff\x06\x07\x00\x00\x00\x00\x00\x00\x00")
let same : UserId = @moonfory.loads(id_bytes)
assert_eq(same.0, 7L)
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
| UINT8 / UINT16 / UINT32 | 9 / 10 / 11 | `UInt` | unsigned, little-endian |
| UINT64 | 13 | `UInt64` | eight bytes |
| TAGGED_INT64 / TAGGED_UINT64 | 8 / 15 | — | four bytes when small, else nine |
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
let tracked = @moonfory.dumps(@moonfory.Value::Int(1L), track_ref=true)

// A whole config, with one field overridden on top of it.
let base = @moonfory.Config::new(depth=9)
let deeper = @moonfory.dumps(@moonfory.Value::Int(1L), config=base, depth=8)

// Two settings that disagree: refused, rather than silently picked.
let refused = try {
  @moonfory.dumps(
    @moonfory.Value::Int(1L),
    config=base,
    xlang=false,
    clash=@moonfory.OnClash::Panic,
  )
} catch {
  @moonfory.Clashed(_) => b""
  failure => raise failure
}
assert_eq(refused.length(), 0)
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

A `Value` under that schema writes its fields in Fory order — the primitives
that cannot be absent first, then the rest — whatever order the caller listed
them in. Reading puts the order back, so the value that comes out is the value
that went in:

```moonbit
let ada = @moonfory.Value::Struct(person, [
  ("name", @moonfory.Value::Str("ada")),
  ("age", @moonfory.Value::Int(36L)),
  (
    "tags",
    @moonfory.Value::List(@moonfory.TypeId::List, [
      @moonfory.Value::Str("math"),
    ]),
  ),
  ("home", @moonfory.Value::Struct(point, [
    ("x", @moonfory.Value::Int(1L)),
    ("y", @moonfory.Value::Int(2L)),
  ])),
])
let ada_bytes = @moonfory.dumps(ada)
let read_back : @moonfory.Value = @moonfory.loads(
  ada_bytes, schemas=[person, point],
)
assert_eq(read_back, ada)
// And writing it again is the bytes it came from: the writer sorts, the reader
// sorts back.
assert_eq(@moonfory.dumps(read_back), ada_bytes)
```

`StructMeta::of` takes the `@moonmodel.Model` that `#model.derive` generates,
fills the type IDs from the description's kinds, and takes the child schemas by
name. A model built by hand is the same thing, which is what this block does:

```moonbit
let account = @moonmodel.Model::new("Account", [
  @moonmodel.Field::new("id", @moonmodel.Int),
  @moonmodel.Field::new("nick", @moonmodel.Text),
])

let account_meta = @moonfory.StructMeta::of(account, user=102, refs=["nick"])
assert_eq(account_meta.name(), "Account")
assert_eq(account_meta.user(), 102)
assert_eq(account_meta.find("id").unwrap().ty, @moonfory.TypeId::VarInt32)
```

A field's *description* is `FieldMeta::desc`, and `meta.model()` hands the whole
`@moonmodel.Model` back, so one description can be published as a schema and
used as a codec without being written twice. A kind with no wire type — `Any` —
is refused rather than guessed at.

## The schema fingerprint

Every struct carries a four-byte fingerprint of its schema, and a peer checks it
against its own before it trusts a field. It is `identifier,typeID,ref,nullable;`
per field, in identifier order, and the number is the low half of MurmurHash3
x64 128 over that text, seeded with 47.

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
let cyclic = @moonfory.Value::Struct(node, [
  ("val", @moonfory.Value::Int(1L)),
  ("next", @moonfory.Value::Pointer(0)),
])

let cyclic_bytes = @moonfory.dumps(cyclic, track_ref=true)
assert_eq(
  cyclic_bytes, b"\x01\x00\x1b\xac\x02\xee\xcb\x23\x4f\x02\xfe\x00",
)
```

Those are the bytes Go's `fory` writes for
`struct Node { Val int32; Next *Node }`, byte for byte, and Go reads them back
into a struct whose `Next` is itself. A value that comes back from a peer is the
same shape: the node it starts at is a `Shared`, and the field that leads back to
it is a `Pointer` to the same key, so the value can be held without holding
itself and written again unchanged.

A typed value is marked the same way, with `shared` for the writer's key:

```moonbit
let once = @moonfory.shared(7, "the same string")
let twice = [once, once] // two references, one body
let shared_bytes = @moonfory.dumps(twice, track_ref=true)
let shared_back : Array[@moonfory.Shared[String]] = @moonfory.loads(
  shared_bytes, track_ref=true,
)
assert_eq(shared_back.length(), 2)
assert_eq(shared_back[1].value, "the same string")
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
  { name: "id", ty: @moonfory.RowType::Int64, nullable: false },
  { name: "name", ty: @moonfory.RowType::String, nullable: false },
  { name: "age", ty: @moonfory.RowType::Int32, nullable: true },
])

let row = @moonfory.Row::new(schema)
row.set(0, @moonfory.RowValue::Int64(7L))
row.set(1, @moonfory.RowValue::String("ada"))
row.set(2, @moonfory.RowValue::Null)

let row_bytes = row.finish()
let cur = @moonfory.RowCursor::new(row_bytes[:], schema)
assert_eq(cur.get_field(1), @moonfory.RowValue::String("ada"))
assert_eq(cur.is_null(2), true)
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
let date = @moonfory.date_of_days(19_000L)
let moment = @moonfory.moment_of_parts(1_700_000_000L, 0)
let span = @moonfory.span_of_parts(3L, 500_000_000)

assert_eq(
  @moonfory.days_of_date(@moonfory.loads(@moonfory.dumps(date))), 19_000L,
)
let (seconds, nanos) = @moonfory.parts_of_span(
  @moonfory.loads(@moonfory.dumps(span)),
)
assert_eq(seconds, 3L)
assert_eq(nanos, 500_000_000)
let (epoch, _) = @moonfory.parts_of_moment(
  @moonfory.loads(@moonfory.dumps(moment)),
)
assert_eq(epoch, 1_700_000_000L)
```

Nanoseconds are always the sub-second part, in `[0, 1e9)`, so a value of 1.5
seconds is `(1, 500_000_000)` and a negative span borrows a second rather than
carrying a negative nanosecond field.

## What is deliberately not here

| Thing | Why not |
|:--|:--|
| Named and compatible structs (26, 28, 29, 30) | They need a schema registry to reconcile two type definitions; that belongs with `moonmodel`, not inside a codec |
| Union, typed union, named union (33, 34, 35) | No MoonBit type maps to one, and which branch a peer meant cannot be recovered without the registry the named form expects |
| Ext (31, 32) | Another language's object graph, which needs a decoder this package does not have |
| FLOAT8 / FLOAT8_ARRAY (16, 52) | No peer in reach writes them; when one does, the table has the code |
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

## The API reference is generated

`docs/api/` is written by `scripts/api.py`, not by hand: it reads
`src/pkg.generated.mbti` for the surface exactly as `moon info` prints it, and
the `///` comments in `src/*.mbt` for the prose, which is why a sentence about a
function lives beside the function. One page per public item, a source link on
each, and a page for the directory itself.

```sh
python3 scripts/api.py     # after changing an interface or a doc comment
```

CI runs the same command and fails if the result differs from what is committed,
so a page cannot outlive the function it describes.

## Specifications

- [Fory cross-language serialization](https://fory.apache.org/docs/specification/fory_xlang_serialization_spec)
- [Fory row format](https://fory.apache.org/docs/specification/fory_row_format_spec)
- [Fory type mapping](https://fory.apache.org/docs/specification/fory_type_mapping)


## Licence

Apache-2.0. See [LICENSE](LICENSE).
