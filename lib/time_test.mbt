// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a date round-trips through the day count" {
  let date = @lib.date_of_days(19_000L)
  let bytes = @lib.dumps(date)
  let back : @moondate.Date = @lib.loads(bytes)
  inspect(back == date, content="true")
  inspect(@lib.days_of_date(date), content="19000")
}

///|
test "a moment round-trips through seconds and nanoseconds" {
  let moment = @lib.moment_of_parts(1_700_000_000L, 123_456_789)
  let bytes = @lib.dumps(moment)
  let back : @moondate.Moment = @lib.loads(bytes)
  let (seconds, nanos) = @lib.parts_of_moment(back)
  inspect(seconds, content="1700000000")
  inspect(nanos, content="123456789")
}

///|
test "a positive span splits into seconds and a sub-second part" {
  let (seconds, nanos) = @lib.parts_of_span(@lib.span_of_parts(3L, 500_000_000))
  inspect(seconds, content="3")
  inspect(nanos, content="500000000")
}

///|
test "a negative span normalises its nanoseconds into the second" {
  let span = @lib.span_of_parts(0L, 0)
  let (seconds, nanos) = @lib.parts_of_span(span)
  inspect(seconds, content="0")
  inspect(nanos, content="0")
  // One nanosecond before the epoch: seconds -1, nanos 999_999_999.
  let before = @lib.span_of_parts(-1L, 999_999_999)
  let (s2, n2) = @lib.parts_of_span(before)
  inspect(s2, content="-1")
  inspect(n2, content="999999999")
}

///|
test "a span travels as its two fields" {
  let span = @lib.span_of_parts(7L, 250_000_000)
  let bytes = @lib.dumps(span)
  let back : @moondate.Span = @lib.loads(bytes)
  let (seconds, nanos) = @lib.parts_of_span(back)
  inspect(seconds, content="7")
  inspect(nanos, content="250000000")
}
