// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

/// The row format: a cache-friendly, random-access layout for a row of values that
/// share one schema. It is the "standard" variant from the Fory row specification
/// (the "compact" variant is Java-only, so it is out of reach for a cross-language
/// implementation). The layout, for each row, is a null bitmap, then one fixed
/// eight-byte slot per field, then the variable-width data (strings, arrays, maps,
/// nested rows) written after, each piece padded to an eight-byte boundary.
///
/// A field that is a string, an array, a map or a nested struct does not keep its
/// bytes in the slot. It keeps a relative offset and a size; the bytes live in the
/// variable region, and the offset is counted from the start of the row that owns
/// them. That single rule holds for every level of nesting, which is why a row and a
/// nested struct are built by the same routine.

///|
/// The type of one field in a row schema.
///
/// It is the cross-language primitive set, plus the three shapes that live in the
/// variable region: a homogeneous array, a key-and-value map, and a nested struct.
pub(all) enum RowType {
  Bool
  Int8
  Int16
  Int32
  Int64
  Float32
  Float64
  String
  Binary
  /// Microseconds since the Unix epoch.
  Timestamp
  /// Days since the Unix epoch.
  Date
  /// A span of time, in microseconds.
  Duration
  Array(RowType)
  Map(RowType, RowType)
  Struct(Array[RowField])
} derive(Eq, Debug)

///|
pub extend RowType with Eq::{not_equal, equal}

///|
pub extend RowType with Debug::{to_repr}

///|
/// One field of a row schema: its name, its type, and whether it may be null.
pub(all) struct RowField {
  /// The field name, kept for readability and for round-tripping a schema.
  name : String
  /// The field type, fixed-width or variable.
  ty : RowType
  /// Whether a null in this field is permitted.
  nullable : Bool
} derive(Eq, Debug)

///|
pub extend RowField with Eq::{not_equal, equal}

///|
pub extend RowField with Debug::{to_repr}

///|
/// A row schema: the ordered list of fields a row is built and read against.
pub(all) struct RowSchema {
  fields : Array[RowField]
}

///|
/// Build a schema from an ordered list of fields.
pub fn RowSchema::new(fields : Array[RowField]) -> RowSchema {
  { fields, }
}

///|
/// A value written into, or read out of, a row.
///
/// It mirrors `RowType` rather than the cross-language `Value`, because the row
/// format is schema-driven: the type of every field is fixed by the schema, not
/// carried in the bytes. `Null` stands for a null field or a null array element.
pub(all) enum RowValue {
  Null
  Bool(Bool)
  Int8(Int32)
  Int16(Int32)
  Int32(Int32)
  Int64(Int64)
  Float32(Double)
  Float64(Double)
  String(String)
  Binary(Bytes)
  Timestamp(Int64)
  Date(Int32)
  Duration(Int64)
  Array(Array[RowValue])
  Map(Array[(RowValue, RowValue)])
  Struct(Array[RowValue])
} derive(Eq, Debug)

///|
pub extend RowValue with Eq::{not_equal, equal}

///|
pub extend RowValue with Debug::{to_repr}

///|
/// Whether the type keeps its bytes in the eight-byte slot (`true`) or in the
/// variable region behind an offset and a size (`false`).
fn is_fixed(ty : RowType) -> Bool {
  match ty {
    Bool
    | Int8
    | Int16
    | Int32
    | Int64
    | Float32
    | Float64
    | Timestamp
    | Date
    | Duration => true
    _ => false
  }
}

///|
/// The width, in bytes, that the type takes in the slot or in an array's element
/// region. Fixed types use their natural width; the rest take the full eight bytes
/// of the offset-and-size pair.
fn row_width(ty : RowType) -> Int32 {
  match ty {
    Bool | Int8 => 1
    Int16 => 2
    Int32 | Float32 | Date => 4
    Int64 | Float64 | Timestamp | Duration => 8
    _ => 8
  }
}

///|
/// Round `n` up to the next multiple of eight.
fn align8(n : Int32) -> Int32 {
  (n + 7) / 8 * 8
}

///|
/// Pad `buf` up to the next multiple of eight bytes with zeros.
fn pad8(buf : Buffer) -> Unit {
  let rem = buf.length() % 8
  if rem != 0 {
    for _ in 0..<(8 - rem) {
      buf.write_byte(0)
    }
  }
}

