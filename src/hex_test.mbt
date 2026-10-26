// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "hexadecimal, there and back" {
  inspect(
    @moonfory.hex(@moonfory.unhex("01ff0401000000")),
    content="01ff0401000000",
  )
  inspect(@moonfory.hex(@moonfory.unhex("")), content="")
  inspect(@moonfory.hex(@moonfory.unhex("deadBEEF")), content="deadbeef")
  inspect(@moonfory.hex(@moonfory.unhex("00")), content="00")
}

///|
test "a character that is not hexadecimal says which one and where" {
  try @moonfory.unhex("ab:c") catch {
    failure => inspect(failure, content="BadEncoding(at=2, got=58)")
  } noraise {
    _ => fail("expected the colon to be refused")
  }
}

///|
test "an odd number of digits is refused at the end" {
  try @moonfory.unhex("abc") catch {
    failure => inspect(failure, content="BadEncoding(at=3, got=3)")
  } noraise {
    _ => fail("expected three digits to be refused")
  }
}
