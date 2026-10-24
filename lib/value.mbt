// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A value whose type travels with it.
///
/// A message written by another language arrives with nothing but its bytes, so
/// this is what `loads` builds when the caller has no schema to hand: the
/// cross-language types, the containers, and the three time types.
///
/// An integer of any width reads as `Int` or `UInt` at sixty-four bits, and a
/// float of any width as `Float`, because a value read without a schema has no
/// width to be. The typed codecs keep the width they were given.
pub(all) enum Value {
  /// Nothing, which is what a nullable field holds when it holds nothing.
  Null
  /// `1` or `0`, one byte.
  Bool(Bool)
  /// A signed integer of any width, at sixty-four.
  Int(Int64)
  /// An unsigned integer of any width, at sixty-four.
  UInt(UInt64)
  /// A float of any width, at double.
  Float(Double)
  /// A string, in whichever of the three encodings it arrived in.
  Str(String)
  /// Bytes: the BINARY type.
  Binary(Bytes)
  /// A list or a set: which one, and the elements.
  List(TypeId, Array[Value])
  /// A map: the pairs, in the order they were written.
  Map(Array[(Value, Value)])
  /// A struct: its schema, and its fields by name.
  Struct(StructMeta, Array[(String, Value)])
  /// An enum: the user type ID of its type, and the variant's ID.
  Enum(Int32, Int32)
  /// Seconds and nanoseconds since the epoch: the TIMESTAMP type.
  Timestamp(Int64, Int32)
  /// Days since the epoch: the DATE type.
  Date(Int64)
  /// Seconds and nanoseconds: the DURATION type.
  Duration(Int64, Int32)
  /// A decimal: the scale, and the unscaled value.
  Decimal(Int32, BigInt)
} derive(Eq, Debug)

///|
/// A value, as text.
///
/// Bytes are hexadecimal and a string is quoted, because a value read out of
/// someone else's message is read by eye first: `Binary(6162)` and
/// `Str("ab")` are the same six bytes in two shapes, and the printed form is
/// what tells them apart.
pub impl Show for Value with fn output(self, logger) {
  match self {
    Null => logger.write_string("Null")
    Bool(b) => logger.write_string("Bool(\{b})")
    Int(i) => logger.write_string("Int(\{i})")
    UInt(u) => logger.write_string("UInt(\{u})")
    Float(d) => logger.write_string("Float(\{d})")
    Str(s) => logger.write_string("Str(\"" + s + "\")")
    Binary(b) => logger.write_string("Binary(" + hex(b) + ")")
    List(kind, items) => {
      logger.write_string("List(" + kind.to_string() + ", [")
      for i in 0..<items.length() {
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string(items[i].to_string())
      }
      logger.write_string("])")
    }
    Map(entries) => {
      logger.write_string("Map([")
      for i in 0..<entries.length() {
        let (k, v) = entries[i]
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string("(" + k.to_string() + ", " + v.to_string() + ")")
      }
      logger.write_string("])")
    }
    Struct(meta, fields) => {
      logger.write_string("Struct(\{meta.user}, [")
      for i in 0..<fields.length() {
        let (name, v) = fields[i]
        if i > 0 {
          logger.write_string(", ")
        }
        logger.write_string(name + ": " + v.to_string())
      }
      logger.write_string("])")
    }
    Enum(user, ordinal) => logger.write_string("Enum(\{user}, \{ordinal})")
    Timestamp(seconds, nanos) =>
      logger.write_string("Timestamp(\{seconds}, \{nanos})")
    Date(days) => logger.write_string("Date(\{days})")
    Duration(seconds, nanos) =>
      logger.write_string("Duration(\{seconds}, \{nanos})")
    Decimal(scale, unscaled) =>
      logger.write_string("Decimal(\{scale}, \{unscaled})")
  }
}

///|
pub extend Value with Debug::{to_repr}

///|
pub extend Value with Show::{to_string, output}

///|
pub extend Value with Eq::{not_equal, equal}

///|
/// The type ID this value goes out as.
pub fn Value::ty(self : Value) -> TypeId {
  match self {
    Null => NoneType
    Bool(_) => Bool
    Int(_) => Int64
    UInt(_) => UInt64
    Float(_) => Float64
    Str(_) => String
    Binary(_) => Binary
    List(kind, _) => kind
    Map(_) => Map
    Struct(_, _) => Struct
    Enum(_, _) => Enum
    Timestamp(_, _) => Timestamp
    Date(_) => Date
    Duration(_, _) => Duration
    Decimal(_, _) => Decimal
  }
}

