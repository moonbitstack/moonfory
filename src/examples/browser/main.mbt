// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The bytes moonfory writes for one of the home page's samples, as hex, or an
/// empty string for a name it does not know.
pub fn sample(name : String) -> String {
  let bytes = try {
    match name {
      "int" => @moonfory.dumps(42)
      "str" => @moonfory.dumps("ab")
      "bool" => @moonfory.dumps(true)
      "float" => @moonfory.dumps(1.5)
      "list" => @moonfory.dumps([1, 2, 3])
      "map" => @moonfory.dumps({ "a": 1 })
      _ => b""
    }
  } catch {
    _ => b""
  }
  @base16.encode(bytes)
}
