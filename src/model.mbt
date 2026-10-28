// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The bridge between a description and the wire.
//
// A `@moonmodel.Type` says what a value is in the smallest set of words every
// projection recognises; this format says what a value is with a type ID from a
// fixed table. The mapping is total in one direction and partial in the other,
// and the partial half is where a description this format cannot carry is
// refused instead of guessed at.

///|
/// Every type ID, by the name it is written under.
///
/// A `Raw` description names a wire type in a form no projection reads inside,
/// which is why the table is a list rather than a chain of matches: a name and
/// its type ID are data, and the two directions read from the same list.
let names : Array[(String, TypeId)] = [
  ("unknown", Unknown),
  ("bool", Bool),
  ("int8", Int8),
  ("int16", Int16),
  ("int32", Int32),
  ("var_int32", VarInt32),
  ("int64", Int64),
  ("var_int64", VarInt64),
  ("tagged_int64", TaggedInt64),
  ("uint8", UInt8),
  ("uint16", UInt16),
  ("uint32", UInt32),
  ("var_uint32", VarUInt32),
  ("uint64", UInt64),
  ("var_uint64", VarUInt64),
  ("tagged_uint64", TaggedUInt64),
  ("float8", Float8),
  ("float16", Float16),
  ("bfloat16", BFloat16),
  ("float32", Float32),
  ("float64", Float64),
  ("string", String),
  ("list", List),
  ("set", Set),
  ("map", Map),
  ("enum", Enum),
  ("named_enum", NamedEnum),
  ("struct", Struct),
  ("compatible_struct", CompatibleStruct),
  ("named_struct", NamedStruct),
  ("named_compatible_struct", NamedCompatibleStruct),
  ("ext", Ext),
  ("named_ext", NamedExt),
  ("union", Union),
  ("typed_union", TypedUnion),
  ("named_union", NamedUnion),
  ("none", NoneType),
  ("duration", Duration),
  ("timestamp", Timestamp),
  ("date", Date),
  ("decimal", Decimal),
  ("binary", Binary),
  ("array", Array),
  ("bool_array", BoolArray),
  ("int8_array", Int8Array),
  ("int16_array", Int16Array),
  ("int32_array", Int32Array),
  ("int64_array", Int64Array),
  ("uint8_array", UInt8Array),
  ("uint16_array", UInt16Array),
  ("uint32_array", UInt32Array),
  ("uint64_array", UInt64Array),
  ("float8_array", Float8Array),
  ("float16_array", Float16Array),
  ("bfloat16_array", BFloat16Array),
  ("float32_array", Float32Array),
  ("float64_array", Float64Array),
]

///|
/// The name a type ID is written under, in the form a `Raw` description carries.
fn name_of(ty : TypeId) -> String {
  for (name, one) in names {
    if one == ty {
      return name
    }
  }
  "unknown"
}

///|
/// The type ID a name stands for, when the table has one.
fn ty_of_name(name : String) -> TypeId? {
  for (one, ty) in names {
    if one == name {
      return Some(ty)
    }
  }
  None
}

///|
/// The type ID a kind goes out as.
///
/// The widths are the compact ones — a field that is `Int` goes out as a
/// `VARINT32` and a `Big` as a `VARINT64` — because that is what every peer's
/// own mapping table chooses for the same word, and a field only interoperates
/// when the two sides agree on the type ID as well as on the value.
///
/// A kind the format cannot carry — `Any`, which has no type ID at all — is
/// refused by name.
pub fn TypeId::of_kind(kind : @moonmodel.Type) -> TypeId raise {
  match kind {
    Bool => TypeId::Bool
    Int => VarInt32
    Big => VarInt64
    Real => Float64
    Text => String
    Bytes => Binary
    Stamp => Timestamp
    List(_) => List
    Dict(_) => Map
    Ref(_) => Struct
    Nest(_) => Struct
    Any => raise Refused::Unsupported(kind="model kind any")
    Raw(raw) =>
      match raw {
        Object(fields) =>
          match fields.get("fory") {
            Some(String(name)) =>
              match ty_of_name(name) {
                Some(ty) => ty
                None => raise Refused::Unsupported(kind="model kind \{name}")
              }
            _ => raise Refused::Unsupported(kind="model kind raw")
          }
        _ => raise Refused::Unsupported(kind="model kind raw")
      }
  }
}

///|
/// The kind a type ID stands for, which is how a wire type is described to a
/// projection that has never heard of this format.
///
/// The widths collapse — every signed 32-bit type is `Int`, every 64-bit one a
/// `Big` — because the description is not the place a width is decided. What
/// the vocabulary has no word for is a `Raw` naming the wire type, which is
/// what `Raw` is for; nothing reads inside it, and the wire record beside the
/// description still holds the type ID itself.
pub fn TypeId::kind(self : TypeId) -> @moonmodel.Type {
  match self {
    Bool => @moonmodel.Bool
    Int8 | Int16 | Int32 | VarInt32 | UInt8 | UInt16 | UInt32 | VarUInt32 =>
      @moonmodel.Int
    Int64 | VarInt64 | TaggedInt64 | UInt64 | VarUInt64 | TaggedUInt64 =>
      @moonmodel.Big
    Float8 | Float16 | BFloat16 | Float32 | Float64 => @moonmodel.Real
    String => @moonmodel.Text
    Binary => @moonmodel.Bytes
    Timestamp | Date => @moonmodel.Stamp
    List => @moonmodel.List(@moonmodel.Any)
    Set => @moonmodel.List(@moonmodel.Any)
    Map => @moonmodel.Dict(@moonmodel.Any)
    _ =>
      match self.element() {
        Some(one) => @moonmodel.List(one.kind())
        None => raw_kind(self)
      }
  }
}

///|
/// A description of a wire type the vocabulary has no word for: `{"fory": …}`.
fn raw_kind(ty : TypeId) -> @moonmodel.Type {
  @moonmodel.Raw(Json::object({ "fory": Json::string(name_of(ty)) }))
}
