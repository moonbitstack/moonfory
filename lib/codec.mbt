// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A value that knows how to become bytes, and how to come back from them.
///
/// The contract is one line: **`write_data` and `read_data` are everything after
/// the type ID.** The type ID belongs to whoever knows the schema — a struct
/// field to its `FieldMeta`, a list to its header, a map to its chunk header —
/// and what follows belongs to the value, which is why a struct or an enum
/// writes its user type ID here and not there.
///
/// Everything this package ships implements this trait, and a caller's own type
/// implements it the same way: there is no second path for the types that come
/// with the library.
pub trait Codec {
  /// The type ID: the number that begins a value of this type.
  fn ty(Self) -> TypeId
  /// Everything after the type ID.
  fn write_data(Self, Writer) -> Unit raise
  /// Everything after the type ID, read back. `ty` is what the wire said, which
  /// is not always what the writer would have chosen: a peer's `1` may come as
  /// `VARINT64`, and an integer asked for as thirty-two bits may arrive as
  /// sixty-four.
  fn read_data(Reader, ty : TypeId) -> Self raise
}

///|
pub impl Codec for Bool with fn ty(_self) -> TypeId {
  Bool
}

///|
pub impl Codec for Bool with fn write_data(self, w : Writer) -> Unit raise {
  w.write_bool(self)
}

///|
pub impl Codec for Bool with fn read_data(r : Reader, ty : TypeId) -> Bool raise {
  if ty != Bool {
    raise Refused::WantType(
      at=r.offset(),
      want=TypeId::Bool.code(),
      got=ty.code(),
    )
  }
  r.read_bool()
}

///|
pub impl Codec for Int32 with fn ty(_self) -> TypeId {
  Int32
}

///|
pub impl Codec for Int32 with fn write_data(self, w : Writer) -> Unit raise {
  w.write_i32(self)
}

///|
pub impl Codec for Int32 with fn read_data(r : Reader, ty : TypeId) -> Int32 raise {
  narrow(r, signed(r, ty))
}

///|
pub impl Codec for Int64 with fn ty(_self) -> TypeId {
  Int64
}

///|
pub impl Codec for Int64 with fn write_data(self, w : Writer) -> Unit raise {
  w.write_i64(self)
}

///|
pub impl Codec for Int64 with fn read_data(r : Reader, ty : TypeId) -> Int64 raise {
  signed(r, ty)
}

///|
pub impl Codec for UInt32 with fn ty(_self) -> TypeId {
  UInt32
}

///|
pub impl Codec for UInt32 with fn write_data(self, w : Writer) -> Unit raise {
  w.write_u32(self)
}

///|
pub impl Codec for UInt32 with fn read_data(r : Reader, ty : TypeId) -> UInt32 raise {
  let v = unsigned(r, ty)
  if v > 4_294_967_295UL {
    raise Refused::TooLarge(
      at=r.offset(),
      limit=4_294_967_295L,
      got=v.reinterpret_as_int64(),
    )
  }
  v.to_uint()
}

///|
pub impl Codec for UInt64 with fn ty(_self) -> TypeId {
  UInt64
}

///|
pub impl Codec for UInt64 with fn write_data(self, w : Writer) -> Unit raise {
  w.write_u64(self)
}

///|
pub impl Codec for UInt64 with fn read_data(r : Reader, ty : TypeId) -> UInt64 raise {
  unsigned(r, ty)
}

///|
pub impl Codec for Byte with fn ty(_self) -> TypeId {
  UInt8
}

///|
pub impl Codec for Byte with fn write_data(self, w : Writer) -> Unit raise {
  w.write_u8(self.to_int())
}

///|
pub impl Codec for Byte with fn read_data(r : Reader, ty : TypeId) -> Byte raise {
  let v = unsigned(r, ty)
  if v > 255UL {
    raise Refused::TooLarge(
      at=r.offset(),
      limit=255L,
      got=v.reinterpret_as_int64(),
    )
  }
  v.to_int().to_byte()
}

