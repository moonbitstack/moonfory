// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The internal type ID: the byte that begins a value's type meta, and the
/// number every language agrees on.
///
/// The numbers are the specification's, and they are not ours to choose: a
/// reader in Go reads `21` as a string because the type mapping says so. The
/// variant names are the specification's too, except `NoneType`, which Python
/// calls `NoneType` and the table calls `NONE`; MoonBit spells nothing `None`,
/// so the spelling here is Python's.
pub(all) enum TypeId {
  Unknown
  Bool
  Int8
  Int16
  Int32
  VarInt32
  Int64
  VarInt64
  TaggedInt64
  UInt8
  UInt16
  UInt32
  VarUInt32
  UInt64
  VarUInt64
  TaggedUInt64
  Float8
  Float16
  BFloat16
  Float32
  Float64
  String
  List
  Set
  Map
  Enum
  NamedEnum
  Struct
  CompatibleStruct
  NamedStruct
  NamedCompatibleStruct
  Ext
  NamedExt
  Union
  TypedUnion
  NamedUnion
  NoneType
  Duration
  Timestamp
  Date
  Decimal
  Binary
  Array
  BoolArray
  Int8Array
  Int16Array
  Int32Array
  Int64Array
  UInt8Array
  UInt16Array
  UInt32Array
  UInt64Array
  Float8Array
  Float16Array
  BFloat16Array
  Float32Array
  Float64Array
} derive(Eq, Debug)

///|
pub extend TypeId with Eq::{not_equal, equal}

///|
pub extend TypeId with Debug::{to_repr}

///|
/// The name of the type, which is how a fixture and an error message name it.
pub impl Show for TypeId with fn output(self, logger) {
  logger.write_string("\{self.to_repr()}")
}

///|
pub extend TypeId with Show::{to_string, output}

///|
/// The number on the wire.
pub fn TypeId::code(self : TypeId) -> Int32 {
  match self {
    Unknown => 0
    Bool => 1
    Int8 => 2
    Int16 => 3
    Int32 => 4
    VarInt32 => 5
    Int64 => 6
    VarInt64 => 7
    TaggedInt64 => 8
    UInt8 => 9
    UInt16 => 10
    UInt32 => 11
    VarUInt32 => 12
    UInt64 => 13
    VarUInt64 => 14
    TaggedUInt64 => 15
    Float8 => 16
    Float16 => 17
    BFloat16 => 18
    Float32 => 19
    Float64 => 20
    String => 21
    List => 22
    Set => 23
    Map => 24
    Enum => 25
    NamedEnum => 26
    Struct => 27
    CompatibleStruct => 28
    NamedStruct => 29
    NamedCompatibleStruct => 30
    Ext => 31
    NamedExt => 32
    Union => 33
    TypedUnion => 34
    NamedUnion => 35
    NoneType => 36
    Duration => 37
    Timestamp => 38
    Date => 39
    Decimal => 40
    Binary => 41
    Array => 42
    BoolArray => 43
    Int8Array => 44
    Int16Array => 45
    Int32Array => 46
    Int64Array => 47
    UInt8Array => 48
    UInt16Array => 49
    UInt32Array => 50
    UInt64Array => 51
    Float8Array => 52
    Float16Array => 53
    BFloat16Array => 54
    Float32Array => 55
    Float64Array => 56
  }
}

///|
/// The type a number on the wire stands for, when the mapping has one.
///
/// `57` and up are unmapped: the specification reserves them, and a reader that
/// met one could not know what to build.
pub fn TypeId::of(code : Int32) -> TypeId? {
  match code {
    0 => Some(Unknown)
    1 => Some(Bool)
    2 => Some(Int8)
    3 => Some(Int16)
    4 => Some(Int32)
    5 => Some(VarInt32)
    6 => Some(Int64)
    7 => Some(VarInt64)
    8 => Some(TaggedInt64)
    9 => Some(UInt8)
    10 => Some(UInt16)
    11 => Some(UInt32)
    12 => Some(VarUInt32)
    13 => Some(UInt64)
    14 => Some(VarUInt64)
    15 => Some(TaggedUInt64)
    16 => Some(Float8)
    17 => Some(Float16)
    18 => Some(BFloat16)
    19 => Some(Float32)
    20 => Some(Float64)
    21 => Some(String)
    22 => Some(List)
    23 => Some(Set)
    24 => Some(Map)
    25 => Some(Enum)
    26 => Some(NamedEnum)
    27 => Some(Struct)
    28 => Some(CompatibleStruct)
    29 => Some(NamedStruct)
    30 => Some(NamedCompatibleStruct)
    31 => Some(Ext)
    32 => Some(NamedExt)
    33 => Some(Union)
    34 => Some(TypedUnion)
    35 => Some(NamedUnion)
    36 => Some(NoneType)
    37 => Some(Duration)
    38 => Some(Timestamp)
    39 => Some(Date)
    40 => Some(Decimal)
    41 => Some(Binary)
    42 => Some(Array)
    43 => Some(BoolArray)
    44 => Some(Int8Array)
    45 => Some(Int16Array)
    46 => Some(Int32Array)
    47 => Some(Int64Array)
    48 => Some(UInt8Array)
    49 => Some(UInt16Array)
    50 => Some(UInt32Array)
    51 => Some(UInt64Array)
    52 => Some(Float8Array)
    53 => Some(Float16Array)
    54 => Some(BFloat16Array)
    55 => Some(Float32Array)
    56 => Some(Float64Array)
    _ => None
  }
}