///|
/// The null bitmap for `count` slots, with bit `j` set when `nulls[j]` is true. Bit
/// zero of the first byte is slot zero, as the specification says.
fn null_bitmap(count : Int32, nulls : Array[Bool]) -> Bytes {
  let nbit = (count + 63) / 64 * 8
  let bm : Array[Int32] = Array::make(nbit, 0)
  for j in 0..<count {
    if nulls[j] {
      let byte = j / 8
      let bit = j % 8
      bm[byte] = bm[byte] | (1 << bit)
    }
  }
  let out = Buffer()
  for b in bm {
    out.write_byte(b.to_byte())
  }
  out.to_bytes()
}

///|
/// True when slot `j` of the bitmap that begins at `base` is set.
fn bitmap_bit(view : BytesView, base : Int32, j : Int32) -> Bool {
  let byte = view.at(base + j / 8).to_int()
  (byte & (1 << (j % 8))) != 0
}

///|
/// The fixed-width value at its natural width: one byte for bool and int8, two for
/// int16, four for int32, date and float32, eight for the rest.
fn fixed_bytes(ty : RowType, v : RowValue) -> Array[Byte] {
  let buf = Buffer()
  match ty {
    Bool =>
      buf.write_byte(
        match v {
          Bool(x) => if x { 1 } else { 0 }
          _ => 0
        },
      )
    Int8 =>
      match v {
        Int8(x) => @fixed.write_i8(buf, x)
        _ => ()
      }
    Int16 =>
      match v {
        Int16(x) => @fixed.write_i16(buf, x, order=Little)
        _ => ()
      }
    Int32 =>
      match v {
        Int32(x) => @fixed.write_i32(buf, x, order=Little)
        _ => ()
      }
    Int64 =>
      match v {
        Int64(x) => @fixed.write_i64(buf, x, order=Little)
        _ => ()
      }
    Float32 =>
      match v {
        Float32(x) => @fixed.write_f32(buf, Float::from_double(x), order=Little)
        _ => ()
      }
    Float64 =>
      match v {
        Float64(x) => @fixed.write_f64(buf, x, order=Little)
        _ => ()
      }
    Timestamp =>
      match v {
        Timestamp(x) => @fixed.write_i64(buf, x, order=Little)
        _ => ()
      }
    Date =>
      match v {
        Date(x) => @fixed.write_i32(buf, x, order=Little)
        _ => ()
      }
    Duration =>
      match v {
        Duration(x) => @fixed.write_i64(buf, x, order=Little)
        _ => ()
      }
    _ => ()
  }
  buf.to_bytes().to_array()
}

///|
/// Build the eight-byte slot for a fixed-width value by padding its natural width.
fn slot_of_fixed(ty : RowType, v : RowValue) -> Array[Byte] {
  let bytes = fixed_bytes(ty, v)
  let zero : Int32 = 0
  while bytes.length() < 8 {
    bytes.push(zero.to_byte())
  }
  bytes
}

///|
/// Read a fixed-width value out of the eight bytes at `at`.
fn read_fixed(ty : RowType, view : BytesView, at : Int32) -> RowValue {
  match ty {
    Bool => RowValue::Bool(view.at(at).to_int() != 0)
    Int8 => {
      let x = match @fixed.read_i8(view, at~) {
        Some(v) => v
        None => 0
      }
      RowValue::Int8(x)
    }
    Int16 => {
      let x = match @fixed.read_i16(view, at~, order=Little) {
        Some(v) => v
        None => 0
      }
      RowValue::Int16(x)
    }
    Int32 => {
      let x = match @fixed.read_i32(view, at~, order=Little) {
        Some(v) => v
        None => 0
      }
      RowValue::Int32(x)
    }
    Int64 => {
      let x = match @fixed.read_i64(view, at~, order=Little) {
        Some(v) => v
        None => 0L
      }
      RowValue::Int64(x)
    }
    Float32 => {
      let x = match @fixed.read_f32(view, at~, order=Little) {
        Some(v) => v
        None => 0.0
      }
      RowValue::Float32(Float::to_double(x))
    }
    Float64 => {
      let x = match @fixed.read_f64(view, at~, order=Little) {
        Some(v) => v
        None => 0.0
      }
      RowValue::Float64(x)
    }
    Timestamp => {
      let x = match @fixed.read_i64(view, at~, order=Little) {
        Some(v) => v
        None => 0L
      }
      RowValue::Timestamp(x)
    }
    Date => {
      let x = match @fixed.read_i32(view, at~, order=Little) {
        Some(v) => v
        None => 0
      }
      RowValue::Date(x)
    }
    Duration => {
      let x = match @fixed.read_i64(view, at~, order=Little) {
        Some(v) => v
        None => 0L
      }
      RowValue::Duration(x)
    }
    _ => RowValue::Null
  }
}