///|
pub impl Codec for Float with fn ty(_self) -> TypeId {
  Float32
}

///|
pub impl Codec for Float with fn write_data(self, w : Writer) -> Unit raise {
  w.write_f32(self)
}

///|
pub impl Codec for Float with fn read_data(r : Reader, ty : TypeId) -> Float raise {
  Float::from_double(numbers(r, ty))
}

///|
pub impl Codec for Double with fn ty(_self) -> TypeId {
  Float64
}

///|
pub impl Codec for Double with fn write_data(self, w : Writer) -> Unit raise {
  w.write_f64(self)
}

///|
pub impl Codec for Double with fn read_data(r : Reader, ty : TypeId) -> Double raise {
  numbers(r, ty)
}

///|
pub impl Codec for String with fn ty(_self) -> TypeId {
  String
}

///|
pub impl Codec for String with fn write_data(self, w : Writer) -> Unit raise {
  w.write_string(self)
}

///|
pub impl Codec for String with fn read_data(r : Reader, ty : TypeId) -> String raise {
  if ty != String {
    raise Refused::WantType(
      at=r.offset(),
      want=TypeId::String.code(),
      got=ty.code(),
    )
  }
  r.read_string()
}

///|
pub impl Codec for Bytes with fn ty(_self) -> TypeId {
  Binary
}

///|
pub impl Codec for Bytes with fn write_data(self, w : Writer) -> Unit raise {
  w.write_binary(self)
}

///|
pub impl Codec for Bytes with fn read_data(r : Reader, ty : TypeId) -> Bytes raise {
  if ty != Binary {
    raise Refused::WantType(
      at=r.offset(),
      want=TypeId::Binary.code(),
      got=ty.code(),
    )
  }
  r.read_binary()
}

///|
/// Read a signed integer of whatever width the wire chose.
///
/// A peer's small integer is not always the width this side would have picked:
/// Python writes `VARINT64`, Go writes `VARINT64`, and a schema may say
/// `TAGGED_INT64`. The signedness is the contract; the width is not.
fn signed(r : Reader, ty : TypeId) -> Int64 raise {
  match ty {
    Int8 => r.read_i8().to_int64()
    Int16 => r.read_i16().to_int64()
    Int32 => r.read_i32().to_int64()
    VarInt32 => r.read_var_i32().to_int64()
    Int64 => r.read_i64()
    VarInt64 => r.read_var_i64()
    TaggedInt64 => r.read_tagged_i64()
    _ =>
      raise Refused::WantType(
        at=r.offset(),
        want=TypeId::Int32.code(),
        got=ty.code(),
      )
  }
}

///|
/// Read an unsigned integer of whatever width the wire chose.
fn unsigned(r : Reader, ty : TypeId) -> UInt64 raise {
  match ty {
    UInt8 => r.read_u8().reinterpret_as_uint().to_uint64()
    UInt16 => r.read_u16().reinterpret_as_uint().to_uint64()
    UInt32 => r.read_u32().to_uint64()
    VarUInt32 => r.read_var_u32().to_uint64()
    UInt64 => r.read_u64()
    VarUInt64 => r.read_var_u64()
    TaggedUInt64 => r.read_tagged_u64()
    _ =>
      raise Refused::WantType(
        at=r.offset(),
        want=TypeId::UInt64.code(),
        got=ty.code(),
      )
  }
}

///|
/// Read a float of whatever width the wire chose, as a double.
fn numbers(r : Reader, ty : TypeId) -> Double raise {
  match ty {
    Float16 => half(r.read_u16())
    BFloat16 => bfloat(r.read_u16())
    Float32 => r.read_f32().to_double()
    Float64 => r.read_f64()
    _ =>
      raise Refused::WantType(
        at=r.offset(),
        want=TypeId::Float64.code(),
        got=ty.code(),
      )
  }
}

