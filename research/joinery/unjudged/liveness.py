#!/usr/bin/env python3
"""Can each of `rack`'s columns take more than one value on the population it is read over?

A field that only ever reads one number is not a field, and nothing on this
board says which of them are. The corpus makes that worse in one specific way
the `unjudged` lane measured: **tree-sitter's own tree carries an `ERROR`
subtree on two rows out of thirty.** Every column whose value is decided by an
error - `unjudged`, `mute`, and the walk's whole first branch - is therefore
read over a population that almost never contains the thing it prices, and a
column can look alive because two rows move while its actual arm is dead.

So the population is manufactured rather than found. `rederive.brood` already
does it - one truncation, then six seeded excisions and six hostile insertions
per grammar, 13 mutants over 30 grammars - and it is a pure
`bytes -> list[(tag, bytes)]`, so pointing it at a second instrument costs a
temp file and a `plumb.Case`. That is the whole claim being tested here: the
generator is cheap to re-aim, and re-aiming it is the difference between a
field that is alive and a field that is merely unfalsified.

    python3 research/joinery/unjudged/liveness.py            both populations
    python3 research/joinery/unjudged/liveness.py --corpus   just the corpus
    python3 research/joinery/unjudged/liveness.py go zig     two grammars

Read the `values` column, not the totals: `1` means every row on that
population agreed, and a tripwire asserting anything about that column is
asserting it against a constant.
"""
from __future__ import annotations

import argparse
import pathlib
import sys
from typing import NamedTuple

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import plumb  # noqa: E402
import rack  # noqa: E402
from rederive import brood  # noqa: E402

# Every integer column `rack.Seen` reports, plus the derived ones a report
# quotes. Read off the record rather than listed, because a column added
# tomorrow is exactly the column nobody will think to add here.
DERIVED = ("crooked", "unbuilt", "judged", "blind", "damage", "honest", "text")


def columns() -> tuple[str, ...]:
    got = rack.blank("x", 1, 1, "")
    return tuple([k for k, v in got._asdict().items() if isinstance(v, int)] + list(DERIVED))


def over(cases: list[tuple[str, plumb.Case]]) -> list[rack.Seen]:
    out = []
    for tag, case in cases:
        got = rack.measure(case, top=1)
        if got is not None:
            out.append(got._replace(name=tag))
    return out


def corpus_cases(names: set[str]) -> list[tuple[str, plumb.Case]]:
    return [(c.name, c) for c in plumb.slate() if not names or c.name in names]


def mutant_cases(names: set[str], seed: int, pen: pathlib.Path) \
        -> list[tuple[str, plumb.Case]]:
    """One file per mutant, so a row can be re-read after the fact.

    Written under a directory of this script's own rather than `rederive`'s
    `.local/rederive`: that one is a scratch pad another lane overwrites per
    grammar, and a population two instruments are reading at once is a
    population neither of them has.
    """
    pen.mkdir(parents=True, exist_ok=True)
    out = []
    for c in plumb.slate():
        if names and c.name not in names:
            continue
        for tag, blob in brood(c.source.read_bytes(), seed):
            src = pen / f"{c.name}-{tag.replace('@', '-')}{c.source.suffix}"
            src.write_bytes(blob)
            out.append((f"{c.name}/{tag}", plumb.Case(c.name, c.grammar, c.lang, src)))
    return out


class Look(NamedTuple):
    """One population, read two ways, because they disagree about what is alive.

    `values` is the bar a sweep usually sets - can the column take more than one
    number - and it is a weak one. `firing` is how many ROWS the column is
    non-zero on, and it is the bar that matters: `unjudged` clears `values` on
    this corpus with three distinct numbers and fires on **two rows of thirty**,
    both of them tree-sitter's own `ERROR` subtrees. A column standing on two
    rows is a column whose next defect is found by a dossier, not by a gate.
    """

    rows: int
    values: dict[str, set[int]]
    firing: dict[str, int]


def tell(rows: list[rack.Seen], label: str) -> Look:
    seen: dict[str, set[int]] = {c: set() for c in columns()}
    hot = dict.fromkeys(seen, 0)
    for r in rows:
        for c in seen:
            seen[c].add(getattr(r, c))
            hot[c] += getattr(r, c) != 0
    live = sum(len(v) > 1 for v in seen.values())
    print(f"\n{label}: {len(rows)} row(s) · {live} of {len(seen)} column(s) take more"
          f" than one value")
    return Look(len(rows), seen, hot)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])
    ap.add_argument("names", nargs="*")
    ap.add_argument("--seed", type=int, default=20260805)
    ap.add_argument("--corpus", action="store_true", help="skip the manufactured population")
    ap.add_argument("--pen", default="")
    got = ap.parse_args(argv)
    names = set(got.names)
    if bad := names - {c.name for c in plumb.slate()}:
        print(f"liveness.py: no such grammar: {', '.join(sorted(bad))}", file=sys.stderr)
        return 2
    pen = pathlib.Path(got.pen) if got.pen else ROOT / ".local" / "unjudged-liveness"

    book = {"corpus": tell(over(corpus_cases(names)), "THE CORPUS AS SHIPPED")}
    if not got.corpus:
        made = mutant_cases(names, got.seed, pen)
        book["mutants"] = tell(over(made), f"MANUFACTURED — `rederive.brood`, seed {got.seed}")

    wide = max(len(c) for c in columns())
    head = "".join(f"{k[:8]:>10}{'values':>11}{'firing':>13}" for k in book)
    print(f"\n{'column':<{wide}}{head}   verdict")
    print("-" * (wide + 34 * len(book) + 14))
    dead: list[str] = []
    thin: list[str] = []
    for c in columns():
        cells, alive = "", []
        for look in book.values():
            n, hot = len(look.values[c]), look.firing[c]
            alive.append(n > 1)
            cells += f"{n:>10}{('values' if n > 1 else 'ONE VALUE'):>11}{hot:>8}/{look.rows:<4}"
        both = " on both" if len(book) > 1 else ""
        say = (f"alive{both}" if all(alive) else
               "DEAD ON THE CORPUS, alive once errors exist" if alive[-1] and not alive[0] else
               f"dead{both} — nothing here can move it" if not any(alive) else
               "alive on the corpus only")
        if not alive[0]:
            dead.append(c)
        elif book["corpus"].firing[c] <= max(3, book["corpus"].rows // 10):
            thin.append(c)
            say += f" — but standing on {book['corpus'].firing[c]} corpus row(s)"
        print(f"{c:<{wide}}{cells}   {say}")
    if len(book) > 1:
        woke = [c for c in dead if len(book["mutants"].values[c]) > 1]
        print(f"\n{len(dead)} column(s) take a single value over the corpus as shipped:"
              f" {', '.join(dead) or 'none'}."
              f"\n{len(woke)} of them move the moment the population contains a syntax error:"
              f" {', '.join(woke) or 'none'}.")
        # The weaker bar is the one a sweep sets, so the stronger one is printed
        # beside it. A column clearing `values` on three rows out of thirty is
        # not a column anybody has evidence about.
        if thin:
            print(f"\n{len(thin)} more clear the 'more than one value' bar on THREE OR FEWER"
                  f" corpus rows:")
            for c in thin:
                a, b = book["corpus"].firing[c], book["mutants"].firing[c]
                print(f"  {c:<{wide}} {a} of {book['corpus'].rows} corpus row(s)"
                      f" → {b} of {book['mutants'].rows} mutants"
                      f"  ({b / max(a, 1):.0f}× the evidence)")
        print("\nA sweep that proves 'every reported field can take more than one value' will"
              "\nclear every column above against a population that barely exercises it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
