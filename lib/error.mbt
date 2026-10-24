// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a message was refused.
///
/// A message that cannot be read is a refusal, never a partial answer: every
/// name here is something the writer did that the specification does not allow,
/// and every one of them carries the offset it happened at, because a byte
/// stream has no line numbers to point at.
pub(all) suberror Refused {
  /// The message ends in the middle of a value.
  Truncated(at~ : Int32, want~ : Int32, got~ : Int32)
  /// A counted thing is past the limit this reader was configured with.
  TooLarge(at~ : Int32, limit~ : Int64, got~ : Int64)
  /// Values nested deeper than the configured depth.
  TooDeep(at~ : Int32, limit~ : Int32)
  /// A type ID the mapping does not define.
  BadType(at~ : Int32, got~ : Int32)
  /// A type ID where the schema demands a different one.
  WantType(at~ : Int32, want~ : Int32, got~ : Int32)
  /// A header byte that is not an xlang header.
  BadHeader(at~ : Int32, got~ : Int32)
  /// A reference to an id this message has not written yet.
  BadRef(at~ : Int32, got~ : Int32)
  /// A wire value the format does not define: a reserved string encoding, a
  /// chunk size of zero, a boolean that is neither.
  BadEncoding(at~ : Int32, got~ : Int32)
  /// A graph whose cycle reaches back into a value still being built, where
  /// rebuilding it would recur for ever.
  Cyclic(at~ : Int32, got~ : Int32)
  /// Bytes left over once the value has been read.
  Trailing(at~ : Int32, got~ : Int32)
  /// A value with no cross-language counterpart.
  Unsupported(kind~ : String)
} derive(Eq, Debug)

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Truncated(at~, want~, got~) =>
      logger.write_string("Truncated(at=\{at}, want=\{want}, got=\{got})")
    TooLarge(at~, limit~, got~) =>
      logger.write_string("TooLarge(at=\{at}, limit=\{limit}, got=\{got})")
    TooDeep(at~, limit~) =>
      logger.write_string("TooDeep(at=\{at}, limit=\{limit})")
    BadType(at~, got~) => logger.write_string("BadType(at=\{at}, got=\{got})")
    WantType(at~, want~, got~) =>
      logger.write_string("WantType(at=\{at}, want=\{want}, got=\{got})")
    BadHeader(at~, got~) =>
      logger.write_string("BadHeader(at=\{at}, got=\{got})")
    BadRef(at~, got~) => logger.write_string("BadRef(at=\{at}, got=\{got})")
    BadEncoding(at~, got~) =>
      logger.write_string("BadEncoding(at=\{at}, got=\{got})")
    Cyclic(at~, got~) => logger.write_string("Cyclic(at=\{at}, got=\{got})")
    Trailing(at~, got~) => logger.write_string("Trailing(at=\{at}, got=\{got})")
    Unsupported(kind~) => logger.write_string("Unsupported(kind=\{kind})")
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}
