// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn layout(
  kind : @moonmodel.Type,
  bits? : Int32,
  unsigned~ : Bool = false,
) -> @moonmodel.Type {
  Wire(@moonmodel.Layout::new(kind, bits?, unsigned~))
}

///|
test "a field with a byte layout goes out as the type ID of its width and sign" {
  assert_eq(@moonfory.TypeId::of_kind(layout(Int, bits=8)), Int8)
  assert_eq(@moonfory.TypeId::of_kind(layout(Int, bits=16)), Int16)
  assert_eq(@moonfory.TypeId::of_kind(layout(Int, bits=32)), VarInt32)
  assert_eq(@moonfory.TypeId::of_kind(layout(Big, bits=64)), VarInt64)
  assert_eq(
    @moonfory.TypeId::of_kind(layout(Int, bits=8, unsigned=true)),
    UInt8,
  )
  assert_eq(
    @moonfory.TypeId::of_kind(layout(Int, bits=16, unsigned=true)),
    UInt16,
  )
  assert_eq(
    @moonfory.TypeId::of_kind(layout(Int, bits=32, unsigned=true)),
    VarUInt32,
  )
  assert_eq(
    @moonfory.TypeId::of_kind(layout(Big, bits=64, unsigned=true)),
    VarUInt64,
  )
  assert_eq(@moonfory.TypeId::of_kind(layout(Real, bits=32)), Float32)
  assert_eq(@moonfory.TypeId::of_kind(layout(Real, bits=64)), Float64)
  // No width says nothing the kind does not.
  assert_eq(@moonfory.TypeId::of_kind(layout(Int)), VarInt32)
  assert_eq(@moonfory.TypeId::of_kind(layout(Text)), String)
}