///|
/// A sixty-four-bit integer asked for as thirty-two: refused rather than cut,
/// because a value that silently loses its top half is worse than an error.
fn narrow(r : Reader, v : Int64) -> Int32 raise {
  if v < -2_147_483_648L || v > 2_147_483_647L {
    raise Refused::TooLarge(at=r.offset(), limit=2_147_483_647L, got=v)
  }
  v.to_int()
}

///|
/// A value that may be written more than once, or that takes part in a cycle.
///
/// MoonBit has no identity to infer sharing from — `physical_equal` is a hint
/// and not a promise — so the key is the caller's, the way `Rc` is the caller's
/// in Rust: two writes of the same key send the value once and point at it
/// afterwards.
pub(all) struct Shared[T] {
  /// The name the caller gives the value.
  key : Int32
  /// The value itself.
  value : T
} derive(Eq, Debug)

///|
pub extend Shared with Debug::{to_repr}

///|
pub extend Shared with Eq::{not_equal, equal}

///|
/// Mark a value as one that may be shared.
pub fn[T] shared(key : Int32, value : T) -> Shared[T] {
  { key, value, }
}

///|
pub impl[T : Codec] Codec for Shared[T] with fn ty(self) -> TypeId {
  self.value.ty()
}

///|
pub impl[T : Codec] Codec for Shared[T] with fn write_data(
  self : Shared[T],
  w : Writer,
) -> Unit raise {
  // Tracking is the configuration's business and not the value's: with it off,
  // the flag is the plain not-null one and the body follows, which is what a
  // peer that is not tracking reads.
  if w.config.track_ref {
    if w.write_tracked(self.key) {
      self.value.write_data(w)
    }
  } else {
    w.write_byte(0xFF)
    self.value.write_data(w)
  }
}

///|
pub impl[T : Codec] Codec for Shared[T] with fn read_data(
  r : Reader,
  ty : TypeId,
) -> Shared[T] raise {
  match r.read_ref_flag() {
    Null => raise Refused::BadEncoding(at=r.offset(), got=-3)
    Ref(id~) => {
      let saved = r.enter_ref(id)
      let value = T::read_data(r, ty)
      r.leave_ref(saved)
      { key: id, value, }
    }
    NotNull => { key: -1, value: T::read_data(r, ty), }
    RefValue(id~) => { key: id, value: T::read_data(r, ty), }
  }
}

///|
pub impl[T : Codec] Codec for Array[T] with fn ty(_self) -> TypeId {
  List
}

///|
/// A list: a count, a header byte, the element type, then the elements.
///
/// The element type is written rather than left to the schema, so that a peer
/// reading without one can still read it back; an empty list writes no type at
/// all, having nothing to say about it.
pub impl[T : Codec] Codec for Array[T] with fn write_data(
  self : Array[T],
  w : Writer,
) -> Unit raise {
  w.write_var_u32(self.length().reinterpret_as_uint())
  if self.length() == 0 {
    return
  }
  w.write_byte(0x08)
  w.write_type_id(self[0].ty())
  for item in self {
    item.write_data(w)
  }
}

///|
pub impl[T : Codec] Codec for Array[T] with fn read_data(
  r : Reader,
  ty : TypeId,
) -> Array[T] raise {
  if ty != List && ty != Set {
    raise Refused::WantType(
      at=r.offset(),
      want=TypeId::List.code(),
      got=ty.code(),
    )
  }
  let n = r.read_var_u32().reinterpret_as_int()
  r.spend(n)
  let out : Array[T] = []
  if n == 0 {
    return out
  }
  let header = r.read_byte()
  if (header & 0x02) != 0 {
    raise Refused::Unsupported(kind="list with null elements")
  }
  if (header & 0x04) != 0 {
    raise Refused::Unsupported(kind="list of a declared type")
  }
  if (header & 0x08) != 0 {
    let element = r.read_type_id()
    for _ in 0..<n {
      out.push(T::read_data(r, element))
    }
  } else {
    for _ in 0..<n {
      let element = r.read_type_id()
      out.push(T::read_data(r, element))
    }
  }
  out
}