///|
/// Whether the values line up, in order and type, with the nested struct's fields.
fn fits_struct(fs : Array[RowField], vals : Array[RowValue]) -> Bool {
  if vals.length() != fs.length() {
    return false
  }
  for i in 0..<fs.length() {
    match vals[i] {
      Null => ()
      _ => if !fits(fs[i].ty, vals[i]) { return false }
    }
  }
  true
}

///|
/// Whether `v` may sit in a field of type `ty`. A `Null` is accepted anywhere; the
/// caller decides whether the field is allowed to be null.
fn fits(ty : RowType, v : RowValue) -> Bool {
  match ty {
    Bool =>
      match v {
        Bool(_) => true
        _ => false
      }
    Int8 =>
      match v {
        Int8(_) => true
        _ => false
      }
    Int16 =>
      match v {
        Int16(_) => true
        _ => false
      }
    Int32 =>
      match v {
        Int32(_) => true
        _ => false
      }
    Int64 =>
      match v {
        Int64(_) => true
        _ => false
      }
    Float32 =>
      match v {
        Float32(_) => true
        _ => false
      }
    Float64 =>
      match v {
        Float64(_) => true
        _ => false
      }
    String =>
      match v {
        String(_) => true
        _ => false
      }
    Binary =>
      match v {
        Binary(_) => true
        _ => false
      }
    Timestamp =>
      match v {
        Timestamp(_) => true
        _ => false
      }
    Date =>
      match v {
        Date(_) => true
        _ => false
      }
    Duration =>
      match v {
        Duration(_) => true
        _ => false
      }
    Array(et) =>
      match v {
        Array(arr) =>
          arr.all(fn(x) {
            match x {
              Null => true
              _ => fits(et, x)
            }
          })
        _ => false
      }
    Map(k, vv) =>
      match v {
        Map(pairs) =>
          pairs.all(fn(p) {
            let a = match p.0 {
              Null => true
              x => fits(k, x)
            }
            let b = match p.1 {
              Null => true
              x => fits(vv, x)
            }
            a && b
          })
        _ => false
      }
    Struct(fs) =>
      match v {
        Struct(vals) => fits_struct(fs, vals)
        _ => false
      }
  }
}

///|
/// Serialise one variable-width value into a block of bytes. The block is padded to
/// an eight-byte boundary so the next value sits clean; `base` is where the block will
/// be placed, so any offset inside it is already absolute. The second returned value is
/// the logical size: the payload without the trailing padding, which is what a slot or
/// an element pair stores.
fn pack(ty : RowType, v : RowValue, base : Int32) -> (Bytes, Int32) raise {
  match ty {
    String => {
      let raw = @utf8.encode(
        match v {
          String(s) => s
          _ => ""
        },
      )
      let buf = Buffer()
      buf.write_bytes(raw)
      pad8(buf)
      (buf.to_bytes(), raw.length())
    }
    Binary => {
      let raw = match v {
        Binary(b) => b
        _ => Buffer().to_bytes()
      }
      let buf = Buffer()
      buf.write_bytes(raw)
      pad8(buf)
      (buf.to_bytes(), raw.length())
    }
    Array(et) => {
      let arr = match v {
        Array(a) => a
        _ => []
      }
      let count = arr.length()
      let nulls = arr.map(fn(x) {
        match x {
          Null => true
          _ => false
        }
      })
      let head = Buffer()
      head.write_uint64_le(count.to_uint64())
      head.write_bytes(null_bitmap(count, nulls))
      let elems = Buffer()
      let mut running = 0
      let bodies = Buffer()
      let width = row_width(et)
      let elem_region = count * width
      for j in 0..<count {
        match arr[j] {
          Null =>
            for _ in 0..<width {
              elems.write_byte(0)
            }
          _ =>
            if is_fixed(et) {
              for byte in fixed_bytes(et, arr[j]) {
                elems.write_byte(byte)
              }
            } else {
              let body_base = base +
                head.length() +
                align8(elem_region) +
                running
              let (body, logical) = pack(et, arr[j], body_base)
              let pair = (body_base.to_uint64() << 32) | logical.to_uint64()
              elems.write_uint64_le(pair)
              running = running + body.length()
              bodies.write_bytes(body)
            }
        }
      }
      let block = Buffer()
      block.write_bytes(head.to_bytes())
      block.write_bytes(elems.to_bytes())
      pad8(block)
      block.write_bytes(bodies.to_bytes())
      pad8(block)
      (block.to_bytes(), block.length())
    }
    Map(k, vv) => {
      let pairs = match v {
        Map(p) => p
        _ => []
      }
      let keys = pairs.map(fn(p) { p.0 })
      let vals = pairs.map(fn(p) { p.1 })
      let (keys_block, keys_size) = pack(
        Array(k),
        RowValue::Array(keys),
        base + 8,
      )
      let (vals_block, _) = pack(
        Array(vv),
        RowValue::Array(vals),
        base + 8 + keys_block.length(),
      )
      let block = Buffer()
      block.write_uint64_le(keys_size.to_uint64())
      block.write_bytes(keys_block)
      block.write_bytes(vals_block)
      pad8(block)
      (block.to_bytes(), block.length())
    }
    Struct(fs) => {
      let block = pack_row(
        fs,
        match v {
          Struct(vals) => vals.map(fn(x) { Some(x) })
          _ => []
        },
        base,
      )
      (block, block.length())
    }
    _ => (Buffer().to_bytes(), 0)
  }
}

