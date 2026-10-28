// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A message read out loud.
///
///     moon run src/examples/inspect -- 01ff0702
///     moon run src/examples/inspect -- 01ff1511164e4c75
///
/// Given hexadecimal, it reads the message and prints the value in it, or the
/// refusal and where in the bytes it happened. Given nothing, it prints the
/// cross-language types and the ID each one goes out under.
#coverage.skip
fn main {
  let args = @env.args()
  if args.length() < 2 {
    table()
    return
  }
  let mut text = ""
  for i in 1..<args.length() {
    text = text + args[i]
  }
  try {
    let bytes = @base16.decode(text)
    let value : @moonfory.Value = @moonfory.loads(bytes)
    println(@base16.encode(bytes))
    println(value.to_string())
  } catch {
    failure => {
      println(text)
      println("refused  " + failure.to_string())
    }
  } noraise {
    _ => ()
  }
}

///|
/// The cross-language types, and the ID each one goes out under.
fn table() -> Unit {
  println("moonfory - the cross-language types")
  println("")
  for code in 0..<57 {
    match @moonfory.TypeId::of(code) {
      Some(t) => println("  " + pad(code.to_string(), 3) + "  " + t.to_string())
      None => ()
    }
  }
  println("")
  println("usage: moonfory <hexadecimal>")
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
