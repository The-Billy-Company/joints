#!/usr/bin/env python3
"""Which instruments have a second parser in the question they ask.

The blind axis asks a page to quote a column of the oracle's. That demand is
only well formed when the instrument which produced the page's figures *has* an
oracle column, and some instruments structurally cannot: both arms of the
question they ask are ours. `shear.py` presses the same bytes with the same
grammar twice and reports the difference. `order.py` parses the same bytes and
the same nodes in two orders and reports the ratio. There is no second parser
anywhere in either question, so *which oracle* has no referent, and refusing
those pages asks their authors to prove something nobody claimed.

`onlydamage.FOREST` already carries one oracle-free exemption - a tree-identity
proof, which answers the same question more cheaply - and carries it as five
spellings. A list is the wrong shape for this second one. The exemption has to
hold for an instrument written next month by a lane that never opened this file,
and a list only holds for the instruments somebody has already met; the walls
classifier learned the same lesson when its separator *enumeration* failed on
`:=`. So nothing here is a name. Every fact is derived from the instrument's own
record declarations, read through `budge.declared`, which is already this tree's
reader for *what columns does this thing report*.

Four questions, in the order they narrow:

  produces  Does any record this module declares carry the column the page
            quoted? A field is read as `_`-separated segments, so
            `whole_rubble` produces `rubble` and `cut_standing` produces
            `standing`.
  oracle    Does any record it declares carry a column of the **oracle's**? If
            one does, the instrument can be asked, and a page quoting only our
            columns off it is blind in exactly the sense the axis means.
  reaches   Does it **import the module that runs the oracle**? Declaring an
            oracle column is not the whole of having a second parser: `bench.py`
            spells tree-sitter's milliseconds `dylib_ms` and `recover.py` spells
            its roots `their_roots`, so both look oracle-free to a vocabulary
            and both are oracle sweeps. What they cannot hide is the import: the
            oracle is a program, exactly one module in this tree spawns it, and
            an instrument with a second parser in it reaches that module or it
            has no way to run one. Direct imports only - `shear.py` imports
            `standing.py` for a span reader and `standing.py` imports `rack.py`,
            so a transitive closure makes every instrument on the tree an oracle
            sweep and exempts nothing.
  arms      Does any record carry one measurement **twice** - two fields
            differing in a single `_` segment and agreeing in every other? That
            is a self-comparison written down: `whole_rubble` beside
            `cut_rubble` is two readings of one column from two arms that are
            both ours.

All four have to hold together, and dropping any one is wrong in a direction
that matters. `oracle` alone would exempt every page naming any oracle-free
tool, including one that took a single reading of our own forest - which is the
population the axis exists for. `arms` alone would exempt `rack.py`, whose
`ours_nodes` sits beside `their_nodes` and which is the most sighted instrument
on the tree. `reaches` alone would exempt every tool in `tool/` that never opens
a socket. `produces` is what stops a page borrowing an exemption from an
instrument it merely mentions in passing.

**What it cannot see, and says so.** An instrument that reports through a bare
dict rather than a `NamedTuple` or a dataclass declares no columns, so nothing
here can read it; those modules are `mute`, and a page naming only mute
instruments is never exempted. That is the safe direction: the failure is a page
refused that could have been let through, never the reverse.

Usage:  instrument.py                every instrument, and what it can be asked
        instrument.py shear order    just these
        instrument.py --json
"""

from __future__ import annotations

import ast
import json
import re
import sys
from functools import lru_cache
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import budge  # noqa: E402  (needs ROOT/tool on the path first)

# The one module in this tree that spawns the oracle. It is named once, here,
# for the same reason `differential.py` itself names the binary once at `TS`:
# a tree has one oracle, something has to say which module holds it, and every
# other fact in this file is then derived. It is emphatically *not* a list of
# exempt instruments - it names the oracle, and an instrument written next month
# is classified by whether it imports this, which is a fact about that
# instrument and not about anybody's memory of it. If it ever stops existing,
# `DRIVEN` fails closed and nothing is exempted at all.
DRIVER = "differential"

# A module named the way a page names one: `shear.py`, or a record path like
# `shear.Cut.cut_rubble`. Both are how this record already cites an instrument,
# and neither is a list of instruments - the stem is looked up against what is
# on disk, so a tool added tomorrow is cited the same way and found the same way.
CITED = re.compile(r"\b([a-z][a-z0-9_]*)\.(?:py\b|(?=[A-Z]))")


