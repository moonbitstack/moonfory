// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Bytes as text, and text as bytes.
///
/// A wire format is read by eye before it is read by anything else, and every
/// fixture in this repository is a line of text: the bytes a peer sent, written
/// down. These two are how a message gets from a shell into a test and back
/// out again.
pub fn hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef".to_array()
  let out = StringBuilder()
  for i in 0..<bytes.length() {
    let v = bytes[i].to_int()
    out.write_char(digits[(v >> 4) & 0x0f])
    out.write_char(digits[v & 0x0f])
  }
  out.to_string()
}

///|
/// The bytes a line of hexadecimal stands for.
///
/// A character that is not one, or an odd number of them, is refused: a
/// fixture that was meant to be bytes and is not should say so at the offset
/// rather than read as a shorter message than it was.
pub fn unhex(text : String) -> Bytes raise {
  let chars = text.to_array()
  if (chars.length() & 1) != 0 {
    raise Refused::BadEncoding(at=chars.length(), got=chars.length())
  }
  let out = Buffer()
  let pairs = chars.length() / 2
  for i in 0..<pairs {
    let high = digit(chars[2 * i], 2 * i)
    let low = digit(chars[2 * i + 1], 2 * i + 1)
    out.write_byte((high * 16 + low).to_byte())
  }
  out.to_bytes()
}

///|
/// One character, as the number it stands for.
fn digit(c : Char, at : Int32) -> Int32 raise {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    raise Refused::BadEncoding(at~, got=c.to_int())
  }
}
