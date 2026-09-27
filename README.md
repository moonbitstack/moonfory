# moonfory

A MoonBit value, written so that Java, Go or Python reads it back as its own.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

[Apache Fory](https://github.com/apache/fory) is a cross-language serialization
framework, and — the part that matters here — **its wire formats are specified
apart from any one implementation**. That makes it something to implement, not
something to bind to.

| Package | What it covers |
|:--|:--|
| `xlang` | The cross-language binary format: the default when the two ends are different languages |
| `row` | The row format: random access to a field without rebuilding the object |
| `types` | The cross-language type mapping, and what has no counterpart on our side |
| `refs` | Shared and circular references, which are the reason this is not just a tagged encoder |

## Why implement it rather than invent one

The same reason [`moonseal`](https://github.com/moonbitstack/moonseal) starts
from age: **the specification is published and so are the other languages'
implementations**, which means a first version can be proved right against
something outside itself. Eleven languages already speak this format; being the
twelfth is worth more than being the only speaker of a better one.

## What is deliberately elsewhere

| Thing | Where it lives |
|:--|:--|
| Describing the fields of a type | [`moonmodel`](https://github.com/moonbitstack/moonmodel) — MoonBit has no user-extensible `derive`, so the description is written or generated once and read by everything, this included |
| Turning numbers into bytes | [`moonvar`](https://github.com/moonbitstack/moonvar) |
| JSON | [`moonjson`](https://github.com/moonbitstack/moonjson). Fory has a JSON mode; ours is already written |

Nothing in this family depends on it. It is a codec a caller chooses, the way
they would choose protobuf — not a layer anything sits on.

## Install

```bash
moon add moonbitstack/moonfory
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
