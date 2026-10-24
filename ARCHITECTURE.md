# moonfory · the architecture

One page, so that the shape is settled before the code is: what each file owns,
what each one is allowed to call, and the four interfaces a caller sees.

## The one rule

**Bytes in, bytes out, and nothing else.** No clock, no file, no socket, no
state between calls. A value goes in, bytes come out; bytes go in, a value comes
out. Everything below follows from that.

## The layers

```
        dumps / loads / dump / load        entry: config, head, one value
                    |
        Codec (a trait)                    the extension point: ty / write_data / read_data
                    |
        Value, StructMeta                 the two shapes a value can have
                    |
        Writer / Reader                   the byte primitives the specification fixes
                    |
        Config, TypeId, Refused           the knobs, the table, the one error
```

A lower layer never calls a higher one. `Writer` knows nothing about `Value`;
`Value` is written entirely with `Writer`'s primitives, which is why a type this
package has never heard of can be written with the same calls its own types are.

| File | Owns | Calls down to |
|:--|:--|:--|
| `error.mbt` | `Refused`, `Clashed` | — |
| `type_id.mbt` | `TypeId` and every question asked of it | — |
| `config.mbt` | `Config`, the `config` preset, `Wins`, `OnClash`, and the one resolver that applies them | — |
| `writer.mbt` | every primitive the specification fixes, and the reference table | `Config`, `TypeId` |
| `reader.mbt` | the mirror of those, plus reference bookkeeping, depth and budget, and the schema registry | `Config`, `TypeId`, `Value` |
| `struct.mbt` | `FieldMeta`, `StructMeta`, and the Fory field order | `TypeId` |
| `value.mbt` | `Value`, and how a container, a struct, an enum, a time and a decimal are framed | `Writer`, `Reader`, `StructMeta` |
| `codec.mbt` | the `Codec` trait, its implementations, and the four entry points | everything above |
| `row.mbt` | the row format: a schema, a writer, and random access | `Writer`, `Reader`, `TypeId` |
| `time.mbt` | DATE, TIMESTAMP and DURATION, wired to `moondate` | `Codec`, `@moondate` |
| `hex.mbt` | `hex`/`unhex`, so a test can compare a fixture as text | — |

## The four interfaces

### 1. `Codec` — the extension point

```moonbit
pub trait Codec {
  ty(Self) -> TypeId                     // what it goes out as
  write_data(Self, Writer) -> Unit       // the body only; the envelope is not its business
  read_data(Reader, TypeId) -> Self raise // the body only; the ID says which width arrived
}
```

The body is written without its type meta and without its reference flag,
because those belong to whoever knows the schema: a struct field knows from its
`FieldMeta`, a list from its header, a map from its chunk header. That is why
one trait covers both the declared and the polymorphic case.

Everything this package ships implements it — `Bool`, `Int`, `Int64`, `Byte`,
`UInt`, `UInt64`, `Float`, `Double`, `String`, `Bytes`, `Value`, `Shared[T]`,
`T?` — and a caller's own type implements it the same way. There is no second,
privileged path.

### 2. `Value` — a value whose type travels with it

What `loads` builds when the caller has no schema: the cross-language types, the
containers, a struct with its `StructMeta`, an enum, and the three time types.
An integer of any width reads as `Int`, and a float of any width as `Float`,
because a value read without a schema has no width to be.

### 3. `StructMeta` — the schema MoonBit cannot generate

MoonBit has no `derive` a package outside the compiler can extend, so a schema
is written down once per type: a name, a user type ID, and the fields with their
type, tag, nullability and reference policy. `StructMeta::order` turns the
declaration order into the Fory order, which is the order every language writes.

### 4. `Config` — the knobs, in the house shape

A record with a preset of the same name, flat mirrors on the entry points, and
`wins`/`clash` over the two. Every default is the Rust `fory` crate's
`Config::default()`, and each one says so where it is declared.

### 5. `RowSchema` / `RowCursor` — the row format's two ends

A row is built against a schema and read against the same schema: `Row::set`
places a `RowValue`, `Row::finish` lays out the bitmap, the slots and the
variable region, and `RowCursor` reads one field at a time. A nested struct is a
whole row in the variable region, so the writer and the reader recurse instead of
special-casing depth.

## How the four meet

| A caller wants | Uses | Goes out as |
|:--|:--|:--|
| one scalar | `dumps(42)` | head, type meta, body |
| a list | `dumps([1, 2, 3])` | `LIST`, count, header, elements |
| a struct | `dumps(Struct)` | `STRUCT`, user ID, fields in Fory order |
| a value with no type | `dumps(Value)` | the type meta of whatever it is |
| a shared or cyclic graph | `shared(key, value)` | `0x00` the first time, `0xFE` after |
| a caller's own type | `impl Codec` | exactly what the impl writes |

## What is deliberately not here

| Thing | Why |
|:--|:--|
| Compatible mode (schema evolution) | It is a second format over the same bytes — TypeDefs, meta strings, a schema hash — and the acceptance list asks for the xlang format, the row format and the type mapping. It comes with `moonmodel`, which owns the field descriptions it needs. |
| `FLOAT8` (16) and `FLOAT8_ARRAY` (52) | The specification added them recently and no peer in the interop set writes them; a refusal names them rather than guessing a conversion. |
| Writing a shared reference from a `Value` | MoonBit has no identity to infer sharing from, so the dynamic writer sends every value as new. Sharing is a thing the typed writer does with `shared`. |
| Reading a struct without its schema | Same-schema mode is the mode implemented; the schema is the agreement. A struct whose user ID is not registered is refused, not guessed at. |
