// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "every type ID is its own code, and every code is mapped" {
  let mut mapped = 0
  for code in 0..<57 {
    match @lib.TypeId::of(code) {
      Some(t) => {
        mapped = mapped + 1
        inspect(t.code(), content=code.to_string())
      }
      None => fail("type \{code} is in the table but is not mapped")
    }
  }
  inspect(mapped, content="57")
}

///|
test "nothing past the table" {
  inspect(@lib.TypeId::of(57) == None, content="true")
  inspect(@lib.TypeId::of(256) == None, content="true")
  inspect(@lib.TypeId::of(-1) == None, content="true")
}

///|
test "the numbers the mapping fixes" {
  inspect(@lib.TypeId::Bool.code(), content="1")
  inspect(@lib.TypeId::String.code(), content="21")
  inspect(@lib.TypeId::List.code(), content="22")
  inspect(@lib.TypeId::Set.code(), content="23")
  inspect(@lib.TypeId::Map.code(), content="24")
  inspect(@lib.TypeId::Struct.code(), content="27")
  inspect(@lib.TypeId::Binary.code(), content="41")
  inspect(@lib.TypeId::NoneType.code(), content="36")
}

///|
test "primitives, compressed integers, and the ones with a fixed width" {
  inspect(@lib.TypeId::Int32.is_primitive(), content="true")
  inspect(@lib.TypeId::String.is_primitive(), content="false")
  inspect(@lib.TypeId::List.is_primitive(), content="false")
  inspect(@lib.TypeId::VarInt64.is_compressed(), content="true")
  inspect(@lib.TypeId::Int32.is_compressed(), content="false")
  inspect(@lib.TypeId::Int32.fixed_size() == Some(4), content="true")
  inspect(@lib.TypeId::VarInt32.fixed_size() == None, content="true")
  inspect(@lib.TypeId::Float32.fixed_size() == Some(4), content="true")
}

///|
test "the collections, the dense arrays, and the types a user names" {
  inspect(@lib.TypeId::List.is_collection(), content="true")
  inspect(@lib.TypeId::Map.is_collection(), content="true")
  inspect(@lib.TypeId::Int32.is_collection(), content="false")
  inspect(@lib.TypeId::Int32Array.is_dense(), content="true")
  inspect(@lib.TypeId::Int32.is_dense(), content="false")
  inspect(
    @lib.TypeId::Int32Array.element() == Some(@lib.TypeId::Int32),
    content="true",
  )
  inspect(
    @lib.TypeId::Int32.arrayed() == Some(@lib.TypeId::Int32Array),
    content="true",
  )
  inspect(@lib.TypeId::String.arrayed() == None, content="true")
  inspect(@lib.TypeId::Struct.is_user(), content="true")
  inspect(@lib.TypeId::Int32.is_user(), content="false")
}