///|
/// Write a value: the type meta that says what it is, then the body.
pub fn write_value(w : Writer, v : Value) -> Unit raise {
  w.write_type_id(v.ty())
  write_value_data(w, v)
}

///|
/// Everything a value writes after its type ID: the user type ID for the kinds
/// that carry one, then the body.
pub fn write_value_data(w : Writer, v : Value) -> Unit raise {
  match v {
    Struct(meta, _) => w.write_var_u32(meta.user.reinterpret_as_uint())
    Enum(user, _) => w.write_var_u32(user.reinterpret_as_uint())
    _ => ()
  }
  write_body(w, v)
}

///|
/// Read a value: the type meta says what to build, and the body fills it.
pub fn read_value(r : Reader) -> Value raise {
  read_body_of(r, r.read_type_id())
}

///|
/// Write the body of a value whose type meta is already on the wire: what a
/// list element and a struct field are, once the header or the schema has said
/// what they are.
pub fn write_body(w : Writer, v : Value) -> Unit raise {
  match v {
    Null => ()
    Bool(b) => w.write_bool(b)
    Int(i) => w.write_i64(i)
    UInt(u) => w.write_u64(u)
    Float(d) => w.write_f64(d)
    Str(s) => w.write_string(s)
    Binary(b) => w.write_binary(b)
    List(_, items) => write_list_body(w, items)
    Map(entries) => write_map_body(w, entries)
    Struct(meta, fields) => write_struct_body(w, meta, fields)
    Enum(_, ordinal) => w.write_var_u32(ordinal.reinterpret_as_uint())
    Timestamp(seconds, nanos) => {
      w.write_i64(seconds)
      w.write_u32(nanos.reinterpret_as_uint())
    }
    Date(days) => w.write_var_i64(days)
    Duration(seconds, nanos) => {
      w.write_var_i64(seconds)
      w.write_i32(nanos)
    }
    Decimal(scale, unscaled) => write_decimal(w, scale, unscaled)
  }
}

///|
/// Write a value as the type its schema named, rather than the one the value
/// would have picked for itself.
///
/// A struct field is four bytes wide because its schema says `INT32`, not
/// because the value happens to be small: the schema is what a peer reads the
/// field by, so the width is the schema's and not the value's. A value that
/// cannot be written as the type named — a string where an integer was
/// declared — is refused rather than written as something else.
fn write_body_as(w : Writer, ty : TypeId, v : Value) -> Unit raise {
  match (ty, v) {
    (Bool, Bool(b)) => w.write_bool(b)
    (Int8, Int(i)) => w.write_i8(i.to_int())
    (Int16, Int(i)) => w.write_i16(i.to_int())
    (Int32, Int(i)) => w.write_i32(i.to_int())
    (VarInt32, Int(i)) => w.write_var_i32(i.to_int())
    (Int64, Int(i)) => w.write_i64(i)
    (VarInt64, Int(i)) => w.write_var_i64(i)
    (TaggedInt64, Int(i)) => w.write_tagged_i64(i)
    (UInt8, UInt(u)) => w.write_u8(u.reinterpret_as_int64().to_int())
    (UInt16, UInt(u)) => w.write_u16(u.reinterpret_as_int64().to_int())
    (UInt32, UInt(u)) => w.write_u32(u.to_uint())
    (VarUInt32, UInt(u)) => w.write_var_u32(u.to_uint())
    (UInt64, UInt(u)) => w.write_u64(u)
    (VarUInt64, UInt(u)) => w.write_var_u64(u)
    (TaggedUInt64, UInt(u)) => w.write_tagged_u64(u)
    (Float32, Float(d)) => w.write_f32(Float::from_double(d))
    (Float64, Float(d)) => w.write_f64(d)
    (String, Str(s)) => w.write_string(s)
    (Binary, Binary(b)) => w.write_binary(b)
    (_, _) =>
      if ty == v.ty() {
        write_value_data(w, v)
      } else {
        raise Refused::WantType(
          at=w.length(),
          want=ty.code(),
          got=v.ty().code(),
        )
      }
  }
}

