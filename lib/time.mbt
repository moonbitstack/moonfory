// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The three time types the cross-language format carries, wired to moonbitstack's
// calendar types so a MoonBit program never has to spell out epoch seconds itself.
//
//   DATE      days since 1970-01-01, a signed varint64
//   TIMESTAMP seconds since the epoch, int64, then nanoseconds, uint32
//   DURATION  whole seconds, signed varint64, then nanoseconds, int32
//
// The nanosecond field is the sub-second part, always in [0, 1e9), so a value of
// 1.5 seconds is (1, 500_000_000) and never (0, 1_500_000_000).

/// The day count of a date, as the wire carries it: days since 1970-01-01.
pub fn date_of_days(days : Int64) -> @moondate.Date {
  @moondate.Date::of_days(days.to_int())
}

/// The days since 1970-01-01 for a date.
pub fn days_of_date(date : @moondate.Date) -> Int64 {
  date.days().to_int64()
}

/// The whole seconds and the sub-second nanoseconds of a moment.
pub fn parts_of_moment(moment : @moondate.Moment) -> (Int64, Int32) {
  let seconds = match moment.epoch() {
    Some(s) => s
    None => 0L
  }
  let nanos = (moment.time().nanos() % 1_000_000_000L).to_int()
  (seconds, nanos)
}

/// The moment `seconds` after the epoch, plus `nanos` nanoseconds.
pub fn moment_of_parts(seconds : Int64, nanos : Int32) -> @moondate.Moment {
  @moondate.Moment::of_epoch(seconds, nano=nanos)
}

/// The whole seconds and the sub-second nanoseconds of a span. The nanoseconds are
/// normalised into [0, 1e9), borrowing a second when the span is negative.
pub fn parts_of_span(span : @moondate.Span) -> (Int64, Int32) {
  let n = span.nanos
  let mut seconds = n / 1_000_000_000L
  let mut nanos = n % 1_000_000_000L
  if nanos < 0L {
    nanos = nanos + 1_000_000_000L
    seconds = seconds - 1L
  }
  (seconds, nanos.to_int())
}

/// The span from `seconds` and `nanos`.
pub fn span_of_parts(seconds : Int64, nanos : Int32) -> @moondate.Span {
  @moondate.Span::new(seconds=seconds, nanos=nanos.to_int64())
}

/// A date travels as DATE.
pub impl Codec for @moondate.Date with fn ty(_self) {
  TypeId::Date
}

///|
pub impl Codec for @moondate.Date with fn write_data(self, w) {
  w.write_var_i64(days_of_date(self))
}

///|
pub impl Codec for @moondate.Date with fn read_data(_r, _ty) {
  date_of_days(_r.read_var_i64())
}

/// A moment travels as TIMESTAMP.
pub impl Codec for @moondate.Moment with fn ty(_self) {
  TypeId::Timestamp
}

///|
pub impl Codec for @moondate.Moment with fn write_data(self, w) {
  let (seconds, nanos) = parts_of_moment(self)
  w.write_i64(seconds)
  w.write_u32(nanos.reinterpret_as_uint())
}

///|
pub impl Codec for @moondate.Moment with fn read_data(r, _ty) {
  let seconds = r.read_i64()
  let nanos = r.read_u32().reinterpret_as_int()
  moment_of_parts(seconds, nanos)
}

/// A span travels as DURATION.
pub impl Codec for @moondate.Span with fn ty(_self) {
  TypeId::Duration
}

///|
pub impl Codec for @moondate.Span with fn write_data(self, w) {
  let (seconds, nanos) = parts_of_span(self)
  w.write_var_i64(seconds)
  w.write_i32(nanos)
}

///|
pub impl Codec for @moondate.Span with fn read_data(r, _ty) {
  let seconds = r.read_var_i64()
  let nanos = r.read_i32()
  span_of_parts(seconds, nanos)
}