///|
pub impl[K : Codec + Hash + Eq, V : Codec] Codec for Map[K, V] with fn ty(
  _self : Map[K, V],
) -> TypeId {
  Map
}

///|
/// A map: a count, then chunks of at most two hundred and fifty-five pairs,
/// each chunk saying the two types it holds.
pub impl[K : Codec + Hash + Eq, V : Codec] Codec for Map[K, V] with fn write_data(
  self : Map[K, V],
  w : Writer,
) -> Unit raise {
  let pairs : Array[(K, V)] = []
  for pair in self.iter() {
    pairs.push(pair)
  }
  w.write_var_u32(pairs.length().reinterpret_as_uint())
  let mut at = 0
  while at < pairs.length() {
    let size = if pairs.length() - at > 255 { 255 } else { pairs.length() - at }
    let (_, value) = pairs[at]
    w.write_byte(0x00)
    w.write_byte(size)
    w.write_type_id(Codec::ty(pairs[at].0))
    w.write_type_id(value.ty())
    for i in at..<(at + size) {
      let (k, v) = pairs[i]
      Codec::write_data(k, w)
      Codec::write_data(v, w)
    }
    at = at + size
  }
}

///|
pub impl[K : Codec + Hash + Eq, V : Codec] Codec for Map[K, V] with fn read_data(
  r : Reader,
  ty : TypeId,
) -> Map[K, V] raise {
  if ty != Map {
    raise Refused::WantType(
      at=r.offset(),
      want=TypeId::Map.code(),
      got=ty.code(),
    )
  }
  let total = r.read_var_u32().reinterpret_as_int()
  r.spend(total)
  let out : Map[K, V] = Map([])
  while out.length() < total {
    let header = r.read_byte()
    if (header & 0x02) != 0 || (header & 0x10) != 0 {
      raise Refused::Unsupported(kind="map with a null key or value")
    }
    if (header & 0x04) != 0 || (header & 0x20) != 0 {
      raise Refused::Unsupported(kind="map of a declared type")
    }
    let size = r.read_byte()
    let key_ty = r.read_type_id()
    let val_ty = r.read_type_id()
    for _ in 0..<size {
      out.set(Codec::read_data(r, key_ty), Codec::read_data(r, val_ty))
    }
  }
  out
}

///|
/// Write a value as a complete message: the root's flag, the type ID, then
/// everything after it.
///
/// The flag belongs to the message and not to the value — the specification's
/// `write_ref_or_null` runs here as it runs before a nullable field — so it is
/// written where the message is, and not in `write_data`, which belongs to the
/// value. A message with no value in it is the flag alone.
pub fn[T : Codec] write_message(w : Writer, value : T) -> Unit raise {
  let ty = value.ty()
  if ty == TypeId::NoneType {
    w.write_byte(0xFD)
    return
  }
  if w.config.track_ref {
    let _ = w.write_tracked(root_key)
  } else {
    w.write_byte(0xFF)
  }
  w.write_type_id(ty)
  value.write_data(w)
}

///|
/// Read one complete message: the root's flag first, then the type ID.
///
/// A value that is not there comes back as this type read under `NONE`, which
/// every type answers in its own way: `Value` answers `Null`, and a type that
/// cannot be absent refuses. A reference where the root belongs is a message
/// that begins by pointing at itself, and is refused.
pub fn[T : Codec] read_message(r : Reader) -> T raise {
  match r.read_ref_flag() {
    Null => T::read_data(r, TypeId::NoneType)
    Ref(id~) => raise Refused::BadEncoding(at=r.offset(), got=id)
    NotNull | RefValue(_) => {
      let ty = r.read_type_id()
      T::read_data(r, ty)
    }
  }
}

///|
pub extend Shared with Codec::{write_data, ty, read_data}

