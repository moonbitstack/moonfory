// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What the byte before a value can say about it.
///
/// The four flags are the specification's, and they are how a nullable field, a
/// shared value and a value that is simply there are told apart: one byte,
/// before the value, that says which.
pub(all) enum RefFlag {
  /// `0xFD`: there is no value. What a nullable field holds when it holds
  /// nothing.
  Null
  /// `0xFE`: the value is one that has already gone past, and the id says
  /// which one. A reference, and the reason this is not a tagged encoder.
  Ref(id~ : Int32)
  /// `0xFF`: there is a value here, and it is not tracked.
  NotNull
  /// `0x00`: there is a value here, and it may be pointed at; the id is the one
  /// it is given.
  RefValue(id~ : Int32)
} derive(Eq, Debug)

///|
pub extend RefFlag with Eq::{not_equal, equal}

///|
pub extend RefFlag with Debug::{to_repr}

///|
/// Where a value comes from: the bytes, the place in them, and what has been
/// read already.
///
/// The mirror of `Writer`. A reader keeps two things about references: where
/// each one started, so a value can be read again, and the container being
/// built for each one, so a cycle can point at a value that is not finished.
pub(all) struct Reader {
  /// The bytes being read.
  view : BytesView
  /// What this message is read under.
  config : Config
  /// Where the next byte is.
  mut at : Int32
  /// Where the value of each reference id starts.
  refs : Array[Int32]
  /// The container being built for each reference id, before it is filled.
  nodes : Map[Int32, Value]
  /// The structs this reader knows, by the user type ID they are registered
  /// under: same-schema mode is an agreement, and this is where it is kept.
  schemas : Map[Int32, StructMeta]
  /// How deep in a replay this read is: a value being read a second time for a
  /// reference does not get a reference id of its own.
  mut replay : Int32
  /// The offsets of the replays above this one, so a cycle is caught rather
  /// than read for ever.
  replaying : Array[Int32]
  /// How deep in the nesting this read is.
  mut depth : Int32
  /// How many bytes of variable-length payload have been declared so far.
  mut spent : Int32
}

///|
/// A reader at the start of `bytes`, knowing the structs named in `schemas`.
///
/// A struct arrives as a user type ID and nothing else, so the schema it stands
/// for has to be given to the reader before it is met.
pub fn Reader::new(
  bytes : Bytes,
  config~ : Config = Config::new(),
  schemas~ : Array[StructMeta] = [],
) -> Reader {
  let by_user : Map[Int32, StructMeta] = Map([])
  for meta in schemas {
    by_user.set(meta.user, meta)
  }
  {
    view: bytes[:],
    config,
    at: 0,
    refs: [],
    nodes: Map([]),
    schemas: by_user,
    replay: 0,
    replaying: [],
    depth: 0,
    spent: 0,
  }
}

///|
/// The struct registered under a user type ID, when this reader knows it.
pub fn Reader::schema(self : Reader, user : Int32) -> StructMeta? {
  self.schemas.get(user)
}

///|
/// Where the next byte is.
pub fn Reader::offset(self : Reader) -> Int32 {
  self.at
}

///|
/// How many bytes are still unread.
pub fn Reader::remaining(self : Reader) -> Int32 {
  self.view.length() - self.at
}

///|
/// Whether every byte has been read.
pub fn Reader::is_done(self : Reader) -> Bool {
  self.at >= self.view.length()
}

///|
/// One byte.
pub fn Reader::read_byte(self : Reader) -> Int32 raise {
  if self.at >= self.view.length() {
    raise Refused::Truncated(at=self.at, want=1, got=0)
  }
  let v = self.view.at(self.at).to_int()
  self.at = self.at + 1
  v
}

///|
/// Eight bits, read as signed, which is how the reference flags are written.
pub fn Reader::read_i8(self : Reader) -> Int32 raise {
  let v = self.read_byte()
  if v >= 0x80 {
    v - 0x100
  } else {
    v
  }
}

///|
/// The header byte, checked against what this reader was asked for.
///
/// A message that does not carry the cross-language flag is a message written
/// by the native format, which is a different format.
pub fn Reader::read_head(self : Reader) -> Unit raise {
  let at = self.at
  let v = self.read_byte()
  if self.config.xlang && (v & 0x01) == 0 {
    raise Refused::BadHeader(at~, got=v)
  }
}

///|
/// A boolean: one byte, and everything but `1` is false.
pub fn Reader::read_bool(self : Reader) -> Bool raise {
  let at = self.at
  let v = self.read_byte()
  match v {
    0 => false
    1 => true
    _ => raise Refused::BadEncoding(at~, got=v)
  }
}

///|
/// Eight bits, unsigned.
pub fn Reader::read_u8(self : Reader) -> Int32 raise {
  self.read_byte()
}

///|
/// Sixteen bits, signed, little endian.
pub fn Reader::read_i16(self : Reader) -> Int32 raise {
  match @fixed.read_i16(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=2, got=self.remaining())
    Some(v) => {
      self.at = self.at + 2
      v
    }
  }
}

