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
/// Which of the two ways of giving a configuration wins when both are given.
///
/// `Extra` — the flat arguments — is the default, because a caller who took the
/// trouble to write `track_ref=true` on one call means it on that call.
pub(all) enum Wins {
  /// The record wins: the flat arguments are ignored where they clash.
  Base
  /// The flat arguments win. The default.
  Extra
} derive(Eq, Debug)

///|
pub extend Wins with Eq::{not_equal, equal}

///|
pub extend Wins with Debug::{to_repr}

///|
/// What to do when the same setting is given twice, once in the record and once
/// as a flat argument.
pub(all) enum OnClash[T] {
  /// Take one of them silently: the one `wins` says.
  Ignore
  /// Refuse the call.
  Panic
  /// Let the caller decide. The pair is (the record's, the flat one's).
  Handle((T, T) -> T)
}

///|
/// The flat mirrors of a `Config`: each one is `None` when the caller did not
/// give it, which is what tells a setting given once from a setting given twice.
priv struct Patch {
  xlang : Bool?
  track_ref : Bool?
  check_string : Bool?
  depth : Int32?
  fields : Int32?
  graph : Int32?
}

///|
/// What `OnClash::Panic` raises: a setting given twice where the caller asked
/// to hear about it.
pub(all) suberror Clashed {
  /// The name of the setting, and the two values it was given.
  Clashed(name~ : String)
} derive(Eq, Debug)

///|
pub impl Show for Clashed with fn output(self, logger) {
  match self {
    Clashed(name~) => logger.write_string("Clashed(name=\{name})")
  }
}

///|
pub extend Clashed with Debug::{to_repr}

///|
pub extend Clashed with Show::{to_string, output}

///|
pub extend Clashed with Eq::{not_equal, equal}

///|
/// Whether a flat mirror contradicts the record it was given beside.
fn clashes(base : Config, patch : Patch) -> Bool {
  match patch.xlang {
    Some(v) => if v != base.xlang { return true }
    None => ()
  }
  match patch.track_ref {
    Some(v) => if v != base.track_ref { return true }
    None => ()
  }
  match patch.check_string {
    Some(v) => if v != base.check_string { return true }
    None => ()
  }
  match patch.depth {
    Some(v) => if v != base.depth { return true }
    None => ()
  }
  match patch.fields {
    Some(v) => if v != base.fields { return true }
    None => ()
  }
  match patch.graph {
    Some(v) => if v != base.graph { return true }
    None => ()
  }
  false
}

///|
/// The two as one, in the direction `wins` names: `Extra` takes the flat mirror,
/// `Base` keeps the record.
fn apply(base : Config, patch : Patch, wins : Wins) -> Config {
  {
    xlang: if wins == Extra {
      match patch.xlang {
        Some(v) => v
        None => base.xlang
      }
    } else {
      base.xlang
    },
    track_ref: if wins == Extra {
      match patch.track_ref {
        Some(v) => v
        None => base.track_ref
      }
    } else {
      base.track_ref
    },
    check_string: if wins == Extra {
      match patch.check_string {
        Some(v) => v
        None => base.check_string
      }
    } else {
      base.check_string
    },
    depth: if wins == Extra {
      match patch.depth {
        Some(v) => v
        None => base.depth
      }
    } else {
      base.depth
    },
    fields: if wins == Extra {
      match patch.fields {
        Some(v) => v
        None => base.fields
      }
    } else {
      base.fields
    },
    graph: if wins == Extra {
      match patch.graph {
        Some(v) => v
        None => base.graph
      }
    } else {
      base.graph
    },
  }
}

///|
/// The configuration one call runs under.
///
/// The library preset is beaten by the record, and the record by this call's
/// flat mirrors — unless `wins` says otherwise. A flat mirror that contradicts
/// the record beside it is what `clash` arbitrates: taken silently by `wins`,
/// refused, or handed to the caller's function as (the record, the two as one).
pub fn resolve(
  config : Config?,
  xlang : Bool?,
  track_ref : Bool?,
  check_string : Bool?,
  depth : Int32?,
  fields : Int32?,
  graph : Int32?,
  wins : Wins?,
  clash : OnClash[Config]?,
) -> Config raise {
  let base = match config {
    Some(given) => given
    None => Config::new()
  }
  let patch : Patch = { xlang, track_ref, check_string, depth, fields, graph, }
  let wins = match wins {
    Some(given) => given
    None => Extra
  }
  let merged = apply(base, patch, wins)
  match clash {
    Some(Ignore) => merged
    Some(Panic) =>
      if clashes(base, patch) {
        raise Clashed::Clashed(name="config")
      } else {
        merged
      }
    Some(Handle(arbitrate)) => arbitrate(base, merged)
    None => merged
  }
}