///|
/// A value whose type travels with it: the type ID is written by whoever knows
/// the schema, and everything after it — the user type ID for the kinds that
/// carry one, then the body — is here.
pub impl Codec for Value with fn ty(self) -> TypeId {
  self.ty()
}

///|
pub impl Codec for Value with fn write_data(self, w : Writer) -> Unit raise {
  write_value_data(w, self)
}

///|
pub impl Codec for Value with fn read_data(r : Reader, ty : TypeId) -> Value raise {
  read_body(r, ty)
}

///|
pub extend Value with Codec::{write_data, read_data}

///|
/// One value as one message: the head, the type ID, and the value.
///
/// The configuration is the record, then this call's flat mirrors: the library
/// preset is beaten by the record, and the record by the flat mirrors, unless
/// `wins` says otherwise. A flat mirror that contradicts the record beside it is
/// what `clash` arbitrates: taken silently by `wins`, refused, or handed to the
/// caller's function as (the record, the two as one).
pub fn[T : Codec] dumps(
  value : T,
  config? : Config,
  xlang? : Bool,
  track_ref? : Bool,
  check_string? : Bool,
  depth? : Int32,
  fields? : Int32,
  graph? : Int32,
  wins? : Wins,
  clash? : OnClash[Config],
) -> Bytes raise {
  let w = Writer::new(
    config=resolve(
      config, xlang, track_ref, check_string, depth, fields, graph, wins, clash,
    ),
  )
  w.write_head()
  write_message(w, value)
  w.bytes()
}

///|
/// The same, into a buffer the caller keeps: for a stream of messages written
/// one after another, or for a buffer that already holds a header of its own.
///
/// The configuration is the record, then this call's flat mirrors: the library
/// preset is beaten by the record, and the record by the flat mirrors, unless
/// `wins` says otherwise. A flat mirror that contradicts the record beside it is
/// what `clash` arbitrates: taken silently by `wins`, refused, or handed to the
/// caller's function as (the record, the two as one).
pub fn[T : Codec] dump(
  value : T,
  buffer : Buffer,
  config? : Config,
  xlang? : Bool,
  track_ref? : Bool,
  check_string? : Bool,
  depth? : Int32,
  fields? : Int32,
  graph? : Int32,
  wins? : Wins,
  clash? : OnClash[Config],
) -> Unit raise {
  let w = Writer::new(
    config=resolve(
      config, xlang, track_ref, check_string, depth, fields, graph, wins, clash,
    ),
    buffer~,
  )
  w.write_head()
  write_message(w, value)
}

///|
/// Bytes as a value: the head is checked, the value is read, and the bytes left
/// over are refused, because a message with two values in it is two messages.
///
/// `schemas` is what the reader knows about structs: a struct arrives as a user
/// type ID and nothing else. The configuration is the record, then this call's
/// flat mirrors: the library preset is beaten by the record, and the record by
/// the flat mirrors, unless `wins` says otherwise. A flat mirror that
/// contradicts the record beside it is what `clash` arbitrates: taken silently
/// by `wins`, refused, or handed to the caller's function as (the record, the
/// two as one).
pub fn[T : Codec] loads(
  bytes : Bytes,
  schemas~ : Array[StructMeta] = [],
  config? : Config,
  xlang? : Bool,
  track_ref? : Bool,
  check_string? : Bool,
  depth? : Int32,
  fields? : Int32,
  graph? : Int32,
  wins? : Wins,
  clash? : OnClash[Config],
) -> T raise {
  let r = Reader::new(
    bytes,
    schemas~,
    config=resolve(
      config, xlang, track_ref, check_string, depth, fields, graph, wins, clash,
    ),
  )
  r.read_head()
  let value = read_message(r)
  r.end()
  value
}

///|
/// One value read out of a reader the caller owns, which is how several
/// messages written one after another are read back: the reader keeps the
/// position, and its configuration is the reader's.
pub fn[T : Codec] load(reader : Reader) -> T raise {
  read_message(reader)
}