///|
/// Whether a field of this type belongs to the primitive groups when the field
/// order is decided: numbers and booleans, not strings and not containers.
pub fn TypeId::is_primitive(self : TypeId) -> Bool {
  match self {
    Bool
    | Int8
    | Int16
    | Int32
    | VarInt32
    | Int64
    | VarInt64
    | TaggedInt64
    | UInt8
    | UInt16
    | UInt32
    | VarUInt32
    | UInt64
    | VarUInt64
    | TaggedUInt64
    | Float8
    | Float16
    | BFloat16
    | Float32
    | Float64 => true
    _ => false
  }
}

///|
/// Whether the width of this type is decided by the value rather than by the
/// type: the compressed integers, which sort after every fixed-width one.
pub fn TypeId::is_compressed(self : TypeId) -> Bool {
  match self {
    VarInt32 | VarInt64 | TaggedInt64 | VarUInt32 | VarUInt64 | TaggedUInt64 =>
      true
    _ => false
  }
}

///|
/// How many bytes a value of this type occupies, when the type decides it.
///
/// `None` for the compressed integers and for everything whose length is part
/// of the value.
pub fn TypeId::fixed_size(self : TypeId) -> Int32? {
  match self {
    Bool | Int8 | UInt8 | Float8 => Some(1)
    Int16 | UInt16 | Float16 | BFloat16 => Some(2)
    Int32 | UInt32 | Float32 => Some(4)
    Int64 | UInt64 | Float64 => Some(8)
    _ => None
  }
}

///|
/// Whether a value of this kind names a type of the writer's own, and so
/// carries a user type ID or type meta after the type ID byte.
///
/// These are the kinds a field must write type information for. An enum or a
/// union inside a struct field does not: its type is the field's declared one.
pub fn TypeId::is_user(self : TypeId) -> Bool {
  match self {
    Struct
    | CompatibleStruct
    | NamedStruct
    | NamedCompatibleStruct
    | Ext
    | NamedExt
    | Enum
    | NamedEnum
    | Union
    | TypedUnion
    | NamedUnion => true
    _ => false
  }
}

///|
/// Whether this kind is one of the five that hold a user type ID in
/// same-schema mode: the four that a struct can be, and the enum.
pub fn TypeId::is_named_by_id(self : TypeId) -> Bool {
  match self {
    Struct | CompatibleStruct | NamedStruct | NamedCompatibleStruct | Enum =>
      true
    _ => false
  }
}

///|
/// Whether values of this kind are counted: a list, a set or a map.
pub fn TypeId::is_collection(self : TypeId) -> Bool {
  match self {
    List | Set | Map => true
    _ => false
  }
}

///|
/// Whether this kind is one of the dense primitive arrays: a run of raw
/// little-endian elements rather than a list of values.
pub fn TypeId::is_dense(self : TypeId) -> Bool {
  match self {
    BoolArray
    | Int8Array
    | Int16Array
    | Int32Array
    | Int64Array
    | UInt8Array
    | UInt16Array
    | UInt32Array
    | UInt64Array
    | Float8Array
    | Float16Array
    | BFloat16Array
    | Float32Array
    | Float64Array => true
    _ => false
  }
}

///|
/// The element type of a dense array, which is what the bytes are.
pub fn TypeId::element(self : TypeId) -> TypeId? {
  match self {
    BoolArray => Some(Bool)
    Int8Array => Some(Int8)
    Int16Array => Some(Int16)
    Int32Array => Some(Int32)
    Int64Array => Some(Int64)
    UInt8Array => Some(UInt8)
    UInt16Array => Some(UInt16)
    UInt32Array => Some(UInt32)
    UInt64Array => Some(UInt64)
    Float8Array => Some(Float8)
    Float16Array => Some(Float16)
    BFloat16Array => Some(BFloat16)
    Float32Array => Some(Float32)
    Float64Array => Some(Float64)
    _ => None
  }
}

///|
/// The dense array of this element type, when there is one.
///
/// Only the fourteen element types above have one; `array<string>` stays a
/// list, which is why the answer is optional.
pub fn TypeId::arrayed(self : TypeId) -> TypeId? {
  match self {
    Bool => Some(BoolArray)
    Int8 => Some(Int8Array)
    Int16 => Some(Int16Array)
    Int32 => Some(Int32Array)
    Int64 => Some(Int64Array)
    UInt8 => Some(UInt8Array)
    UInt16 => Some(UInt16Array)
    UInt32 => Some(UInt32Array)
    UInt64 => Some(UInt64Array)
    Float8 => Some(Float8Array)
    Float16 => Some(Float16Array)
    BFloat16 => Some(BFloat16Array)
    Float32 => Some(Float32Array)
    Float64 => Some(Float64Array)
    _ => None
  }
}