///|
/// Read the body of a value whose type is already known.
pub fn read_body(r : Reader, ty : TypeId) -> Value raise {
  match ty {
    NoneType => Null
    Bool => Bool(r.read_bool())
    Int8 => Int(r.read_i8().to_int64())
    Int16 => Int(r.read_i16().to_int64())
    Int32 => Int(r.read_i32().to_int64())
    VarInt32 => Int(r.read_var_i32().to_int64())
    Int64 => Int(r.read_i64())
    VarInt64 => Int(r.read_var_i64())
    TaggedInt64 => Int(r.read_tagged_i64())
    UInt8 => UInt(r.read_u8().reinterpret_as_uint().to_uint64())
    UInt16 => UInt(r.read_u16().reinterpret_as_uint().to_uint64())
    UInt32 => UInt(r.read_u32().to_uint64())
    VarUInt32 => UInt(r.read_var_u32().to_uint64())
    UInt64 => UInt(r.read_u64())
    VarUInt64 => UInt(r.read_var_u64())
    TaggedUInt64 => UInt(r.read_tagged_u64())
    Float16 => Float(half(r.read_u16()))
    BFloat16 => Float(bfloat(r.read_u16()))
    Float32 => Float(r.read_f32().to_double())
    Float64 => Float(r.read_f64())
    String => Str(r.read_string())
    Binary => Binary(r.read_binary())
    List => read_list_body(r, List)
    Set => read_list_body(r, Set)
    Map => read_map_body(r)
    Timestamp => {
      let seconds = r.read_i64()
      Timestamp(seconds, r.read_u32().reinterpret_as_int())
    }
    Date => Date(r.read_var_i64())
    Duration => {
      let seconds = r.read_var_i64()
      Duration(seconds, r.read_i32())
    }
    Decimal => read_decimal(r)
    Struct | CompatibleStruct | NamedStruct | NamedCompatibleStruct =>
      read_struct_body(r)
    Enum | NamedEnum => {
      let user = r.read_var_u32().reinterpret_as_int()
      Enum(user, r.read_var_u32().reinterpret_as_int())
    }
    Float8 => raise Refused::Unsupported(kind="float8")
    Array => raise Refused::Unsupported(kind="array")
    _ =>
      if ty.is_dense() {
        read_dense(r, ty)
      } else {
        raise Refused::Unsupported(kind="type \{ty.code()}")
      }
  }
}

///|
/// Read a value that names a type of the writer's own: the user type ID has not
/// been read yet.
fn read_body_of(r : Reader, ty : TypeId) -> Value raise {
  match ty {
    Struct | CompatibleStruct | NamedStruct | NamedCompatibleStruct =>
      read_struct_body(r)
    Enum | NamedEnum => {
      let user = r.read_var_u32().reinterpret_as_int()
      Enum(user, r.read_var_u32().reinterpret_as_int())
    }
    _ => read_body(r, ty)
  }
}

///|
/// Read a struct: the user type ID says which schema, and the schema says what
/// the fields are and in what order.
fn read_struct_body(r : Reader) -> Value raise {
  let user = r.read_var_u32().reinterpret_as_int()
  let meta = match r.schema(user) {
    Some(m) => m
    None => raise Refused::Unsupported(kind="struct \{user}")
  }
  Struct(meta, read_struct_fields(r, meta))
}

///|
/// Read a struct's fields in Fory order, and hand them back by name.
fn read_struct_fields(
  r : Reader,
  meta : StructMeta,
) -> Array[(String, Value)] raise {
  read_fields_into(r, meta, [])
}

///|
/// A list: a count, one header byte, the element type when there is a single
/// one, then the elements.
///
/// The element type is always written here, because a value without a schema has
/// no declared type to be. A peer that knows the schema may leave it out; this
/// reader asks for it rather than guessing.
fn write_list_body(w : Writer, items : Array[Value]) -> Unit raise {
  w.write_var_u32(items.length().reinterpret_as_uint())
  if items.length() == 0 {
    return
  }
  let mut has_null = false
  let mut same = true
  let mut first : TypeId? = None
  for item in items {
    if item is Null {
      has_null = true
    } else {
      let ty = item.ty()
      match first {
        None => first = Some(ty)
        Some(t) => if t != ty { same = false }
      }
    }
  }
  let mut header = 0
  if has_null {
    header = header | 0x02
  }
  if same && first is Some(_) {
    header = header | 0x08
  }
  w.write_byte(header)
  if same {
    match first {
      Some(t) => w.write_type_id(t)
      None => ()
    }
  }
  for item in items {
    if has_null {
      if item is Null {
        w.write_byte(0xFD)
        continue
      }
      w.write_byte(0xFF)
    }
    // The type is written by the element when the list did not say one for
    // all of them, and by the list when it did.
    if same {
      write_value_data(w, item)
    } else {
      write_value(w, item)
    }
  }
}

