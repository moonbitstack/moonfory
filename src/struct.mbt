// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One field of a struct: the description it carries, and what the wire needs
/// that a description has no word for.
///
/// The description is a `@moonmodel.Field` — a name, a kind, whether the value
/// may be absent, and what it means — so that a type described once can be
/// written by this package and still be published as a JSON Schema or a
/// `CREATE TABLE` without being written down twice. The three other members are
/// the wire's own: the type ID that kind goes out as, the tag that identifies
/// the field when the schema configures one, and whether the value may be
/// shared.
pub(all) struct FieldMeta {
  /// The description: name, kind, nullability, documentation.
  desc : @moonmodel.Field
  /// The type ID the description's kind goes out as.
  ty : TypeId
  /// The tag ID, when the schema configures one.
  ///
  /// The specification allows `0 <= tag < 2^29` and requires tags to be unique
  /// within a type; a tag sorts before every name, so adding one to a field
  /// moves it.
  tag : Int32?
  /// Whether the value may be shared, and so preceded by the tracking byte
  /// rather than the plain not-null one.
  track_ref : Bool
  /// The struct this field holds, when it holds one.
  ///
  /// A field's type is declared, so the wire does not say it again: a nested
  /// struct arrives as its fingerprint and its fields, with no type ID and no
  /// user type ID in front. The schema has to know which struct the field is,
  /// and this is where it says so — a field of type `Struct` with no child is
  /// one this reader cannot follow.
  child : StructMeta?
  /// The element type of a list, when the schema declares one.
  ///
  /// A writer that knows a list holds strings says so in the schema and leaves
  /// the type out of the list header, which is a byte saved per list. Reading
  /// such a list needs the type the schema left out, and this is where it is.
  element : TypeId?
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
/// A field that is simply there, named by hand.
///
/// `nullable` is a question about the value and goes into the description; a
/// kind the description has no word for is written as `Raw`, and the type ID
/// the caller gave stays the one it goes out as.
pub fn FieldMeta::new(
  name : String,
  ty : TypeId,
  tag~ : Int32? = None,
  nullable~ : Bool = false,
  track_ref~ : Bool = false,
  child~ : StructMeta? = None,
  element~ : TypeId? = None,
) -> FieldMeta {
  {
    desc: @moonmodel.Field::new(name, ty.kind(), nullable~),
    ty,
    tag,
    track_ref,
    child,
    element,
  }
}

///|
/// The field a description asks for: its kind decides the type ID.
///
/// A kind with no wire type — `Any`, or a `Raw` that does not name one of this
/// format's own — is refused rather than guessed at, because a field whose type
/// the other side cannot name is a field neither side can read.
pub fn FieldMeta::from(
  desc : @moonmodel.Field,
  tag~ : Int32? = None,
  track_ref~ : Bool = false,
  child~ : StructMeta? = None,
  element~ : TypeId? = None,
) -> FieldMeta raise {
  { desc, ty: TypeId::of_kind(desc.kind), tag, track_ref, child, element, }
}

///|
/// The field's name, which is what a peer reads it by.
pub fn FieldMeta::name(self : FieldMeta) -> String {
  self.desc.name
}

///|
/// The kind the description gives this field.
pub fn FieldMeta::kind(self : FieldMeta) -> @moonmodel.Type {
  self.desc.kind
}

///|
/// Whether the value may be absent. A nullable field is preceded by a flag byte
/// and sorts after every primitive that is not.
pub fn FieldMeta::nullable(self : FieldMeta) -> Bool {
  self.desc.nullable
}

///|
/// The field's identifier as the order sees it: the tag when there is one, and
/// the `snake_case` of the name when there is not.
pub fn FieldMeta::identifier(self : FieldMeta) -> String {
  match self.tag {
    Some(t) => t.to_string()
    None => snake(self.desc.name)
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
    (None, None) => compare_text(snake(a.desc.name), snake(b.desc.name))
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
    } else if f.nullable() {
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
/// A struct type: the description every projection shares, the user type ID it
/// is registered under, and one wire record per field.
///
/// The description is `@moonmodel.Model`, which is what `#model.derive` hands
/// back for a MoonBit type. The wire records are index-aligned with the model's
/// fields and carry the three things a description does not: the type ID, the
/// tag and the reference policy.
pub struct StructMeta {
  /// The description: the type's name, its documentation, and its fields.
  model_ : @moonmodel.Model
  /// The user type ID written after the type ID byte in same-schema mode.
  id_ : Int32
  /// Per field, in declaration order: the type ID, the tag, whether it may be
  /// shared, the struct it holds, and the element type of the list it holds.
  wire_ : Array[(TypeId, Int32?, Bool, StructMeta?, TypeId?)]
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
/// A struct described field by field, which is how a schema is written when
/// there is no `@moonmodel.Model` to hand.
///
/// The model is built from the fields: its name is `name`, its fields are the
/// descriptions the caller gave, in the order they were given.
pub fn StructMeta::new(
  name : String,
  user : Int32,
  fields : Array[FieldMeta],
) -> StructMeta {
  let descs : Array[@moonmodel.Field] = []
  let wire : Array[(TypeId, Int32?, Bool, StructMeta?, TypeId?)] = []
  for f in fields {
    descs.push(f.desc)
    wire.push((f.ty, f.tag, f.track_ref, f.child, f.element))
  }
  { model_: @moonmodel.Model::new(name, descs), id_: user, wire_: wire, }
}

///|
/// A struct described by a model, which is what `#model.derive` produces.
///
/// `tags` names the fields whose identifier is a tag rather than a name, and
/// `refs` the fields whose value may be shared; both are empty in the ordinary
/// case, where a field is known by its name and sent as itself.
///
/// A field whose kind has no wire type is refused: a description this format
/// cannot carry is better named than silently dropped.
pub fn StructMeta::of(
  model : @moonmodel.Model,
  user~ : Int32,
  tags~ : Map[String, Int32] = {},
  refs~ : Array[String] = [],
  children~ : Array[StructMeta] = [],
) -> StructMeta raise {
  let wire : Array[(TypeId, Int32?, Bool, StructMeta?, TypeId?)] = []
  for f in model.fields {
    wire.push(
      (
        TypeId::of_kind(f.kind),
        tags.get(f.name),
        refs.contains(f.name),
        child_of(f.kind, children),
        element_of(f.kind),
      ),
    )
  }
  { model_: model, id_: user, wire_: wire, }
}

///|
/// The element type a kind declares, when it declares one: a list of a kind the
/// type mapping has a word for.
fn element_of(kind : @moonmodel.Type) -> TypeId? {
  match kind {
    List(inner) =>
      match inner {
        Any => None
        _ => Some(TypeId::of_kind(inner)) catch { _ => None }
      }
    _ => None
  }
}

///|
/// The struct a kind refers to, when one of the schemas the caller handed over
/// is it: by name for a `Ref`, and by being the one nested for a `Nest`.
fn child_of(
  kind : @moonmodel.Type,
  children : Array[StructMeta],
) -> StructMeta? {
  match kind {
    Ref(name) => {
      let mut found = None
      for c in children {
        if c.name() == name {
          found = Some(c)
        }
      }
      found
    }
    Nest(model) => {
      let mut found = None
      for c in children {
        if c.name() == model.name {
          found = Some(c)
        }
      }
      found
    }
    _ => None
  }
}

///|
/// The struct's name, which a peer reading in compatible mode sees and which
/// this package writes down in its errors.
pub fn StructMeta::name(self : StructMeta) -> String {
  self.model_.name
}

///|
/// The user type ID the struct is registered under.
pub fn StructMeta::user(self : StructMeta) -> Int32 {
  self.id_
}

///|
/// The description, as the projections outside this package read it.
pub fn StructMeta::model(self : StructMeta) -> @moonmodel.Model {
  self.model_
}

///|
/// The fields, in the order they are declared, each joined to its wire record.
pub fn StructMeta::fields(self : StructMeta) -> Array[FieldMeta] {
  let out : Array[FieldMeta] = []
  for i in 0..<self.model_.fields.length() {
    let (ty, tag, track_ref, child, element) = self.wire_[i]
    out.push({
      desc: self.model_.fields[i],
      ty,
      tag,
      track_ref,
      child,
      element,
    })
  }
  out
}

///|
/// The indices of the fields in Fory order: the order their values are written
/// in, which is not the order they were declared in.
///
/// The order is computed rather than asked for, because a field added in the
/// middle of a declaration is a change no peer should have to be told about
/// twice.
pub fn StructMeta::order(self : StructMeta) -> Array[Int32] {
  let fields = self.fields()
  let indices : Array[Int32] = []
  for i in 0..<fields.length() {
    indices.push(i)
  }
  indices.sort_by(fn(a, b) { compare_field(fields[a], fields[b]) })
  indices
}

///|
/// The fields in Fory order.
pub fn StructMeta::ordered(self : StructMeta) -> Array[FieldMeta] {
  let fields = self.fields()
  let out : Array[FieldMeta] = []
  for i in self.order() {
    out.push(fields[i])
  }
  out
}

///|
/// The field a name refers to, which is what a reader needs when the order on
/// the wire is not the order it wants.
pub fn StructMeta::find(self : StructMeta, name : String) -> FieldMeta? {
  for f in self.fields() {
    if f.desc.name == name {
      return Some(f)
    }
  }
  None
}