class Kit(NamedTuple):
    """What one instrument can be asked for, read off its own declarations."""

    module: str
    files: tuple[str, ...]
    fields: frozenset[str]  # the field names it declares, exactly as declared
    columns: frozenset[str]  # those plus every `_` segment of each of them
    oracle: frozenset[str]  # those of them the oracle owns
    reaches: bool  # imports the module that spawns the oracle
    arms: tuple[tuple[str, tuple[str, ...]], ...]  # (column, the arms reporting it)

    @property
    def mute(self) -> bool:
        """Declares no record at all, so nothing here can read what it reports."""
        return not self.columns

    @property
    def selfsame(self) -> bool:
        """Reports one measurement twice, from two arms, and no second parser."""
        return bool(self.arms) and not self.oracle and not self.reaches


def segments(field: str) -> set[str]:
    """A field name as the columns it could be reporting.

    `set_` is `budge`'s one mechanical rename and it owns that rule, so the
    trailing underscore comes off through `budge.aliases` rather than here.
    """
    out: set[str] = set()
    for spelling in budge.aliases(field):
        parts = spelling.split("_")
        out.add(spelling)
        out |= {p for p in parts if p}
    return out


def paired(fields: tuple[str, ...]) -> dict[str, tuple[str, ...]]:
    """Fields differing in exactly one `_` segment, keyed by what stayed.

    Two arms of one measurement is the shape; `whole_roots` against `cut_roots`
    keeps `roots` and differs at position 0. Requiring the *rest* of the name to
    agree is what keeps this from pairing `cut_roots` with `whole_rubble`, which
    share a position and measure different things.
    """
    seen: dict[tuple[int, tuple[str, ...]], set[str]] = {}
    for field in fields:
        parts = field.rstrip("_").split("_")
        if len(parts) < 2:
            continue
        for i in range(len(parts)):
            rest = tuple(parts[:i] + parts[i + 1:])
            seen.setdefault((i, rest), set()).add(parts[i])
    out: dict[str, tuple[str, ...]] = {}
    for (_, rest), qualifiers in seen.items():
        if len(qualifiers) < 2:
            continue
        column = "_".join(rest)
        out.setdefault(column, ())
        out[column] = tuple(sorted(set(out[column]) | qualifiers))
    return out


@lru_cache(maxsize=1)
def index() -> dict[str, tuple[Path, ...]]:
    """Every module stem in the tree, and the files it could mean.

    A glob, not a parse: naming the population is cheap and parsing it is not,
    and a gate priced at the diff must only ever parse the handful a page cites.
    """
    out: dict[str, list[Path]] = {}
    for path in budge.modules():
        out.setdefault(path.stem, []).append(path)
    return {stem: tuple(paths) for stem, paths in out.items()}


def imports(source: str) -> set[str]:
    """Top-level module names this source imports, however it spells the import.

    `ast` rather than a regex on purpose: `import differential`,
    `from differential import ask`, and a deferred import inside a function all
    have to read the same, and only the first of the three is a line a pattern
    would obviously catch.
    """
    out: set[str] = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            out |= {alias.name.split(".")[0] for alias in node.names}
        elif isinstance(node, ast.ImportFrom) and node.module and not node.level:
            out.add(node.module.split(".")[0])
    return out


@lru_cache(maxsize=1)
def driven() -> bool:
    """Is the oracle's driver still on the tree? Fail closed if it is not."""
    return DRIVER in index()


@lru_cache(maxsize=None)
def kit(module: str, theirs: str) -> Kit | None:
    """One instrument's declarations, or None when no such module exists.

    Two files sharing a stem are read as one instrument and unioned, which is
    the conservative direction: an oracle column in either half makes the whole
    stem answerable, so an ambiguous citation never buys an exemption.
    """
    paths = index().get(module)
    if not paths:
        return None
    records, _ = budge.declared(paths)
    fields: set[str] = set()
    columns: set[str] = set()
    arms: dict[str, tuple[str, ...]] = {}
    for record in records:
        for field in record.fields:
            fields |= set(budge.aliases(field))
            columns |= segments(field)
        for column, qualifiers in paired(record.fields).items():
            arms[column] = qualifiers
    owns = re.compile(rf"^(?:{theirs})$", re.I)
    reaches = module == DRIVER or not driven() or any(
        DRIVER in imports(p.read_text(errors="replace")) for p in paths)
    return Kit(module=module,
               files=tuple(budge.stamp.here(p) for p in paths),
               fields=frozenset(fields),
               columns=frozenset(columns),
               oracle=frozenset(c for c in columns if owns.match(c)),
               reaches=reaches,
               arms=tuple(sorted((c, q) for c, q in arms.items())))


