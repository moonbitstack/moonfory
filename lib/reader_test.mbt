// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a dense array is a byte count and then the raw elements" {
  let v : @lib.Value = @lib.loads(@lib.unhex("01ff2e080100000002000000"))
  inspect(v.to_string(), content="List(Int32Array, [Int(1), Int(2)])")
  let bytes : @lib.Value = @lib.loads(@lib.unhex("01ff30020102"))
  inspect(bytes.to_string(), content="List(UInt8Array, [UInt(1), UInt(2)])")
}

///|
test "a dense array of nothing is a byte count of nothing" {
  let v : @lib.Value = @lib.loads(@lib.unhex("01ff2e00"))
  inspect(v.to_string(), content="List(Int32Array, [])")
}

///|
test "the narrow floats are read as doubles" {
  let half : @lib.Value = @lib.loads(@lib.unhex("01ff11003c"))
  inspect(half.to_string(), content="Float(1)")
  let bfloat : @lib.Value = @lib.loads(@lib.unhex("01ff12803f"))
  inspect(bfloat.to_string(), content="Float(1)")
  let single : @lib.Value = @lib.loads(@lib.unhex("01ff130000803f"))
  inspect(single.to_string(), content="Float(1)")
}

///|
test "a string that is not UTF-8 is refused when the reader was asked to check" {
  let outcome = try {
    let _ : @lib.Value = @lib.loads(@lib.unhex("01ff150aff61"))
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome, content="BadEncoding(at=4, got=2)")
  let unchecked : @lib.Value = @lib.loads(
    @lib.unhex("01ff150aff61"),
    check_string=false,
  )
  inspect(unchecked.to_string().has_prefix("Str("), content="true")
}

///|
test "a reference to an id the message has not written is refused" {
  let r = @lib.Reader::new(@lib.unhex("fe05"))
  let outcome = try {
    ignore(r.read_ref_flag())
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome, content="BadRef(at=0, got=5)")
}

///|
test "a chunk of nothing in a map is refused" {
  let outcome = try {
    let _ : @lib.Value = @lib.loads(@lib.unhex("01ff1801000015"))
    "read"
  } catch {
    failure => failure.to_string()
  } noraise {
    _ => "read"
  }
  inspect(outcome.has_prefix("BadEncoding"), content="true")
}
