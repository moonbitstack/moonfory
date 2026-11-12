#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Have `pyfory` read the messages this package wrote, and say what it made of them.

    moon run src/examples/wire --target native > wire.tsv
    python3 scripts/check_peer_reads.py wire.tsv

`src/examples/wire` prints one message per class as `name<TAB>hex`; this reads
each line with the Python implementation and requires the value the class
stands for. That is the direction a byte-level fixture cannot check on its own:
a fixture proves this package reads what Python wrote, and this proves Python
reads what this package writes.

Every line has an expectation below, and a line without one fails rather than
passes, so a class added to the example cannot slip through unchecked. Run it
by hand, or in the interop job of the workflow; it needs `pyfory`, which is the
peer and not a dependency of the module.
"""

import datetime
import decimal
import pathlib
import sys

import pyfory
from dataclasses import dataclass


@dataclass
class Point:
    x: pyfory.Int32
    y: pyfory.Int32


# What each class of message stands for. The same list `scripts/interop.py`
# writes, plus the two compressed widths the example adds by hand.
EXPECTED = {
    "bool": True,
    "int32": 42,
    "int64": 42,
    "varint32": 42,
    "varint64": 42,
    "float64": 1.5,
    "string": "世界",
    "binary": b"ab",
    "list_int": [1, 2, 3],
    "list_str": ["a", "b"],
    "map_str_int": {"a": 1},
    "int32_array": [1, 2, 3],
    "decimal": decimal.Decimal("123.45"),
    "timestamp": datetime.datetime(1970, 1, 1, 0, 0, 1, 500000, tzinfo=datetime.timezone.utc),
    "date": datetime.date(1970, 1, 2),
    "duration": datetime.timedelta(seconds=90, microseconds=500),
    "struct_point": Point(1, 2),
}

# A dense array reads back as the array type rather than as a list, and the
# array type is not a `list`: the elements are the same, which is what the
# message said.
ARRAYS = {"int32_array"}


def flatten(value):
    """The elements of a dense array, as a list, so it compares with the list
    the message stands for."""
    return list(value)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_peer_reads.py <name-tab-hex file>", file=sys.stderr)
        return 2
    fory = pyfory.Fory(xlang=True, ref=False, compatible=False)
    fory.register_type(Point, type_id=100)

    seen = 0
    failed = 0
    for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        name, _, text = line.partition("\t")
        if name not in EXPECTED:
            print("%-14s no expectation in this script" % name, file=sys.stderr)
            failed += 1
            continue
        want = EXPECTED[name]
        try:
            value = fory.deserialize(bytes.fromhex(text))
            got = flatten(value) if name in ARRAYS else value
        except Exception as error:  # the peer's own error is the answer
            print("%-14s refused: %s" % (name, error), file=sys.stderr)
            failed += 1
            continue
        if got != want:
            print("%-14s read %r, wanted %r" % (name, got, want), file=sys.stderr)
            failed += 1
            continue
        print("%-14s %r" % (name, got))
        seen += 1

    if seen + failed != len(EXPECTED):
        print(
            "%d of %d classes present: a class of message is missing from the example"
            % (seen + failed, len(EXPECTED)),
            file=sys.stderr,
        )
        failed += 1
    print("pyfory %s read %d of %d messages" % (pyfory.__version__, seen, len(EXPECTED)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
