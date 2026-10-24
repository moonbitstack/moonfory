// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One field of a struct: what it is called, what type it is on the wire, and
/// whether it may be absent or pointed at.
///
/// MoonBit has no `derive` a package outside the compiler can extend, so a
/// schema is written down rather than generated: this is the shape a hand
/// writes once per type, and the shape a generator writes later.
pub(all) struct FieldMeta {
  /// The name. It is the field's identifier when no tag is configured, and it
  /// is what a peer reads the field by.
  name : String
  /// The tag ID, when the schema configures one.
  ///
  /// The specification allows `0 <= tag < 2^29` and requires tags to be unique
  /// within a type; a tag sorts before every name, so adding one to a field
  /// moves it.
  tag : Int32?
  /// The type on the wire.
  ty : TypeId
  /// Whether the value may be absent. A nullable field is preceded by a flag
  /// byte and sorts after every primitive that is not.
  nullable : Bool
  /// Whether the value may be shared, and so preceded by the tracking byte
  /// rather than the plain not-null one.
  track_ref : Bool
} derive(Eq, Debug)

///|
pub impl Show for FieldMeta with fn output(self, logger) {
  logger.write_string("\{self.to_repr()}")
}

///|
pub extend FieldMeta with Debug::{to_repr}

///|
pub extend FieldMeta with Show::{to_string, output}

///|
pub extend FieldMeta with Eq::{not_equal, equal}

///|
/// A field that is simply there.
pub fn FieldMeta::new(
  name : String,
  ty : TypeId,
  tag~ : Int32? = None,
  nullable~ : Bool = false,
  track_ref~ : Bool = false,
) -> FieldMeta {
  { name, tag, ty, nullable, track_ref, }
}

///|
/// The field's identifier as the order sees it: the tag when there is one, and
/// the `snake_case` of the name when there is not.
pub fn FieldMeta::identifier(self : FieldMeta) -> String {
  match self.tag {
    Some(t) => t.to_string()
    None => snake(self.name)
  }
}

///|
/// `userName` as `user_name`, which is what the specification orders untagged
/// fields by.
///
/// A run of capitals stays one word, so `HTTPServer` is `http_server` and not
/// `h_t_t_p_server`.
fn snake(name : String) -> String {
  let chars = name.to_array()
  let out = StringBuilder()
  let mut previous_was_word = false
  for i in 0..<chars.length() {
    let c = chars[i]
    let upper = c >= 'A' && c <= 'Z'
    if upper {
      let next_is_lower = i + 1 < chars.length() &&
        chars[i + 1] >= 'a' &&
        chars[i + 1] <= 'z'
      if previous_was_word && (next_is_lower || !previous_was_word) {
        out.write_char('_')
      }
      out.write_char(lower(c))
      previous_was_word = true
    } else {
      let is_word = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
      out.write_char(c)
      previous_was_word = is_word
    }
  }
  out.to_string()
}

///|
/// The same letter, lower: `Char` carries no case of its own in MoonBit.
fn lower(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    (c.to_int() + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
/// Which of two fields comes first, by the identifier alone: a tag before a
/// name, and two names in `snake_case` order.
fn compare_identifier(a : FieldMeta, b : FieldMeta) -> Int32 {
  match (a.tag, b.tag) {
    (Some(x), Some(y)) => if x < y { -1 } else if x > y { 1 } else { 0 }
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => compare_text(snake(a.name), snake(b.name))
  }
}

///|
/// Two strings in the order a dictionary would put them, which is not the order
/// `String` compares in: that one answers length first.
fn compare_text(a : String, b : String) -> Int32 {
  let x = a.to_array()
  let y = b.to_array()
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    let d = x[i].to_int() - y[i].to_int()
    if d != 0 {
      return d
    }
  }
  x.length() - y.length()
}

///|
/// Which of two fields comes first, by the rules the specification lays down so
/// that every language writes the same order.
///
/// Three groups — primitives that cannot be absent, primitives that can, and
/// everything else — and inside them the keys the specification names: for the
/// primitives, fixed width before compressed, then width descending, then type
/// ID, then identifier; for the rest, the identifier alone.
pub fn compare_field(a : FieldMeta, b : FieldMeta) -> Int32 {
  let group = fn(f : FieldMeta) -> Int32 {
    if !f.ty.is_primitive() {
      2
    } else if f.nullable {
      1
    } else {
      0
    }
  }
  let ga = group(a)
  let gb = group(b)
  if ga != gb {
    return ga - gb
  }
  if ga < 2 {
    let ca = if a.ty.is_compressed() { 1 } else { 0 }
    let cb = if b.ty.is_compressed() { 1 } else { 0 }
    if ca != cb {
      return ca - cb
    }
    let sa = match a.ty.fixed_size() {
      Some(n) => n
      None => 0
    }
    let sb = match b.ty.fixed_size() {
      Some(n) => n
      None => 0
    }
    if sa != sb {
      return sb - sa
    }
    if a.ty.code() != b.ty.code() {
      return a.ty.code() - b.ty.code()
    }
  }
  compare_identifier(a, b)
}

///|
/// A struct type: its name, the ID it is registered under, and its fields.
pub(all) struct StructMeta {
  /// The type name, which a peer reading in compatible mode sees.
  name : String
  /// The user type ID written after the type ID byte in same-schema mode.
  user : Int32
  /// The fields, in the order they are declared.
  fields : Array[FieldMeta]
} derive(Eq, Debug)

///|
pub impl Show for StructMeta with fn output(self, logger) {
  logger.write_string("\{self.to_repr()}")
}

///|
pub extend StructMeta with Debug::{to_repr}

///|
pub extend StructMeta with Show::{to_string, output}

///|
pub extend StructMeta with Eq::{not_equal, equal}

///|
pub fn StructMeta::new(
  name : String,
  user : Int32,
  fields : Array[FieldMeta],
) -> StructMeta {
  { name, user, fields, }
}

///|
/// The indices of the fields in Fory order: the order their values are written
/// in, which is not the order they were declared in.
///
/// The order is computed rather than asked for, because a field added in the
/// middle of a declaration is a change no peer should have to be told about
/// twice.
pub fn StructMeta::order(self : StructMeta) -> Array[Int32] {
  let indices : Array[Int32] = []
  for i in 0..<self.fields.length() {
    indices.push(i)
  }
  indices.sort_by(fn(a, b) { compare_field(self.fields[a], self.fields[b]) })
  indices
}

///|
/// The fields in Fory order.
pub fn StructMeta::ordered(self : StructMeta) -> Array[FieldMeta] {
  let out : Array[FieldMeta] = []
  for i in self.order() {
    out.push(self.fields[i])
  }
  out
}

///|
/// The field a name or a tag refers to, which is what a reader needs when the
/// order on the wire is not the order it wants.
pub fn StructMeta::find(self : StructMeta, name : String) -> FieldMeta? {
  for f in self.fields {
    if f.name == name {
      return Some(f)
    }
  }
  None
}
