// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a read says, or the refusal it met instead.
fn outcome(f : () -> Unit raise) -> String {
  try {
    f()
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
}

///|
/// `n` lists, one inside the next.
fn nest(n : Int32) -> @moonfory.Value {
  let mut v = @moonfory.Value::Int(1L)
  for _ in 0..<n {
    v = @moonfory.Value::List(@moonfory.TypeId::List, [v])
  }
  v
}

///|
test "a typed value is written in the width its type asks for" {
  inspect(@moonfory.hex(@moonfory.dumps(1)), content="01ff0401000000")
  inspect(@moonfory.hex(@moonfory.dumps(1L)), content="01ff060100000000000000")
  inspect(@moonfory.hex(@moonfory.dumps(1U)), content="01ff0b01000000")
  inspect(@moonfory.hex(@moonfory.dumps(1UL)), content="01ff0d0100000000000000")
  inspect(@moonfory.hex(@moonfory.dumps(true)), content="01ff0101")
  inspect(@moonfory.hex(@moonfory.dumps(1.5)), content="01ff14000000000000f83f")
  inspect(@moonfory.hex(@moonfory.dumps("ab")), content="01ff150a6162")
}

///|
test "a typed value is read in whatever width the peer chose" {
  let narrow : Int32 = @moonfory.loads(@moonfory.unhex("01ff0702"))
  inspect(narrow, content="1")
  let wide : Int64 = @moonfory.loads(@moonfory.unhex("01ff0401000000"))
  inspect(wide, content="1")
  let tiny : Int32 = @moonfory.loads(@moonfory.unhex("01ff0201"))
  inspect(tiny, content="1")
  let unsigned : UInt64 = @moonfory.loads(@moonfory.unhex("01ff0b01000000"))
  inspect(unsigned, content="1")
}

///|
test "a sixty-four-bit integer asked for as thirty-two is refused, not cut" {
  inspect(
    outcome(fn() raise {
      let _ : Int32 = @moonfory.loads(@moonfory.unhex("01ff07808080808040"))
      ()
    }).has_prefix("TooLarge"),
    content="true",
  )
  inspect(
    outcome(fn() raise {
      let _ : UInt32 = @moonfory.loads(
        @moonfory.unhex("01ff0d0000000001000000"),
      )
      ()
    }).has_prefix("TooLarge"),
    content="true",
  )
}

///|
test "a message that is not one is refused, and says where" {
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(@moonfory.unhex("00ff0702"))
      ()
    }),
    content="BadHeader(at=0, got=0)",
  )
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(@moonfory.unhex("01ff040100"))
      ()
    }),
    content="Truncated(at=3, want=4, got=2)",
  )
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(
        @moonfory.unhex("01ff070201ff0702"),
      )
      ()
    }),
    content="Trailing(at=4, got=4)",
  )
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(@moonfory.unhex("01ff3901"))
      ()
    }),
    content="BadType(at=2, got=57)",
  )
}

///|
test "a message nested deeper than the reader allows is refused before the stack is" {
  let five = @moonfory.dumps(nest(5))
  let back : @moonfory.Value = @moonfory.loads(five)
  inspect(back == nest(5), content="true")
  let six = @moonfory.dumps(nest(6))
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(six)
      ()
    }).has_prefix("TooDeep"),
    content="true",
  )
}

///|
test "a message that declares more payload than the reader allows is refused" {
  let out = StringBuilder()
  for _ in 0..<200 {
    out.write_char('x')
  }
  let bytes = @moonfory.dumps(@moonfory.Value::Str(out.to_string()))
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(bytes, graph=10)
      ()
    }).has_prefix("TooLarge"),
    content="true",
  )
}

