// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a reader will accept and what a writer will send.
///
/// Every default here is the Rust `fory` crate's `Config::default()`, because
/// that is the reference implementation the specification names first, and
/// because a default nobody else shares is a default an interop test finds.
/// Where this package has no counterpart for one of its knobs — the schema
/// version check, the type-meta cache — the knob is absent rather than inert.
pub(all) struct Config {
  /// Whether the header byte carries the cross-language flag.
  ///
  /// The xlang format is the one implemented here, so this is `true`; a writer
  /// asked for `false` writes a header without the flag, and a reader asked for
  /// `true` refuses one.
  xlang : Bool
  /// Whether values that are written more than once, or that take part in a
  /// cycle, are sent once and pointed at afterwards.
  ///
  /// Off by default, as in the Rust crate: reference tracking costs a byte per
  /// tracked value and a table on both sides, which a graph without sharing
  /// should not pay for. Turn it on and mark the shared nodes with `shared`.
  track_ref : Bool
  /// Whether the bytes of a string are checked as UTF-8 before they become a
  /// `String`.
  ///
  /// On by default, as in the Rust crate. Turning it off is a promise that the
  /// peer is trusted, not a way to read a string that is not one.
  check_string : Bool
  /// How deeply values may nest before a message is refused.
  ///
  /// Five is the Rust crate's `max_dyn_depth`. A message of ten thousand open
  /// lists is a denial of service rather than a message, and the depth is the
  /// one number that stops it before the stack does.
  depth : Int32
  /// How many fields a struct may declare before a message is refused.
  ///
  /// Five hundred and twelve is the Rust crate's `max_type_fields`. The count
  /// is written by the message and read before the fields are, so it is the
  /// cheapest place to stop a message that claims more fields than it has.
  fields : Int32
  /// How many bytes of variable-length payload one message may declare before
  /// it is refused: strings, binaries, dense arrays and container bodies added
  /// up as they are read.
  ///
  /// A hundred and twenty-eight mebibytes is the Rust crate's
  /// `max_graph_memory_bytes`. Declared lengths are already bounded by the
  /// bytes actually present, so this gate is the one that bounds a message
  /// made of many small declarations whose total is a large allocation.
  graph : Int32
}

///|
/// The preset every entry point takes when it is not given one.
///
/// Named `config` so that an argument reads `config=config` and an update reads
/// `{ ..config, track_ref: true }`.
pub let config : Config = {
  xlang: true,
  track_ref: false,
  check_string: true,
  depth: 5,
  fields: 512,
  graph: 134_217_728,
}

///|
/// The same preset, one argument at a time.
///
/// For when several parts differ at once and a record update would mean
/// spelling the ones that did not change.
pub fn Config::new(
  xlang~ : Bool = config.xlang,
  track_ref~ : Bool = config.track_ref,
  check_string~ : Bool = config.check_string,
  depth~ : Int32 = config.depth,
  fields~ : Int32 = config.fields,
  graph~ : Int32 = config.graph,
) -> Config {
  { xlang, track_ref, check_string, depth, fields, graph, }
}

///|
/// The configuration one call runs under.
///
/// The library preset is beaten by the record, and the record by this call's
/// flat mirrors, unless `wins` says otherwise; with no record, the preset
/// stands in for it. A flat mirror whose value differs from the record's is
/// what `clash` arbitrates: taken by `wins` silently or with a warning,
/// aborted on, or handed to the caller's function. Both are `moonknob`'s.
pub fn resolve(
  config : Config?,
  xlang : Bool?,
  track_ref : Bool?,
  check_string : Bool?,
  depth : Int32?,
  fields : Int32?,
  graph : Int32?,
  wins : @moonknob.Wins?,
  clash : @moonknob.OnClash[Config]?,
) -> Config {
  let base = match config {
    Some(given) => given
    None => Config::new()
  }
  let merge = @moonknob.Merge::new(wins.unwrap_or(Extra))
  let merged = {
    xlang: merge.pick("xlang", base.xlang, xlang),
    track_ref: merge.pick("track_ref", base.track_ref, track_ref),
    check_string: merge.pick("check_string", base.check_string, check_string),
    depth: merge.pick("depth", base.depth, depth),
    fields: merge.pick("fields", base.fields, fields),
    graph: merge.pick("graph", base.graph, graph),
  }
  merge.settle(
    clash.unwrap_or(Ignore),
    base,
    merged,
    "moonfory: the config and the flat arguments",
  )
}