///|
/// The list header as it is read: the count, then the flags, then the elements
/// in whatever shape the flags describe.
fn read_list_body(r : Reader, kind : TypeId) -> Value raise {
  read_list_into(r, kind, [])
}

///|
/// The same, filling an array the caller already holds: a cycle reaches back
/// into a list that is not finished, so the array has to exist before the
/// elements are read into it.
fn read_list_into(
  r : Reader,
  kind : TypeId,
  items : Array[Value],
) -> Value raise {
  let n = r.read_var_u32().reinterpret_as_int()
  r.spend(n)
  if n == 0 {
    return List(kind, items)
  }
  r.enter()
  let at = r.offset()
  let header = r.read_byte()
  let has_null = (header & 0x02) != 0
  let same = (header & 0x08) != 0
  let declared = (header & 0x04) != 0
  if declared {
    raise Refused::Unsupported(kind="list of a declared type")
  }
  let element : TypeId? = if same { Some(r.read_type_id()) } else { None }
  for _ in 0..<n {
    if has_null {
      let flag = r.read_i8()
      if flag == -3 {
        items.push(Null)
        continue
      }
      if flag != -1 {
        raise Refused::BadEncoding(at=r.offset() - 1, got=flag)
      }
    }
    match element {
      Some(ty) => items.push(read_body(r, ty))
      None => items.push(read_value(r))
    }
  }
  if items.length() != n {
    raise Refused::Truncated(at~, want=n, got=items.length())
  }
  r.leave()
  List(kind, items)
}

///|
/// A map: a count, then chunks of at most two hundred and fifty-five pairs.
///
/// A chunk exists because the pairs in it share their shape — which side may be
/// nothing, and what the types are — and because a writer cannot know the shape
/// of every pair without reading them all first.
fn write_map_body(w : Writer, entries : Array[(Value, Value)]) -> Unit raise {
  w.write_var_u32(entries.length().reinterpret_as_uint())
  let mut chunk : Array[(Value, Value)] = []
  let mut key_ty : TypeId? = None
  let mut val_ty : TypeId? = None
  for (k, v) in entries {
    if k is Null || v is Null {
      write_map_chunk(w, chunk, key_ty, val_ty)
      chunk = []
      key_ty = None
      val_ty = None
      write_null_pair(w, k, v)
      continue
    }
    let kt = k.ty()
    let vt = v.ty()
    let fits = match (key_ty, val_ty) {
      (Some(a), Some(b)) => a == kt && b == vt
      _ => true
    }
    if !fits || chunk.length() >= 255 {
      write_map_chunk(w, chunk, key_ty, val_ty)
      chunk = []
      key_ty = None
      val_ty = None
    }
    key_ty = Some(kt)
    val_ty = Some(vt)
    chunk.push((k, v))
  }
  write_map_chunk(w, chunk, key_ty, val_ty)
}

///|
/// One chunk, if it has anything in it: the header, the count, the two types,
/// then the pairs.
fn write_map_chunk(
  w : Writer,
  chunk : Array[(Value, Value)],
  key_ty : TypeId?,
  val_ty : TypeId?,
) -> Unit raise {
  if chunk.length() == 0 {
    return
  }
  w.write_byte(0x00)
  w.write_byte(chunk.length())
  match key_ty {
    Some(t) => w.write_type_id(t)
    None => ()
  }
  match val_ty {
    Some(t) => w.write_type_id(t)
    None => ()
  }
  for (k, v) in chunk {
    write_value_data(w, k)
    write_value_data(w, v)
  }
}

///|
/// A pair with nothing on one side: its own chunk, of one pair, with no count
/// byte, which is how the reader knows to stop after it.
fn write_null_pair(w : Writer, k : Value, v : Value) -> Unit raise {
  if k is Null && v is Null {
    w.write_byte(0x12)
  } else if v is Null {
    w.write_byte(0x10)
    write_value(w, k)
  } else {
    w.write_byte(0x02)
    write_value(w, v)
  }
}

