// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The fingerprint of a struct: the number every language writes after the user
// type ID, so that a reader can tell a schema it agrees with from one it only
// thinks it agrees with.
//
// The fingerprint is a string — one line per field, `identifier,type,ref,null;`
// — and the number is the low half of its MurmurHash3 x64 128, seeded with 47.
// Both halves are the specification's; a peer computes the same number from the
// same schema, which is the only reason the check means anything.

///|
/// The fingerprint of a struct, as the text the hash is taken of.
///
/// Fields enter in identifier order, which is not the order they are written
/// in: the fingerprint is about the schema, and the schema does not depend on
/// how the values are laid out. A field of a user type contributes `UNKNOWN`
/// rather than its own type ID, because two languages name their own types
/// differently and a hash over the name would never agree.
fn fingerprint(fields : Array[FieldMeta]) -> String {
  let sorted = fields.copy()
  sorted.sort_by(fn(a, b) { compare_identifier(a, b) })
  let out = StringBuilder()
  for f in sorted {
    out.write_string(f.identifier())
    out.write_char(',')
    out.write_string((if f.ty.is_user() { 0 } else { f.ty.code() }).to_string())
    out.write_char(',')
    // A field of a user type never counts as shared here, whatever the schema
    // says about the slot it sits in: both reference implementations compute
    // this flag from the type and not from the place, so a schema that says
    // otherwise would fingerprint differently from a peer that can read it.
    out.write_char(if f.track_ref && !f.ty.is_user() { '1' } else { '0' })
    out.write_char(',')
    out.write_char(if f.nullable() { '1' } else { '0' })
    // A list says what it holds, because a list of strings and a list of
    // integers are different schemas with the same type ID. The element is
    // written as a type and two zeroes: an element is not a slot, so it is
    // never shared and never absent.
    match f.element {
      Some(element) =>
        if f.ty == List || f.ty == Set {
          out.write_char('[')
          out.write_string(
            (if element.is_user() { 0 } else { element.code() }).to_string(),
          )
          out.write_string(",0,0]")
        }
      None => ()
    }
    out.write_char(';')
  }
  out.to_string()
}

///|
/// The number written after a user type ID in same-schema mode.
pub fn StructMeta::hash(self : StructMeta) -> Int32 {
  let text = fingerprint(self.fields())
  murmur3_low32(@utf8.encode(text), 47)
}

///|
/// The low thirty-two bits of MurmurHash3 x64 128 over `bytes`, seeded with
/// `seed`.
fn murmur3_low32(bytes : Bytes, seed : UInt32) -> Int32 {
  let c1 = 0x87c37b91114253d5UL
  let c2 = 0x4cf5ad432745937fUL
  let mut h1 = seed.to_uint64()
  let mut h2 = h1
  let n = bytes.length()
  let view = bytes[:]
  let blocks = n / 16
  for i in 0..<blocks {
    let mut k1 = read_u64_le(view, i * 16) * c1
    k1 = rotl64(k1, 31) * c2
    h1 = h1 ^ k1
    h1 = rotl64(h1, 27) + h2
    h1 = h1 * 5UL + 0x52dce729UL
    let mut k2 = read_u64_le(view, i * 16 + 8) * c2
    k2 = rotl64(k2, 33) * c1
    h2 = h2 ^ k2
    h2 = rotl64(h2, 31) + h1
    h2 = h2 * 5UL + 0x38495ab5UL
  }
  let tail = n - blocks * 16
  let mut k1 = 0UL
  let mut k2 = 0UL
  for i in 0..<tail {
    let b = view.at(blocks * 16 + i).to_int().reinterpret_as_uint().to_uint64()
    if i < 8 {
      k1 = k1 | (b << (i * 8))
    } else {
      k2 = k2 | (b << ((i - 8) * 8))
    }
  }
  if tail > 8 {
    h2 = h2 ^ (rotl64(k2 * c2, 33) * c1)
  }
  if tail > 0 {
    h1 = h1 ^ (rotl64(k1 * c1, 31) * c2)
  }
  let len = n.to_uint64()
  h1 = h1 ^ len
  h2 = h2 ^ len
  h1 = h1 + h2
  h2 = h2 + h1
  h1 = fmix64(h1)
  h2 = fmix64(h2)
  h1 = h1 + h2
  (h1 & 0xffffffffUL).to_uint().reinterpret_as_int()
}

///|
/// The final avalanche of MurmurHash3.
fn fmix64(input : UInt64) -> UInt64 {
  let mut k = input ^ (input >> 33)
  k = k * 0xff51afd7ed558ccdUL
  k = k ^ (k >> 33)
  k = k * 0xc4ceb9fe1a85ec53UL
  k ^ (k >> 33)
}

///|
/// Rotate sixty-four bits left.
fn rotl64(x : UInt64, n : Int32) -> UInt64 {
  (x << n) | (x >> (64 - n))
}

///|
/// Eight bytes, little endian.
fn read_u64_le(view : BytesView, at : Int32) -> UInt64 {
  let mut out = 0UL
  for i in 0..<8 {
    out = out |
      (view.at(at + i).to_int().reinterpret_as_uint().to_uint64() << (i * 8))
  }
  out
}
