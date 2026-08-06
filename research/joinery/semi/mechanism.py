#!/usr/bin/env python3
"""Sort a grammar's external terminals by MECHANISM, derived from the grammar.

The question a lane has to answer before it can stand in for an external scanner
is not "what is this token called" - `outside.zig`'s header is one long argument
that the name is never evidence. It is **what does recognising these bytes
require**, and there are only three answers:

  spelled   the grammar itself states the bytes. A pattern at one offset
            answers it, so it is a `Provision` row and carries nothing.
  unspelled  the grammar never states the bytes and the token bounds nothing.
            No memory is required - but no spelling is available from the
            grammar either, so seating it means transcribing the scanner and
            citing it, which is what `caesura`, `scry` and `lineage` already
            are.
  span      the grammar never states the bytes AND the token is
            **co-derivable** with another unspelled external: the two can both
            be matched in one derivation of one rule, so they are the ends of a
            run rather than rival spellings of one position. Recognising one
            requires remembering the other - carried state. `fence` and
            `marrow` are this shape.

Both axes are read off `grammar.json`, so this runs offline over all thirty and
re-derives rather than remembering. The one thing it deliberately does **not**
claim is a token's *width*: nothing in `grammar.json` says whether a terminal
consumes bytes, and a zero-width terminal may only be answered by a hand (the
slate must refuse an empty match, since nothing in a regex promises the next
call differs). That fact comes from the scanner, and a row that needs it says so.

## Axis one - does the grammar state the bytes

**One** place it can, and the qualifier is load-bearing:

  ALIAS with `"named": false`
            `{"type":"ALIAS","value":"=","named":false,
              "content":{"SYMBOL":"_eq_custom"}}`
            The tree has to show the user a `=`, so the DSL carries the spelling
            even for a token it routes through C. An **anonymous** alias is a
            spelling; a **named** one is a node rename and says nothing about
            bytes. Ignoring `named` classified lua's `_block_string_content` and
            php's `encapsed_string_chars` as spelled, on the strength of both
            being aliased to the *node name* `string_content`. Two string
            interiors, reported as literal text.

A rule of the form `x = {ext | "lit"}` looks like a second source and is not
one. It fits `bang = {_bang_custom|"!"}`, where `!` really is the external's
spelling - and equally fits php's `_semicolon = {_automatic_semicolon|";"}`,
where the two alternatives are a zero-width break and a real semicolon and
emphatically not one token spelled twice. Nothing in the tree tells those apart,
so this file does not guess: it was tried, it named php's ASI `spelled`, and it
is gone. `_bang_custom` therefore lands in `unspelled`, which is the honest
answer - the grammar does not state its bytes, the scanner's `OPERATORS` table
does.

## Axis two - carried state, and where the derivation actually comes from

The memory axis is **not** derivable from `grammar.json`, and saying so is the
most useful thing in this file.

The signal that looks like it should work is *co-derivability*: two unspelled
externals that can both be matched while deriving one rule are the two ends of a
run, so recognising one requires remembering the other. Meeting across the
members of a SEQ means both are matched; meeting only under a CHOICE means one
excludes the other; REPEAT is transparent, which is the case that matters -

    raw_string_literal = SEQ( REPEAT(SEQ(raw_str_part, …, {cont|e})),
                              raw_str_end_part )

`raw_str_part` and `raw_str_end_part` are not siblings, but they meet at that
outer SEQ, so the signal calls all three one span, and for swift it is exactly
right. It is still not a verdict, because bash breaks it:

    heredoc_redirect = SEQ( optional(file_descriptor), …, heredoc_start, … )

`file_descriptor` meets `heredoc_start` in that SEQ and carries nothing at all -
it is `[0-9]+` plus "and the next byte is `>`", already seated in the roll as a
flat pattern. A sequence is not a span, and no shape in the tree separates "two
ends of one run" from "two unrelated tokens in a row". So this column is
reported as `span?` - a **candidate**, with its kin named so a reader can check
it - and never as the answer.

The answer comes from the scanner, which is where every hand in `outside.zig`
already gets it, and it is one line long: **`external_scanner_serialize`.** A
scanner that returns zero bytes carries nothing; what it does return *is* the
memory, and the functions that read it are the terminals that need it.

  swift   `struct ScannerState { uint32_t ongoing_raw_str_hash_count; }`,
          serialize returns 4. One integer, read only by `eat_raw_str_part`.
          **Exactly the three `raw_str_*` terminals carry.** The candidate
          column agrees here, which is why swift was safe to design against.
  kotlin  a `Stack` of string delimiters, serialize returns its size.
          `scan_automatic_semicolon(lexer, valid_symbols)` does not take the
          payload at all, so **the semicolon provably carries nothing** and only
          the string family does.

  python3 mechanism.py <grammar.json>...   the table
  python3 mechanism.py --json <g.json>...  machine output
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

# Wrappers that do not change what a node is, only how it is treated. Unwrapped
# on the way down so a spelling inside a TOKEN() is still found.
CLEAR = ("PREC", "PREC_LEFT", "PREC_RIGHT", "PREC_DYNAMIC", "FIELD", "TOKEN",
         "IMMEDIATE_TOKEN", "REPEAT", "REPEAT1")


def externals(g: dict) -> list[str]:
    """Named externals in declaration order. A STRING/PATTERN external has no
    symbol to stand in for, and the press drops it - scala declares six that
    way, which is why its `else` and `catch` are absent from this table and
    from its terminal set."""
    return [e["name"] for e in g.get("externals", []) if e.get("type") == "SYMBOL"]


def aliases(g: dict, ext: set[str]) -> dict[str, set[str]]:
    """Spellings the grammar states by wrapping the SYMBOL in an **anonymous**
    ALIAS. `named: true` is a node rename and carries no claim about bytes."""
    found: dict[str, set[str]] = defaultdict(set)

    def walk(n) -> None:
        if isinstance(n, list):
            for x in n:
                walk(x)
        elif isinstance(n, dict):
            if n.get("type") == "ALIAS" and n.get("named") is False:
                c = n.get("content")
                if isinstance(c, dict) and c.get("type") == "SYMBOL" and c.get("name") in ext:
                    if isinstance(n.get("value"), str) and n["value"]:
                        found[c["name"]].add(n["value"])
            for v in n.values():
                walk(v)

    walk(g["rules"])
    return found


def _peel(n):
    while isinstance(n, dict) and n.get("type") in CLEAR:
        n = n.get("content")
    return n


def company(g: dict, ext: set[str]) -> dict[str, set[str]]:
    """Every external that can be matched in the same derivation as each other
    one, within a single rule - the `span?` candidate signal.

    Computed by folding the externals under each node upward and joining them
    wherever two *different* SEQ members carry some. A CHOICE joins nothing,
    which is the mutual exclusion that makes a rival spelling not a span. A
    REPEAT is transparent, because a repeat of a SEQ still derives every part.

    A candidate, not a verdict: bash's `heredoc_redirect` puts `file_descriptor`
    in sequence with `heredoc_start` and the first carries nothing."""
    kin: dict[str, set[str]] = defaultdict(set)

    def under(n) -> set[str]:
        """Externals reachable in this rule without entering another rule. A
        SYMBOL leaf stops the walk: another rule's parts are not this rule's."""
        if isinstance(n, list):
            got: set[str] = set()
            for x in n:
                got |= under(x)
            return got
        if not isinstance(n, dict):
            return set()
        t = n.get("type")
        if t == "SYMBOL":
            return {n["name"]} if n["name"] in ext else set()
        if t == "SEQ":
            got: set[str] = set()
            for m in n.get("members", []):
                # Everything gathered from earlier members is derivable
                # alongside everything in this one.
                p = under(m)
                for a in p:
                    kin[a] |= got
                for a in got:
                    kin[a] |= p
                got |= p
            return got
        got = set()
        for v in n.values():
            got |= under(v)
        return got

    for rule in g["rules"].values():
        under(rule)
    for a in list(kin):
        kin[a].discard(a)
    return kin


def classify(path: Path) -> dict:
    g = json.loads(path.read_text())
    order = externals(g)
    ext = set(order)
    alias = aliases(g, ext)
    seq = company(g, ext)

    # Who the grammar spells, resolved whole first: the candidate column asks
    # "co-derivable with an UNSPELLED external", which quantifies over this.
    spell = {n: " ".join(sorted(alias[n])) if alias.get(n) else "" for n in order}

    rows = []
    for name in order:
        bytes_ = spell[name]
        kin = sorted(k for k in seq.get(name, ()) if not spell[k])
        if bytes_:
            mech, seat = "spelled", "Provision row"
            why = "the grammar states its bytes in an anonymous ALIAS"
        elif kin:
            mech, seat = "span?", "hand + memory?"
            why = "co-derivable with unspelled external(s): " + " ".join(kin)
        else:
            mech, seat = "unspelled", "hand, no memory"
            why = "no spelling, and excludes every unspelled kin - a position, not a run"
        rows.append({
            "name": name, "mechanism": mech, "bytes": bytes_,
            "span_kin": kin, "why": why, "seat": seat,
        })
    return {"grammar": path.stem, "externals": len(order), "row": rows}


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    out = [classify(Path(a)) for a in args]
    if "--json" in sys.argv:
        print(json.dumps(out, indent=1))
        return 0
    for d in out:
        tally: dict[str, int] = defaultdict(int)
        for r in d["row"]:
            tally[r["mechanism"]] += 1
        print(f"\n===== {d['grammar']}: {d['externals']} named externals   "
              + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())))
        for r in d["row"]:
            b = f"  = {r['bytes']}" if r["bytes"] else ""
            print(f"  {r['name']:<38} {r['mechanism']:<9} {r['seat']:<15}{b}")
            if r["span_kin"]:
                print(f"      candidate span with: {' '.join(r['span_kin'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
