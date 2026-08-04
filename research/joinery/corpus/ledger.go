/*
The corpus program: a ledger that caches its own total.
push invalidates the cache, total rebuilds it and holds it until the
next push, and every file in this folder tells that same story.
*/
package main

import (
	"fmt"
	"os"
	"strconv"
)

// A raw string literal. Go spells it with backquotes, and a newline inside
// one is text rather than the end of anything.
const banner = `ledger receipt
--------------
`

type Ledger struct {
	rows  []int64
	tags  map[string]int
	total *int64
}

func NewLedger() *Ledger {
	return &Ledger{tags: make(map[string]int)}
}

func (l *Ledger) Push(tag string, v int64) int {
	at := len(l.rows)
	l.rows = append(l.rows, v)
	l.tags[tag] = at
	l.total = nil
	return at
}

func (l *Ledger) Total() int64 {
	if l.total != nil {
		return *l.total
	}
	var acc int64
	for _, r := range l.rows {
		if r > 0 {
			acc += r
		}
	}
	l.total = &acc
	return acc
}

func main() {
	l := NewLedger()
	for i, arg := range os.Args[1:] {
		v, err := strconv.ParseInt(arg, 10, 64)
		if err != nil {
			fmt.Fprintf(os.Stderr, "skipping %s: %v\n", arg, err)
			continue
		}
		l.Push(fmt.Sprintf("arg%d", i), v)
	}
	fmt.Print(banner)
	fmt.Printf("total=%d\n", l.Total())
}
