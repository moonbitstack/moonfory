// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where a value goes: a buffer, the configuration it is written under, and
/// the table of what has already been sent.
///
/// Everything the specification fixes is a method here, so that a type this
/// package has never heard of can be written with the same primitives its own
/// types are written with. Nothing here is private to a codec.
pub(all) struct Writer {
  /// The bytes so far.
  buf : Buffer
  /// What this message is written under.
  config : Config
  /// The caller's key for a shared value, and the reference id it was given.
  ///
  /// MoonBit has no identity to infer sharing from, so the key is the caller's:
  /// two writes of the same key send the value once and point at it after.
  refs : Map[Int32, Int32]
  /// The next reference id.
  mut next_ref : Int32
  /// The key handed to the next value that takes a reference id without being
  /// given one: a tracked value the caller did not name still has to occupy its
  /// place in the id order, and the key it is filed under descends from `-2`,
  /// below `root_key`.
  mut fresh : Int32
}

///|
/// A writer with nothing in it.
pub fn Writer::new(
  config~ : Config = Config::new(),
  buffer~ : Buffer = Buffer(),
) -> Writer {
  { buf: buffer, config, refs: Map([]), next_ref: 0, fresh: -2, }
}

///|
/// The buffer being written into, so that a caller who already has one does not
/// have to copy out of it.
pub fn Writer::buffer(self : Writer) -> Buffer {
  self.buf
}

///|
/// The bytes written so far.
pub fn Writer::bytes(self : Writer) -> Bytes {
  self.buf.to_bytes()
}

///|
/// How many bytes have been written.
pub fn Writer::length(self : Writer) -> Int32 {
  self.buf.length()
}

///|
/// One byte.
pub fn Writer::write_byte(self : Writer, v : Int32) -> Unit {
  self.buf.write_byte(v.to_byte())
}

///|
/// The header byte: the cross-language flag in bit 0.
///
/// The specification leaves bit 1 for out-of-band data and asks that it be 0
/// when there is none, which is always here: this package writes no
/// out-of-band buffer.
pub fn Writer::write_head(self : Writer) -> Unit {
  self.write_byte(if self.config.xlang { 0x01 } else { 0x00 })
}

///|
/// A boolean: one byte, `1` or `0`.
pub fn Writer::write_bool(self : Writer, v : Bool) -> Unit {
  self.write_byte(if v { 1 } else { 0 })
}

///|
/// Eight bits, signed or unsigned: the byte is the same either way.
pub fn Writer::write_i8(self : Writer, v : Int32) -> Unit {
  self.write_byte(v)
}

///|
/// Eight bits, unsigned.
pub fn Writer::write_u8(self : Writer, v : Int32) -> Unit {
  self.write_byte(v)
}

///|
/// Sixteen bits, signed, little endian.
pub fn Writer::write_i16(self : Writer, v : Int32) -> Unit {
  @fixed.write_i16(self.buf, v, order=Little)
}

///|
/// Sixteen bits, unsigned, little endian.
pub fn Writer::write_u16(self : Writer, v : Int32) -> Unit {
  @fixed.write_u16(self.buf, v, order=Little)
}

///|
/// Thirty-two bits, signed, little endian.
pub fn Writer::write_i32(self : Writer, v : Int32) -> Unit {
  @fixed.write_i32(self.buf, v, order=Little)
}

///|
/// Thirty-two bits, unsigned, little endian.
pub fn Writer::write_u32(self : Writer, v : UInt32) -> Unit {
  @fixed.write_u32(self.buf, v, order=Little)
}

///|
/// Sixty-four bits, signed, little endian.
pub fn Writer::write_i64(self : Writer, v : Int64) -> Unit {
  @fixed.write_i64(self.buf, v, order=Little)
}

///|
/// Sixty-four bits, unsigned, little endian.
pub fn Writer::write_u64(self : Writer, v : UInt64) -> Unit {
  @fixed.write_u64(self.buf, v, order=Little)
}

///|
/// A single-precision float: IEEE 754 binary32, little endian, NaN preserved.
pub fn Writer::write_f32(self : Writer, v : Float) -> Unit {
  @fixed.write_f32(self.buf, v, order=Little)
}

///|
/// A double-precision float: IEEE 754 binary64, little endian, NaN preserved.
pub fn Writer::write_f64(self : Writer, v : Double) -> Unit {
  @fixed.write_f64(self.buf, v, order=Little)
}

///|
/// A base-128 varint, least significant group first, the high bit marking that
/// more follow.
pub fn Writer::write_var_u64(self : Writer, v : UInt64) -> Unit {
  @leb128.write(self.buf, v)
}

///|
/// A base-128 varint of thirty-two bits.
pub fn Writer::write_var_u32(self : Writer, v : UInt32) -> Unit {
  @leb128.write(self.buf, v.to_uint64())
}

///|
/// A signed integer folded onto an unsigned one by zigzag, then written as a
/// varint: a small negative stays one byte.
pub fn Writer::write_var_i64(self : Writer, v : Int64) -> Unit {
  @leb128.write(self.buf, @leb128.zigzag(v))
}