def cited(text: str, theirs: str) -> list[Kit]:
    """The instruments a page names, in the order the tree lists them."""
    want = {hit.group(1) for hit in CITED.finditer(text)}
    got = (kit(module, theirs) for module in sorted(want))
    return [k for k in got if k is not None]


class Verdict(NamedTuple):
    """Why a page's figures do or do not have an oracle behind them."""

    exempt: bool
    why: str
    kits: tuple[str, ...]


def judge(text: str, quoted: set[str], theirs: str) -> Verdict:
    """Is every column this page quoted from an instrument with one parser in it?

    `quoted` is the set of our columns the page put a number beside - the same
    reading the blind axis made to decide the page was blind in the first place.
    Asking about *those* columns rather than about the page in general is what
    keeps a passing mention of `shear.py` from clearing a board's `damage`.

    The question is asked **per column**, and that is not a detail. A page about
    `shear.py` that also names `standing.py` in a sentence is the common case,
    and judging the page by its most answerable instrument refuses it for a
    citation rather than for a figure. Judging each figure by the instruments
    that could have produced *it* refuses the right half: `rubble` off `shear`
    alone is exempt, and `damage` on the same page is not, because
    `standing.py` reports `damage` and `standing.py` can be asked.
    """
    kits = cited(text, theirs)
    if not kits:
        return Verdict(False, "names no instrument", ())
    names = tuple(k.module for k in kits)
    if not quoted:
        return Verdict(False, "quotes no column of ours", names)
    who = ""
    for column in sorted(quoted):
        # A field *named* the column is the column; a field that merely contains
        # it as a segment is a guess, and `stamp.py`'s `built_at` is exactly the
        # guess that would make the timestamp module a reporter of `built`. So
        # the exact declarations answer whenever any of them can, and the
        # segments are the fallback for the paired spellings - `cut_rubble` and
        # `whole_rubble` - which are the shape this file exists for.
        reporters = [k for k in kits if column in k.fields] or \
                    [k for k in kits if column in k.columns]
        if not reporters:
            return Verdict(False, f"nothing named here reports `{column}`", names)
        if asked := [k.module for k in reporters if not k.selfsame]:
            return Verdict(False, f"`{column}` is {asked[0]}'s too and "
                                  f"{asked[0]} can be asked an oracle", names)
        who = who or f"{reporters[0].module} reports `{column}` as " + " and ".join(
            f"`{q}`" for c, arms in reporters[0].arms if c == column
            for q in arms)
    return Verdict(True, f"{who or names[0]} - two arms, both ours", names)


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import onlydamage  # noqa: PLC0415  (the vocabulary's owner, not a copy of it)

    theirs = onlydamage.THEIRS
    want = [a for a in argv if not a.startswith("-")]
    kits = [k for k in (kit(m, theirs) for m in (want or sorted(index()))) if k]
    if "--json" in argv:
        json.dump([{**k._asdict(), "columns": sorted(k.columns),
                    "oracle": sorted(k.oracle), "selfsame": k.selfsame,
                    "mute": k.mute} for k in kits],
                  sys.stdout, indent=1)
        print()
        return 0
    same = [k for k in kits if k.selfsame]
    print(f"\n  {len(kits)} module(s) · {len(same)} ask a question with one "
          f"parser in it\n")
    print(f"  {'module':<16}{'cols':>5}{'oracle':>7}{'runs it':>9}  arms")
    for k in sorted(kits, key=lambda k: (not k.selfsame, k.module)):
        if k.mute:
            continue
        arms = " · ".join(f"{c}({'/'.join(q)})" for c, q in k.arms[:3]) or "—"
        print(f"  {k.module:<16}{len(k.columns):>5}{len(k.oracle):>7}"
              f"{'yes' if k.reaches else '·':>9}  {arms}")
    print(f"\n  {sum(1 for k in kits if k.mute)} declare no record and cannot be "
          f"read here; a page naming only those is never exempted.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