///|
/// Serialise a row (or a nested struct) into bytes. `base` is where the row starts, so
/// the offsets written into its slots point at the right place wherever it sits.
fn pack_row(
  fields : Array[RowField],
  values : Array[RowValue?],
  base : Int32,
) -> Bytes raise {
  let n = fields.length()
  let nbmp = (n + 63) / 64 * 8
  let fixed = nbmp + n * 8
  let bitmap : Array[Int32] = Array::make(nbmp, 0)
  let zero : Int32 = 0
  let zero8 : Array[Byte] = Array::make(8, zero.to_byte())
  let slots : Array[Array[Byte]] = Array::make(n, [])
  let var_buf = Buffer()
  for j in 0..<n {
    match values[j] {
      None => {
        bitmap[j / 8] = bitmap[j / 8] | (1 << (j % 8))
        slots[j] = zero8
      }
      Some(v) =>
        if v is RowValue::Null {
          bitmap[j / 8] = bitmap[j / 8] | (1 << (j % 8))
          slots[j] = zero8
        } else {
          let ty = fields[j].ty
          if is_fixed(ty) {
            slots[j] = slot_of_fixed(ty, v)
          } else {
            let vbase = fixed + var_buf.length()
            let (block, logical) = pack(ty, v, base + vbase)
            var_buf.write_bytes(block)
            let pair = ((base + vbase).to_uint64() << 32) | logical.to_uint64()
            slots[j] = u64_to_8(pair)
          }
        }
    }
  }
  let out = Buffer()
  for b in bitmap {
    out.write_byte(b.to_byte())
  }
  for s in slots {
    for byte in s {
      out.write_byte(byte)
    }
  }
  out.write_bytes(var_buf.to_bytes())
  out.to_bytes()
}

///|
/// Spread a sixty-four-bit value into its eight little-endian bytes.
fn u64_to_8(v : UInt64) -> Array[Byte] {
  [
    (v & 0xffUL).to_byte(),
    ((v >> 8) & 0xffUL).to_byte(),
    ((v >> 16) & 0xffUL).to_byte(),
    ((v >> 24) & 0xffUL).to_byte(),
    ((v >> 32) & 0xffUL).to_byte(),
    ((v >> 40) & 0xffUL).to_byte(),
    ((v >> 48) & 0xffUL).to_byte(),
    ((v >> 56) & 0xffUL).to_byte(),
  ]
}

///|
/// Read a little-endian sixty-four-bit value out of `view` at `at`.
fn read_u64(view : BytesView, at : Int32) -> UInt64 {
  let a = view.at(at).to_uint64()
  let b = view.at(at + 1).to_uint64() << 8
  let c = view.at(at + 2).to_uint64() << 16
  let d = view.at(at + 3).to_uint64() << 24
  let e = view.at(at + 4).to_uint64() << 32
  let f = view.at(at + 5).to_uint64() << 40
  let g = view.at(at + 6).to_uint64() << 48
  let h = view.at(at + 7).to_uint64() << 56
  a | b | c | d | e | f | g | h
}

///|
/// The offset and size packed into a slot's eight bytes: the offset in the high
/// thirty-two bits, the size in the low thirty-two, counted from the owning row.
fn unpack_slot(view : BytesView, at : Int32) -> (Int32, Int32) {
  let pair = read_u64(view, at)
  let off = ((pair >> 32) & 0xffffffffUL).to_int()
  let sz = (pair & 0xffffffffUL).to_int()
  (off, sz)
}