///|
/// Read a map: the count, then chunks until that many pairs have been read.
fn read_map_body(r : Reader) -> Value raise {
  read_map_into(r, [])
}

///|
/// The same, filling an array the caller already holds, for the same reason a
/// list does.
fn read_map_into(r : Reader, entries : Array[(Value, Value)]) -> Value raise {
  let total = r.read_var_u32().reinterpret_as_int()
  r.spend(total)
  r.enter()
  while entries.length() < total {
    let at = r.offset()
    let header = r.read_byte()
    let key_null = (header & 0x02) != 0
    let val_null = (header & 0x10) != 0
    if key_null && val_null {
      entries.push((Null, Null))
      continue
    }
    if key_null || val_null {
      // An entry of one pair, with no count byte after the header.
      let key = if key_null {
        Value::Null
      } else if (header & 0x04) != 0 {
        raise Refused::Unsupported(kind="map key of a declared type")
      } else {
        read_value(r)
      }
      let value = if val_null {
        Value::Null
      } else if (header & 0x20) != 0 {
        raise Refused::Unsupported(kind="map value of a declared type")
      } else {
        read_value(r)
      }
      entries.push((key, value))
      continue
    }
    let size = r.read_byte()
    if size == 0 {
      raise Refused::BadEncoding(at~, got=size)
    }
    if (header & 0x04) != 0 || (header & 0x20) != 0 {
      raise Refused::Unsupported(kind="map of a declared type")
    }
    let key_ty = r.read_type_id()
    let val_ty = r.read_type_id()
    for _ in 0..<size {
      entries.push((read_body(r, key_ty), read_body(r, val_ty)))
    }
  }
  r.leave()
  Map(entries)
}

///|
/// A struct's fields, in Fory order, each with the flag its schema asks for and
/// the type meta its type needs.
fn write_struct_body(
  w : Writer,
  meta : StructMeta,
  fields : Array[(String, Value)],
) -> Unit raise {
  for field in meta.ordered() {
    let value = lookup(fields, field.name)
    if field.nullable || field.track_ref {
      if value is Null {
        w.write_byte(0xFD)
        continue
      } else if field.track_ref {
        w.write_byte(0x00)
      } else {
        w.write_byte(0xFF)
      }
    }
    if field.ty.is_user() {
      w.write_type_id(field.ty)
    }
    write_body_as(w, field.ty, value)
  }
}

///|
/// Read the fields of one struct into `out`, in Fory order, by name.
///
/// A field whose schema says it may be shared is put aside before its contents
/// are read: a cycle reaches back into a container that is not finished, and
/// this is the only place that can hand out the container it points at.
fn read_fields_into(
  r : Reader,
  meta : StructMeta,
  out : Array[(String, Value)],
) -> Array[(String, Value)] raise {
  if meta.fields.length() > r.config.fields {
    raise Refused::TooLarge(
      at=r.offset(),
      limit=r.config.fields.to_int64(),
      got=meta.fields.length().to_int64(),
    )
  }
  r.enter()
  for field in meta.ordered() {
    let mut tracked : Int32? = None
    if field.nullable || field.track_ref {
      match r.read_ref_flag() {
        Null => {
          out.push((field.name, Null))
          continue
        }
        Ref(id~) => {
          out.push((field.name, resolve_ref(r, id)))
          continue
        }
        NotNull => ()
        RefValue(id~) => tracked = Some(id)
      }
    }
    if field.ty.is_user() {
      let (got, user) = r.read_user_type()
      if got != field.ty {
        raise Refused::WantType(
          at=r.offset(),
          want=field.ty.code(),
          got=got.code(),
        )
      }
      if got == Enum || got == NamedEnum {
        out.push(
          (field.name, Enum(user, r.read_var_u32().reinterpret_as_int())),
        )
        continue
      }
      let child = match r.schema(user) {
        Some(m) => m
        None => raise Refused::Unsupported(kind="struct \{user}")
      }
      let fields : Array[(String, Value)] = []
      match tracked {
        Some(id) => r.set_node(id, Struct(child, fields))
        None => ()
      }
      let _ = read_fields_into(r, child, fields)
      out.push((field.name, Struct(child, fields)))
      continue
    }
    let value = match tracked {
      Some(id) if field.ty == List || field.ty == Set => {
        let items : Array[Value] = []
        r.set_node(id, List(field.ty, items))
        read_list_into(r, field.ty, items)
      }
      Some(id) if field.ty == Map => {
        let entries : Array[(Value, Value)] = []
        r.set_node(id, Map(entries))
        read_map_into(r, entries)
      }
      _ => read_body(r, field.ty)
    }
    out.push((field.name, value))
  }
  r.leave()
  out
}