///|
/// Sixteen bits, unsigned, little endian.
pub fn Reader::read_u16(self : Reader) -> Int32 raise {
  match @fixed.read_u16(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=2, got=self.remaining())
    Some(v) => {
      self.at = self.at + 2
      v
    }
  }
}

///|
/// Thirty-two bits, signed, little endian.
pub fn Reader::read_i32(self : Reader) -> Int32 raise {
  match @fixed.read_i32(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=4, got=self.remaining())
    Some(v) => {
      self.at = self.at + 4
      v
    }
  }
}

///|
/// Thirty-two bits, unsigned, little endian.
pub fn Reader::read_u32(self : Reader) -> UInt32 raise {
  match @fixed.read_u32(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=4, got=self.remaining())
    Some(v) => {
      self.at = self.at + 4
      v
    }
  }
}

///|
/// Sixty-four bits, signed, little endian.
pub fn Reader::read_i64(self : Reader) -> Int64 raise {
  match @fixed.read_i64(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=8, got=self.remaining())
    Some(v) => {
      self.at = self.at + 8
      v
    }
  }
}

///|
/// Sixty-four bits, unsigned, little endian.
pub fn Reader::read_u64(self : Reader) -> UInt64 raise {
  match @fixed.read_u64(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=8, got=self.remaining())
    Some(v) => {
      self.at = self.at + 8
      v
    }
  }
}

///|
/// A single-precision float.
pub fn Reader::read_f32(self : Reader) -> Float raise {
  match @fixed.read_f32(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=4, got=self.remaining())
    Some(v) => {
      self.at = self.at + 4
      v
    }
  }
}

///|
/// A double-precision float.
pub fn Reader::read_f64(self : Reader) -> Double raise {
  match @fixed.read_f64(self.view, at=self.at, order=Little) {
    None => raise Refused::Truncated(at=self.at, want=8, got=self.remaining())
    Some(v) => {
      self.at = self.at + 8
      v
    }
  }
}

///|
/// A base-128 varint.
pub fn Reader::read_var_u64(self : Reader) -> UInt64 raise {
  let at = self.at
  let (v, n) = @leb128.decode(self.view, at=self.at) catch {
    _ => raise Refused::Truncated(at~, want=1, got=self.remaining())
  }
  self.at = self.at + n
  v
}

///|
/// A base-128 varint of thirty-two bits.
pub fn Reader::read_var_u32(self : Reader) -> UInt32 raise {
  self.read_var_u64().to_uint()
}

///|
/// A zigzag-folded varint: the signed half of `write_var_i64`.
pub fn Reader::read_var_i64(self : Reader) -> Int64 raise {
  @leb128.unzigzag(self.read_var_u64())
}

///|
/// The same for thirty-two bits.
pub fn Reader::read_var_i32(self : Reader) -> Int32 raise {
  self.read_var_i64().to_int()
}

///|
/// A sixty-four-bit signed integer that is usually small: four bytes whose low
/// bit says whether eight more follow.
pub fn Reader::read_tagged_i64(self : Reader) -> Int64 raise {
  let first = self.read_i32()
  if (first & 1) == 1 {
    self.read_i64()
  } else {
    first.to_int64() >> 1
  }
}

///|
/// A sixty-four-bit unsigned integer that is usually small.
pub fn Reader::read_tagged_u64(self : Reader) -> UInt64 raise {
  let first = self.read_u32()
  if (first & 1U) == 1U {
    self.read_u64()
  } else {
    first.to_uint64() >> 1
  }
}

///|
/// The string header: one byte while it fits in seven bits, a varint when it
/// does not.
pub fn Reader::read_var_u36(self : Reader) -> UInt64 raise {
  let at = self.at
  let v = self.read_byte()
  if v < 0x80 {
    v.to_uint64()
  } else {
    // The byte is the first byte of the varint, so step back over it.
    self.at = at
    self.read_var_u64()
  }
}

///|
/// `n` bytes, as they are.
pub fn Reader::read_bytes(self : Reader, n : Int32) -> Bytes raise {
  if n < 0 {
    raise Refused::TooLarge(
      at=self.at,
      limit=self.config.graph.to_int64(),
      got=n.to_int64(),
    )
  }
  if self.remaining() < n {
    raise Refused::Truncated(at=self.at, want=n, got=self.remaining())
  }
  let out = self.view.exact_view(start=self.at, end=self.at + n).to_owned()
  self.at = self.at + n
  out
}

///|
/// A string: the header says how many bytes and which of the three encodings
/// they are.
pub fn Reader::read_string(self : Reader) -> String raise {
  let header = self.read_var_u36()
  let size = (header >> 2).to_int()
  let encoding = header & 3UL
  self.spend(size)
  let at = self.at
  let bytes = self.read_bytes(size)
  if encoding == 2UL {
    if self.config.check_string {
      @utf8.decode(bytes[:]) catch {
        _ => raise Refused::BadEncoding(at~, got=2)
      }
    } else {
      bytes.to_unchecked_string()
    }
  } else if encoding == 0UL {
    latin1(bytes)
  } else if encoding == 1UL {
    @utf16.decode(bytes[:], endianness=Little) catch {
      _ => raise Refused::BadEncoding(at~, got=1)
    }
  } else {
    raise Refused::BadEncoding(at=self.at, got=encoding.to_int())
  }
}