///|
/// The same for thirty-two bits.
pub fn Writer::write_var_i32(self : Writer, v : Int32) -> Unit {
  @leb128.write(self.buf, @leb128.zigzag(v.to_int64()))
}

///|
/// A sixty-four-bit signed integer that is usually small: four bytes carrying
/// `v << 1`, or `1` and then eight bytes when it does not fit.
///
/// The low bit of the first four bytes is the tag, which is why the range that
/// fits is `[-2^30, 2^30-1]` and not the whole of the thirty-two bits.
pub fn Writer::write_tagged_i64(self : Writer, v : Int64) -> Unit {
  if v >= -1_073_741_824L && v <= 1_073_741_823L {
    self.write_i32(v.to_int() << 1)
  } else {
    self.write_byte(0x01)
    self.write_i64(v)
  }
}

///|
/// A sixty-four-bit unsigned integer that is usually small: four bytes
/// carrying `v << 1`, or `1` and then eight bytes when it does not fit.
pub fn Writer::write_tagged_u64(self : Writer, v : UInt64) -> Unit {
  if v <= 2_147_483_647UL {
    self.write_u32(v.to_uint() << 1)
  } else {
    self.write_byte(0x01)
    self.write_u64(v)
  }
}

///|
/// The string header: `size << 2 | encoding`, written as one byte while it
/// fits in seven bits and as a varint when it does not.
///
/// Sizes under thirty-two bytes are most strings, so the single byte is the
/// case worth having.
pub fn Writer::write_var_u36(self : Writer, v : UInt64) -> Unit {
  if v < 0x80UL {
    self.write_byte(v.to_int())
  } else {
    self.write_var_u64(v)
  }
}

///|
/// A string: the header, then the bytes.
///
/// The encoding chosen is UTF-8, which the specification allows every language
/// to read; LATIN1 and UTF-16 are read but not written, because a MoonBit
/// string is Unicode and narrowing it would lose what is not in the other one.
pub fn Writer::write_string(self : Writer, v : String) -> Unit {
  let bytes = @utf8.encode(v)
  self.write_var_u36((bytes.length().to_uint64() << 2) | 2UL)
  self.buf.write_bytes(bytes)
}

///|
/// Bytes with their length in front: the BINARY type's body.
pub fn Writer::write_binary(self : Writer, v : Bytes) -> Unit {
  self.write_var_u32(v.length().reinterpret_as_uint())
  self.buf.write_bytes(v)
}

///|
/// Bytes as they are, with no length: for the caller who has already written
/// one.
pub fn Writer::write_bytes(self : Writer, v : Bytes) -> Unit {
  self.buf.write_bytes(v)
}

///|
/// A type ID byte.
pub fn Writer::write_type_id(self : Writer, t : TypeId) -> Unit {
  self.write_byte(t.code())
}

///|
/// A type ID byte and the user type ID that follows it: how a struct, an enum
/// or an extension names its own type in same-schema mode.
pub fn Writer::write_user_type(self : Writer, t : TypeId, user : Int32) -> Unit {
  self.write_byte(t.code())
  self.write_var_u32(user.reinterpret_as_uint())
}

///|
/// The null flag: `0xFD` for a value that is not there, `0xFF` for one that is.
pub fn Writer::write_null_flag(self : Writer, is_null : Bool) -> Unit {
  self.write_byte(if is_null { 0xFD } else { 0xFF })
}

///|
/// The key the root value is tracked under, when tracking is on.
///
/// The root is reference zero, so that the ids here line up with a peer's: a
/// `shared` value is given a key of its own, and this one is kept out of the
/// way of them.
pub let root_key : Int32 = -1

///|
/// The flag for a reference to a value that has already been written, and
/// whether it was: a key that names nothing yet writes nothing and answers
/// `false`, because a reference to a value that is not on the wire cannot be
/// written as one.
pub fn Writer::write_ref(self : Writer, key : Int32) -> Bool {
  match self.refs.get(key) {
    Some(id) => {
      self.write_byte(0xFE)
      self.write_var_u32(id.reinterpret_as_uint())
      true
    }
    None => false
  }
}

///|
/// The flag for a value that is tracked but was never named: it takes the next
/// reference id, under a key of this writer's own below every caller's, so that
/// the ids of the references that do name something still line up with a peer's.
pub fn Writer::write_fresh(self : Writer) -> Unit {
  let id = self.next_ref
  self.refs.set(self.fresh, id)
  self.fresh = self.fresh - 1
  self.next_ref = id + 1
  self.write_byte(0x00)
}

///|
/// The envelope of a value that may be written more than once, and whether the
/// body still has to be written.
///
/// `key` is the caller's name for the value. The first time it is met, `0x00`
/// goes out and the answer is `true`; after that, `0xFE` and the reference id
/// go out and the answer is `false`, because the value is already on the wire.
pub fn Writer::write_tracked(self : Writer, key : Int32) -> Bool {
  match self.refs.get(key) {
    Some(id) => {
      self.write_byte(0xFE)
      self.write_var_u32(id.reinterpret_as_uint())
      false
    }
    None => {
      let id = self.next_ref
      self.refs.set(key, id)
      self.next_ref = id + 1
      self.write_byte(0x00)
      true
    }
  }
}