///|
/// What a reference points at: the container put aside for that id when there is
/// one, and otherwise the bytes read again.
fn resolve_ref(r : Reader, id : Int32) -> Value raise {
  match r.node(id) {
    Some(v) => v
    None => {
      let saved = r.enter_ref(id)
      let v = read_value(r)
      r.leave_ref(saved)
      v
    }
  }
}

///|
/// The field a name asks for, and nothing when the writer left it out.
fn lookup(fields : Array[(String, Value)], name : String) -> Value {
  for (k, v) in fields {
    if k == name {
      return v
    }
  }
  Null
}

///|
/// A dense primitive array: a byte count, then the raw little-endian elements,
/// read as the list of values they are.
///
/// The width is the format's and not this package's — MoonBit has no
/// `Array[Int16]` — so a dense array of any width reads as a list.
fn read_dense(r : Reader, ty : TypeId) -> Value raise {
  let element = match ty.element() {
    Some(t) => t
    None => raise Refused::BadType(at=r.offset(), got=ty.code())
  }
  let size = match element.fixed_size() {
    Some(n) => n
    None => raise Refused::BadType(at=r.offset(), got=ty.code())
  }
  let bytes = r.read_var_u32().reinterpret_as_int()
  r.spend(bytes)
  let body = r.read_bytes(bytes)
  let items : Array[Value] = []
  let mut at = 0
  while at + size <= bytes {
    items.push(
      read_dense_unit(body.exact_view(start=at, end=at + size), element),
    )
    at = at + size
  }
  List(ty, items)
}

///|
/// One element of a dense array, read out of its own little-endian bytes.
fn read_dense_unit(unit : BytesView, element : TypeId) -> Value {
  match element {
    Bool => Bool(unit.at(0).to_int() != 0)
    Int8 => Int(fixed_int(unit, 1).to_int64())
    Int16 => Int(fixed_int(unit, 2).to_int64())
    Int32 => Int(fixed_int(unit, 4).to_int64())
    Int64 => Int(or_i64(@fixed.read_i64(unit, order=Little)))
    UInt8 => UInt(fixed_uint(unit, 1))
    UInt16 => UInt(fixed_uint(unit, 2))
    UInt32 => UInt(fixed_uint(unit, 4))
    UInt64 => UInt(or_u64(@fixed.read_u64(unit, order=Little)))
    Float16 => Float(half(fixed_uint(unit, 2).to_int()))
    BFloat16 => Float(bfloat(fixed_uint(unit, 2).to_int()))
    Float32 => Float(or_f32(@fixed.read_f32(unit, order=Little)).to_double())
    Float64 => Float(or_f64(@fixed.read_f64(unit, order=Little)))
    _ => Null
  }
}

///|
/// A read that cannot be short: a dense array's byte count has already been
/// checked against what is left of the message.
fn or_i64(v : Int64?) -> Int64 {
  match v {
    Some(x) => x
    None => 0L
  }
}

///|
fn or_u64(v : UInt64?) -> UInt64 {
  match v {
    Some(x) => x
    None => 0UL
  }
}

///|
fn or_f32(v : Float?) -> Float {
  match v {
    Some(x) => x
    None => 0.0
  }
}

///|
fn or_f64(v : Double?) -> Double {
  match v {
    Some(x) => x
    None => 0.0
  }
}

///|
/// A little-endian signed integer of `size` bytes, sign-extended.
fn fixed_int(unit : BytesView, size : Int32) -> Int32 {
  let mut out = 0
  for i in 0..<size {
    out = out | (unit.at(i).to_int() << (i * 8))
  }
  if size < 4 && out >= 1 << (size * 8 - 1) {
    out - (1 << (size * 8))
  } else {
    out
  }
}