///|
/// Read a variable-width value whose block begins at `base` and runs `size` bytes.
fn read_variable(
  ty : RowType,
  view : BytesView,
  base : Int32,
  size : Int32,
) -> RowValue raise {
  match ty {
    String =>
      RowValue::String(
        @utf8.decode(view.exact_view(start=base, end=base + size)),
      )
    Binary =>
      RowValue::Binary(view.exact_view(start=base, end=base + size).to_owned())
    Array(et) => {
      let count = read_u64(view, base).to_int()
      let nbit = (count + 63) / 64 * 8
      let region = base + 8 + nbit
      let mut running = 0
      let items : Array[RowValue] = []
      for j in 0..<count {
        if bitmap_bit(view, base + 8, j) {
          items.push(RowValue::Null)
          running = running + row_width(et)
        } else if is_fixed(et) {
          items.push(read_fixed(et, view, region + running))
          running = running + row_width(et)
        } else {
          let (boff, bsz) = unpack_slot(view, region + running)
          running = running + 8
          items.push(read_variable(et, view, boff, bsz))
        }
      }
      RowValue::Array(items)
    }
    Map(k, vv) => {
      let ks = read_u64(view, base).to_int()
      let kvals = match read_variable(Array(k), view, base + 8, ks) {
        Array(a) => a
        _ => []
      }
      let vvals = match
        read_variable(Array(vv), view, base + 8 + ks, size - 8 - ks) {
        Array(a) => a
        _ => []
      }
      let pairs : Array[(RowValue, RowValue)] = []
      for j in 0..<kvals.length() {
        pairs.push((kvals[j], vvals[j]))
      }
      RowValue::Map(pairs)
    }
    Struct(fs) => {
      let cur = RowCursor::new(view, RowSchema::new(fs), base~)
      let vals : Array[RowValue] = []
      for j in 0..<fs.length() {
        vals.push(cur.get_field(j))
      }
      RowValue::Struct(vals)
    }
    _ => RowValue::Null
  }
}

///|
/// A builder for one row. Create it from a schema, set each field in any order, then
/// call `finish` to get the row's bytes.
pub(all) struct Row {
  schema : RowSchema
  values : Array[RowValue?]
}

///|
/// Start a row against `schema`. Every field begins null until `set`.
pub fn Row::new(schema : RowSchema) -> Row {
  { schema, values: Array::make(schema.fields.length(), None), }
}

///|
/// Place `v` in field `i`. The value must fit the field's type, or the call refuses.
pub fn Row::set(self : Row, i : Int32, v : RowValue) -> Unit raise {
  let field = self.schema.fields[i]
  if v is RowValue::Null || fits(field.ty, v) {
    self.values[i] = Some(v)
  } else {
    raise Refused::BadType(at=i, got=0)
  }
}

///|
/// Serialise the row. A field left unset is written as null.
pub fn Row::finish(self : Row) -> Bytes raise {
  pack_row(self.schema.fields, self.values, 0)
}

///|
/// A reader over one row's bytes, with random access to any field.
///
/// Build it from the same schema the row was written with, and from the bytes
/// `finish` produced. `base` is normally zero; it is non-zero only when this cursor
/// reads a nested struct inside a larger row.
pub struct RowCursor {
  view : BytesView
  schema : RowSchema
  bitmap_size : Int32
  fixed : Int32
  base : Int32
}

///|
/// Open a cursor over a row's bytes. `base` defaults to zero for a top-level row.
pub fn RowCursor::new(
  view : BytesView,
  schema : RowSchema,
  base~ : Int32 = 0,
) -> RowCursor {
  let n = schema.fields.length()
  let bitmap_size = (n + 63) / 64 * 8
  { view, schema, bitmap_size, fixed: bitmap_size + n * 8, base, }
}

///|
/// The number of fields in the row.
pub fn RowCursor::length(self : RowCursor) -> Int32 {
  self.schema.fields.length()
}

///|
/// Whether field `i` is null.
pub fn RowCursor::is_null(self : RowCursor, i : Int32) -> Bool {
  bitmap_bit(self.view, self.base, i)
}

///|
/// Read field `i`. A null field returns `RowValue::Null`; a variable field is read
/// from the offset and size in its slot.
pub fn RowCursor::get_field(self : RowCursor, i : Int32) -> RowValue raise {
  if self.is_null(i) {
    return RowValue::Null
  }
  let ty = self.schema.fields[i].ty
  let slot = self.base + self.bitmap_size + i * 8
  if is_fixed(ty) {
    read_fixed(ty, self.view, slot)
  } else {
    let (off, sz) = unpack_slot(self.view, slot)
    read_variable(ty, self.view, off, sz)
  }
}