///|
test "the cross-language flag is written either way, and read the way it was asked for" {
  let bytes = @moonfory.dumps(@moonfory.Value::Int(1L), xlang=false)
  inspect(@moonfory.hex(bytes), content="00ff060100000000000000")
  let back : @moonfory.Value = @moonfory.loads(bytes, xlang=false)
  inspect(back, content="Int(1)")
  inspect(
    outcome(fn() raise {
      let _ : @moonfory.Value = @moonfory.loads(bytes)
      ()
    }),
    content="BadHeader(at=0, got=0)",
  )
}

///|
test "a value written twice is sent once and pointed at, when tracking is on" {
  let bytes = @moonfory.dumps(
    [@moonfory.shared(7, "once"), @moonfory.shared(7, "once")],
    track_ref=true,
  )
  inspect(@moonfory.hex(bytes), content="01001602081500126f6e6365fe01")
  let back : Array[@moonfory.Shared[String]] = @moonfory.loads(
    bytes,
    track_ref=true,
  )
  inspect(back.length(), content="2")
  inspect(back[0].value, content="once")
  inspect(back[1].value, content="once")
}

///|
test "with tracking off, a shared value is written as itself, twice" {
  let bytes = @moonfory.dumps([
    @moonfory.shared(7, "once"),
    @moonfory.shared(7, "once"),
  ])
  inspect(@moonfory.hex(bytes), content="01ff16020815ff126f6e6365ff126f6e6365")
  let back : Array[@moonfory.Shared[String]] = @moonfory.loads(bytes)
  inspect(back.length(), content="2")
}

///|
test "the library preset is beaten by the record, and the record by the flat mirrors" {
  let given = @moonfory.Config::new(track_ref=false)
  let merged = @moonfory.resolve(
    Some(given),
    None,
    Some(true),
    None,
    None,
    None,
    None,
    None,
    None,
  )
  inspect(merged.track_ref, content="true")
  let preset = @moonfory.resolve(
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
  )
  inspect(preset.depth, content="5")
  inspect(preset.fields, content="512")
}

///|
test "wins turns the order around" {
  let given = @moonfory.Config::new(track_ref=false)
  let base = @moonfory.resolve(
    Some(given),
    None,
    Some(true),
    None,
    None,
    None,
    None,
    Some(@moonfory.Wins::Base),
    None,
  )
  inspect(base.track_ref, content="false")
}

///|
test "a setting given twice is refused when the caller asks to hear about it" {
  inspect(
    outcome(fn() raise {
      let _ = @moonfory.resolve(
        Some(@moonfory.Config::new(track_ref=false)),
        None,
        Some(true),
        None,
        None,
        None,
        None,
        None,
        Some(@moonfory.OnClash::Panic),
      )
      ()
    }),
    content="Clashed(name=config)",
  )
}

///|
test "the same setting twice agreed on is not a clash" {
  let same = @moonfory.resolve(
    Some(@moonfory.Config::new(track_ref=false)),
    None,
    Some(false),
    None,
    None,
    None,
    None,
    None,
    Some(@moonfory.OnClash::Panic),
  )
  inspect(same.track_ref, content="false")
}

///|
test "a setting given twice can be handed to the caller's own function" {
  let handled = @moonfory.resolve(
    Some(@moonfory.Config::new(depth=9)),
    None,
    None,
    None,
    Some(2),
    None,
    None,
    None,
    Some(
      @moonfory.OnClash::Handle(fn(record, merged) {
        if record.depth > merged.depth {
          record
        } else {
          merged
        }
      }),
    ),
  )
  inspect(handled.depth, content="9")
}

///|
test "a stream of messages written one after another is read back in order" {
  let buffer = Buffer()
  @moonfory.dump(@moonfory.Value::Int(1L), buffer)
  @moonfory.dump(@moonfory.Value::Int(2L), buffer)
  let reader = @moonfory.Reader::new(buffer.to_bytes())
  reader.read_head()
  let first : @moonfory.Value = @moonfory.load(reader)
  inspect(first, content="Int(1)")
  reader.read_head()
  let second : @moonfory.Value = @moonfory.load(reader)
  inspect(second, content="Int(2)")
  inspect(reader.is_done(), content="true")
}