///|
/// A little-endian unsigned integer of `size` bytes.
fn fixed_uint(unit : BytesView, size : Int32) -> UInt64 {
  let mut out = 0UL
  for i in 0..<size {
    out = out |
      (unit.at(i).to_int().reinterpret_as_uint().to_uint64() << (i * 8))
  }
  out
}

///|
/// Two to the power of `n`, for the exponents a float can ask for.
fn pow2(n : Int32) -> Double {
  let mut out = 1.0
  let mut i = 0
  let steps = if n < 0 { -n } else { n }
  while i < steps {
    out = if n < 0 { out / 2.0 } else { out * 2.0 }
    i = i + 1
  }
  out
}

///|
/// An IEEE 754 binary16 as the double it stands for.
fn half(bits : Int32) -> Double {
  let sign = if bits >> 15 == 1 { -1.0 } else { 1.0 }
  let exponent = (bits >> 10) & 0x1F
  let mantissa = (bits & 0x3FF).to_double()
  if exponent == 0 {
    sign * (mantissa / 1024.0) * pow2(-14)
  } else if exponent == 31 {
    if mantissa == 0.0 {
      sign * 1.0 / 0.0
    } else {
      0.0 / 0.0
    }
  } else {
    sign * (1.0 + mantissa / 1024.0) * pow2(exponent - 15)
  }
}

///|
/// A bfloat16: the top sixteen bits of a binary32, which is what the format
/// means by it.
fn bfloat(bits : Int32) -> Double {
  let sign = if bits >> 15 == 1 { -1.0 } else { 1.0 }
  let exponent = (bits >> 7) & 0xFF
  let mantissa = (bits & 0x7F).to_double()
  if exponent == 0 {
    sign * (mantissa / 128.0) * pow2(-126)
  } else if exponent == 255 {
    if mantissa == 0.0 {
      sign * 1.0 / 0.0
    } else {
      0.0 / 0.0
    }
  } else {
    sign * (1.0 + mantissa / 128.0) * pow2(exponent - 127)
  }
}

///|
/// A decimal: the scale as a signed varint, then the unscaled value as a
/// varint when it is small and as a sign and magnitude when it is not.
fn write_decimal(w : Writer, scale : Int32, unscaled : BigInt) -> Unit raise {
  if scale < -10_000 || scale > 10_000 {
    raise Refused::TooLarge(at=w.length(), limit=10_000L, got=scale.to_int64())
  }
  w.write_var_i32(scale)
  let small = unscaled.compare_int64(-4_611_686_018_427_387_904L) >= 0 &&
    unscaled.compare_int64(4_611_686_018_427_387_903L) <= 0
  if small {
    w.write_var_u64(@leb128.zigzag(unscaled.to_int64()) << 1)
  } else {
    let negative = unscaled.compare_int(0) < 0
    let magnitude = if negative { unscaled.neg() } else { unscaled }
    let bytes = magnitude.to_octets()
    if bytes.length() > 10_000 {
      raise Refused::TooLarge(
        at=w.length(),
        limit=10_000L,
        got=bytes.length().to_int64(),
      )
    }
    let sign = if negative { 1 } else { 0 }
    let meta = ((bytes.length() << 1) | sign).reinterpret_as_uint().to_uint64()
    w.write_var_u64((meta << 1) | 1UL)
    w.write_bytes(bytes)
  }
}

///|
/// Read a decimal back.
fn read_decimal(r : Reader) -> Value raise {
  let scale = r.read_var_i32()
  if scale < -10_000 || scale > 10_000 {
    raise Refused::TooLarge(at=r.offset(), limit=10_000L, got=scale.to_int64())
  }
  let header = r.read_var_u64()
  if (header & 1UL) == 0UL {
    Decimal(scale, BigInt::from_int64(@leb128.unzigzag(header >> 1)))
  } else {
    let meta = (header >> 1).to_int()
    let sign = meta & 1
    let len = meta >> 1
    if len == 0 {
      raise Refused::BadEncoding(at=r.offset(), got=meta)
    }
    if len > 10_000 {
      raise Refused::TooLarge(at=r.offset(), limit=10_000L, got=len.to_int64())
    }
    let bytes = r.read_bytes(len)
    let magnitude = BigInt::from_octets(bytes[:])
    Decimal(scale, if sign == 1 { magnitude.neg() } else { magnitude })
  }
}