///|
/// LATIN1, which the specification allows a writer to choose: one byte, one
/// character, the first two hundred and fifty-six of Unicode.
///
/// Widening it is what it is: the bytes are the code points, so each one is
/// written as the UTF-8 it stands for.
fn latin1(bytes : Bytes) -> String {
  let out = StringBuilder()
  for i in 0..<bytes.length() {
    out.write_char(bytes.at(i).to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
/// Bytes with their length in front: the BINARY type's body.
pub fn Reader::read_binary(self : Reader) -> Bytes raise {
  let n = self.read_var_u32().reinterpret_as_int()
  self.spend(n)
  self.read_bytes(n)
}

///|
/// A type ID byte.
pub fn Reader::read_type_id(self : Reader) -> TypeId raise {
  let at = self.at
  let v = self.read_byte()
  match TypeId::of(v) {
    Some(t) => t
    None => raise Refused::BadType(at~, got=v)
  }
}

///|
/// A type ID byte and the user type ID after it.
pub fn Reader::read_user_type(self : Reader) -> (TypeId, Int32) raise {
  let t = self.read_type_id()
  let user = self.read_var_u32().reinterpret_as_int()
  (t, user)
}

///|
/// The byte before a value, and what it says.
///
/// A reference to an id this message has not written is a refusal: there is
/// nothing to point at.
pub fn Reader::read_ref_flag(self : Reader) -> RefFlag raise {
  let at = self.at
  let v = self.read_i8()
  match v {
    -3 => Null
    -2 => {
      let id = self.read_var_u32().reinterpret_as_int()
      if id >= self.refs.length() {
        raise Refused::BadRef(at~, got=id)
      }
      Ref(id~)
    }
    -1 => NotNull
    0 => {
      let id = self.refs.length()
      // A value read a second time for a reference already has its id.
      if self.replay == 0 {
        self.refs.push(self.at)
      }
      RefValue(id~)
    }
    _ => raise Refused::BadEncoding(at~, got=v)
  }
}

///|
/// Where the value of a reference id starts, so it can be read again.
pub fn Reader::ref_offset(self : Reader, id : Int32) -> Int32 raise {
  if id < 0 || id >= self.refs.length() {
    raise Refused::BadRef(at=self.at, got=id)
  }
  self.refs[id]
}

///|
/// Put the reader back at `at`.
pub fn Reader::seek(self : Reader, at : Int32) -> Unit {
  self.at = at
}

///|
/// Go back to where the value of reference `id` was written and read it again,
/// which is what a reference asks for when the value was not a container put
/// aside. The answer is the offset to hand to `leave_ref` afterwards.
///
/// A reference that points into a value still being read is a cycle this
/// package cannot rebuild — a MoonBit value is finished before it is held — so
/// it is refused rather than read until the stack runs out.
pub fn Reader::enter_ref(self : Reader, id : Int32) -> Int32 raise {
  let offset = self.ref_offset(id)
  if self.replaying.contains(offset) {
    raise Refused::Cyclic(at=self.at, got=id)
  }
  self.replaying.push(offset)
  let saved = self.at
  self.at = offset
  self.replay = self.replay + 1
  saved
}

///|
/// Come back from a replay to where the read was.
pub fn Reader::leave_ref(self : Reader, saved : Int32) -> Unit {
  self.at = saved
  self.replay = self.replay - 1
  let _ = self.replaying.pop()
}

///|
/// The container being built for a reference id, when there is one.
///
/// A cycle points at a value that is not finished, so the container is put here
/// before its contents are read, and the reference finds it.
pub fn Reader::node(self : Reader, id : Int32) -> Value? {
  self.nodes.get(id)
}

///|
/// Remember the container being built for a reference id.
pub fn Reader::set_node(self : Reader, id : Int32, v : Value) -> Unit {
  self.nodes.set(id, v)
}

///|
/// Go one level deeper, refusing a message nested past what was configured.
pub fn Reader::enter(self : Reader) -> Unit raise {
  self.depth = self.depth + 1
  if self.depth > self.config.depth {
    raise Refused::TooDeep(at=self.at, limit=self.config.depth)
  }
}

///|
/// Come back one level.
pub fn Reader::leave(self : Reader) -> Unit {
  self.depth = self.depth - 1
}

///|
/// Count `n` bytes of declared payload against the budget for one message.
pub fn Reader::spend(self : Reader, n : Int32) -> Unit raise {
  self.spent = self.spent + n
  if self.spent > self.config.graph {
    raise Refused::TooLarge(
      at=self.at,
      limit=self.config.graph.to_int64(),
      got=self.spent.to_int64(),
    )
  }
}

///|
/// Refuse the bytes left over once a value has been read.
///
/// A message with two values in it is two messages, and reading one of them and
/// ignoring the rest is how a truncation goes unnoticed.
pub fn Reader::end(self : Reader) -> Unit raise {
  if self.at < self.view.length() {
    raise Refused::Trailing(at=self.at, got=self.view.length() - self.at)
  }
}
