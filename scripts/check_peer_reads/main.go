// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Have Go's `fory` read the messages this package wrote, and say what it made of
// them.
//
//	moon run src/examples/wire --target native > wire.tsv
//	go run ./check_peer_reads wire.tsv
//
// `src/examples/wire` prints one message per class as `name<TAB>hex`; this reads
// each line into the Go type that class stands for. It is the direction the
// checked-in fixtures cannot cover: those prove this package reads what Go
// wrote, and this proves Go reads what this package writes.
//
// A class this program does not read is named at the end with the reason, and
// the run fails only on a message that was read and read wrongly: a silent skip
// is the one outcome that would make the check worth nothing.
package main

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"

	"github.com/apache/fory/go/fory"
)

// Point is the schema the example writes under user type ID 100.
type Point struct {
	X int32
	Y int32
}

// skip is a class of message this peer has no target for, and why. Go's reader
// decodes an integer as a zigzag varint whatever type ID the message carries,
// where this package writes `Int` as `INT32`; the classes below are the ones
// that cannot be read for that reason. `varint32` and `varint64` are the same
// numbers in the form Go expects.
var skip = map[string]string{
	"int32":       "Go decodes an integer as a zigzag varint; this message is INT32",
	"int64":       "Go decodes an integer as a zigzag varint; this message is INT64",
	"list_int":    "Go decodes list elements as zigzag varints; these are INT32",
	"map_str_int": "Go decodes map values as zigzag varints; these are INT32",
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: check_peer_reads <name-tab-hex file>")
		os.Exit(2)
	}
	f := fory.NewFory(fory.WithXlang(true), fory.WithTrackRef(false), fory.WithCompatible(false))
	if err := f.RegisterStruct(&Point{}, 100); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer file.Close()

	read, failed := 0, 0
	skipped := make([]string, 0, len(skip))
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		name, text, found := strings.Cut(line, "\t")
		if !found {
			fmt.Fprintf(os.Stderr, "%-14s not a name and bytes\n", name)
			failed++
			continue
		}
		if reason, ok := skip[name]; ok {
			skipped = append(skipped, fmt.Sprintf("%s (%s)", name, reason))
			continue
		}
		bytes, err := hex.DecodeString(text)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%-14s %v\n", name, err)
			failed++
			continue
		}
		detail, err := one(f, name, bytes)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%-14s %v\n", name, err)
			failed++
			continue
		}
		fmt.Printf("%-14s %s\n", name, detail)
		read++
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Printf("go fory read %d of %d messages\n", read, read+len(skipped))
	for _, one := range skipped {
		fmt.Printf("  not read: %s\n", one)
	}
	if failed > 0 {
		fmt.Fprintf(os.Stderr, "%d messages were read wrongly\n", failed)
		os.Exit(1)
	}
}

// one reads a single message into the type its class stands for and checks the
// value, returning the value as text or the mismatch.
func one(f *fory.Fory, name string, bytes []byte) (string, error) {
	switch name {
	case "bool":
		var v bool
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		return expect(name, v, true)
	case "varint32":
		var v int32
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		return expect(name, v, int32(42))
	case "varint64":
		var v int64
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		return expect(name, v, int64(42))
	case "float64":
		var v float64
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		return expect(name, v, 1.5)
	case "string":
		var v string
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		return expect(name, v, "世界")
	case "binary":
		var v []byte
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		return expect(name, string(v), "ab")
	case "list_str":
		var v []any
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		if len(v) != 2 || v[0] != "a" || v[1] != "b" {
			return "", fmt.Errorf("read %v, wanted [a b]", v)
		}
		return fmt.Sprint(v), nil
	case "int32_array":
		var v []int32
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		if len(v) != 3 || v[0] != 1 || v[1] != 2 || v[2] != 3 {
			return "", fmt.Errorf("read %v, wanted [1 2 3]", v)
		}
		return fmt.Sprint(v), nil
	case "decimal":
		var v fory.Decimal
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		want := fory.NewDecimal(big.NewInt(12345), 2)
		if !v.Equal(want) {
			return "", fmt.Errorf("read %s, wanted %s", v.String(), want.String())
		}
		return v.String(), nil
	case "timestamp":
		var v time.Time
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		want := time.Unix(1, 500_000_000).UTC()
		if !v.Equal(want) {
			return "", fmt.Errorf("read %s, wanted %s", v, want)
		}
		return v.UTC().Format(time.RFC3339Nano), nil
	case "duration":
		var v time.Duration
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		want := 90*time.Second + 500*time.Microsecond
		if v != want {
			return "", fmt.Errorf("read %s, wanted %s", v, want)
		}
		return v.String(), nil
	case "date":
		var v fory.Date
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		if v.Year != 1970 || v.Month != 1 || v.Day != 2 {
			return "", fmt.Errorf("read %+v, wanted 1970-01-02", v)
		}
		return fmt.Sprintf("%04d-%02d-%02d", v.Year, v.Month, v.Day), nil
	case "struct_point":
		var v *Point
		if err := f.Deserialize(bytes, &v); err != nil {
			return "", err
		}
		if v == nil || v.X != 1 || v.Y != 2 {
			return "", fmt.Errorf("read %v, wanted {1 2}", v)
		}
		return fmt.Sprintf("{%d %d}", v.X, v.Y), nil
	}
	return "", fmt.Errorf("no reader for this class")
}

// expect is the comparison every scalar case makes: the value, or the pair.
func expect[T comparable](name string, got, want T) (string, error) {
	if got != want {
		return "", fmt.Errorf("read %v, wanted %v", got, want)
	}
	return fmt.Sprintf("%v", got), nil
}
