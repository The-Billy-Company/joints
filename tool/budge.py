#!/usr/bin/env python3
"""Every field an instrument reports, and whether it has ever moved.

`still against` refuses a comparison whose evidence is byte-identical either
side of the treatment: an instrument that did not respond to your change cannot
clear it. That argument is not about whole boards. It is about *values*, and a
board is only the coarsest unit you can apply it to. A single column that reads
the same on every grammar, every run, every day of its life is vacuous evidence
by exactly the same reasoning - it did not respond to anything, so it has
cleared nothing, and twenty-five green rows around it say only that the rows
were green.

So: for every field every record in this tree declares, what values has it
actually taken? Two halves, because one of them is complete and the other is
not, and flattening them would hide which:

- **static** - every record, every field, every place in the source that can
  set it. Complete over the population, blind to values. It is the denominator.
- **dynamic** - every value each field has held in the JSON this tree has
  written. Honest about its reach, which is printed rather than implied.

A field with one value is three different findings and they are not
interchangeable:

| verdict | what was observed |
|---|---|
| `budged` | two or more distinct values. Alive |
| `flat`   | exactly one, and it is not empty. A constant |
| `void`   | every observation is empty - `{}`, `[]`, `""`, null. It has never held anything |
| `unseen` | declared, never observed. A hole in the sweep, printed as one |

and the sweep says *why* it did not move, which is the part that decides
whether it is a defect:

| why | what the source and the population say |
|---|---|
| `unwritten` | nothing in the tree sets it. Dead in the strongest sense |
| `sealed` | one writer and it is a literal. Constant by construction |
| `unasked` | its one value is a default its own CLI declares. Nobody passed the flag |
| `open` | the record moved - siblings took several values - and this did not |
| `thin` | the record never moved either. A corpus finding, not a field finding |

`void/open` is the shape of the bug this was built for: a witness's `oracles`
read `0 oracle(s)` on all 33 witnesses on disk while `binary`, `tree` and
`when` beside it moved constantly, because the lookup took the *stem* of
`grammar.json` and asked for a language called "grammar". `flat/thin` is the
opposite finding and it belongs to `absent.py` - the corpus never presented the
second value, and widening the corpus is the fix.

A field that is deliberately constant says so where it is declared:

    kind: str = "clean"   # budge: the only outcome this record is minted for

which is printed with its reason rather than silently forgiven.

Exit 0 clean, 1 findings, 2 could not run.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stamp  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]

# Where instruments in this tree put the JSON they write. Not an allowlist of
# suspects - the static half walks every module regardless, and a record no
# document under these roots ever carried is reported `unseen` rather than
# passed over.
SCOPES = (".local", "research")

# Where `--keep` files a board. Inside the default scopes on purpose: a sweep
# that checks whether fields vary is itself a field-reporting instrument, and
# pointed at a tree it has never written to it reports all nineteen of its own
# columns `unseen` - exempt from itself by never leaving a trace. Kept boards
# put its own record into its own population, so a column of its own that never
# moves comes back red under its own rule. The board is written AFTER the read,
# so no run ever reads its own output as evidence.
KEEP = Path(".local") / "budge"

# Reading every JSON this tree has written costs about a second, which is over
# the budget for anything that runs on a hook. Documents are taken in sorted
# order and the tail past the budget is reported rather than dropped quietly,
# so a short run and a full run disagree only in coverage, never in order.
BUDGET = 64 << 20

# A NamedTuple field spelled `set_` is written `set` when the record renders
# itself, because `set` is taken in Python and is not taken in JSON. Mechanical,
# and the only rename in the tree - anything else shows up as `unseen`.
def aliases(name: str) -> tuple[str, ...]:
    return (name, name[:-1]) if name.endswith("_") else (name,)


# --------------------------------------------------------------- the static half


class Writer(NamedTuple):
    """One place in the source that can decide a field's value.

    `site` is the construction it belongs to, not the line the argument sits
    on - a call spread over six lines writes six fields at six line numbers and
    they are all one decision. Grouping by it is what lets the sweep ask
    whether a writer ever *ran*: a site that also pins a sibling to a literal
    nobody has ever observed did not.
    """

    file: str
    line: int
    const: bool
    text: str
    site: str = ""
    # `text` is truncated for display and a truncated literal is not a literal.
    # A `note='everything before the first tree: for u` reads back as a syntax
    # error, so the value is taken off the node and kept beside the spelling
    # rather than recovered from it.
    value: Any = None


class Field(NamedTuple):
    owner: str
    name: str
    file: str
    line: int
    excuse: str
    writers: tuple[Writer, ...]

    @property
    def sealed(self) -> bool:
        """One value, handed over by literals only. It cannot take another."""
        return (bool(self.writers)
                and all(w.const for w in self.writers)
                and len({w.text for w in self.writers}) == 1)

    @property
    def where(self) -> str:
        return f"{self.file}:{self.line}"


class Record(NamedTuple):
    owner: str
    file: str
    fields: tuple[str, ...]
    required: frozenset[str]


def modules() -> list[Path]:
    out = sorted((ROOT / "tool").glob("*.py"))
    out += sorted(p for p in (ROOT / "research").rglob("*.py"))
    return out


def declared(paths: Iterable[Path]) -> tuple[list[Record], dict[str, Field]]:
    """Every record in the tree and every field it says it reports.

    A record is a NamedTuple or a dataclass: the two shapes this tree uses to
    say "these are my columns". Reading them out of the source rather than out
    of an observation is what makes the denominator complete - a field nobody
    has ever written still gets a row.
    """
    recs: list[Record] = []
    fields: dict[str, Field] = {}
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
            tree = ast.parse(text)
        except (OSError, SyntaxError):
            continue
        lines = text.splitlines()
        short = stamp.here(path)
        mod = path.stem
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            base = any("NamedTuple" in ast.unparse(b) for b in node.bases)
            data = any("dataclass" in ast.unparse(d) for d in node.decorator_list)
            if not (base or data):
                continue
            owner = f"{mod}.{node.name}"
            names: list[str] = []
            need: list[str] = []
            for stmt in node.body:
                if not (isinstance(stmt, ast.AnnAssign)
                        and isinstance(stmt.target, ast.Name)):
                    continue
                name = stmt.target.id
                if name.startswith("__"):
                    continue
                names.append(name)
                if stmt.value is None:
                    need.append(name)
                row = lines[stmt.lineno - 1] if stmt.lineno <= len(lines) else ""
                above = lines[stmt.lineno - 2] if stmt.lineno > 1 else ""
                fields[f"{owner}.{name}"] = Field(
                    owner=owner, name=name, file=short, line=stmt.lineno,
                    excuse=excuse(row) or excuse(above), writers=())
            if names:
                recs.append(Record(owner, short, tuple(names), frozenset(need)))
    return recs, fields


def excuse(line: str) -> str:
    """A declared reason for being constant, read off the declaration itself."""
    _, sep, rest = line.partition("# budge:")
    return rest.strip() if sep else ""


def defaults(paths: Iterable[Path]) -> dict[str, set[str]]:
    """Per module, the string values its own CLI hands over when nobody chooses.

    `amend.Row.grammar` reads `json` on all 168 rows anybody has ever taken,
    and every sibling column beside it - scale, bytes, cut, microseconds -
    moves constantly, so the population plainly responded and that one did not.
    It is still not a defect: `amend.py --grammar` *defaults* to json and no
    run has ever passed the flag. A field whose single value is one its own
    module declares as a default is a fact about how the instrument has been
    invoked, and the remedy is an invocation, not an edit.

    Strings only. `0`, `False` and `""` are the defaults of half the flags in
    this tree and matching on them would turn real findings amber by
    coincidence; a distinctive string will not.
    """
    out: dict[str, set[str]] = defaultdict(set)
    for path in paths:
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except (OSError, SyntaxError):
            continue
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Call)
                    and isinstance(node.func, ast.Attribute)
                    and node.func.attr == "add_argument"):
                continue
            for kw in node.keywords:
                if kw.arg == "default" and isinstance(kw.value, ast.Constant) \
                        and isinstance(kw.value.value, str) and kw.value.value:
                    out[path.stem].add(kw.value.value)
    return out


def writers(paths: Iterable[Path], recs: list[Record]) -> dict[str, list[Writer]]:
    """Every source expression that can end up in a field.

    Construction (positional and by keyword), `_replace`, and `**` splats -
    which are recorded as writers whose value is unknown, because a field whose
    only writer is a splat is not sealed and saying so would be a guess. Zero
    writers is the strongest static finding this half can make: the field is
    declared and nothing in the tree fills it.
    """
    # Twelve modules in this tree declare a record called `Row`. A bare
    # `Row(...)` therefore means whichever `Row` the file it sits in declares,
    # and a qualified `still.Witness(...)` means the one that module declares -
    # resolving both by bare name would charge every writer to one arbitrary
    # record and report the other eleven `unwritten`.
    shapes = {r.owner: r for r in recs}
    # `_replace` is called on a value, and a value's record is not always
    # knowable from the syntax. It is charged only where the field name belongs
    # to exactly one record in the tree; anywhere else it is left uncharged,
    # because inventing a writer would turn `unwritten` - the strongest thing
    # this half can say - into silence.
    sole: dict[str, str] = {}
    for r in recs:
        for f in r.fields:
            sole[f] = "" if f in sole else r.owner
    out: dict[str, list[Writer]] = defaultdict(list)
    for path in paths:
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except (OSError, SyntaxError):
            continue
        short = stamp.here(path)
        mine = path.stem
        # `row._replace(asked=…)` in `absent.py` can only mean `absent.Row`,
        # because that is the only record in that file with an `asked`. Three
        # other modules also declare an `asked`, so the tree-wide answer is
        # ambiguous and the module-local one is not.
        home: dict[str, str] = {}
        for r in recs:
            if r.owner.startswith(f"{mine}."):
                for f in r.fields:
                    home[f] = "" if f in home else r.owner
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            fn = node.func
            if isinstance(fn, ast.Attribute):
                owner = (f"{fn.value.id}.{fn.attr}"
                         if isinstance(fn.value, ast.Name) else "")
                bare = fn.attr
            elif isinstance(fn, ast.Name):
                owner, bare = f"{mine}.{fn.id}", fn.id
            else:
                continue
            here = f"{short}:{node.lineno}"
            if bare == "_replace":
                for kw in node.keywords:
                    if kw.arg and (home.get(kw.arg) or sole.get(kw.arg)):
                        one = home.get(kw.arg) or sole[kw.arg]
                        out[f"{one}.{kw.arg}"].append(seen(short, kw.value, here))
                continue
            rec = shapes.get(owner)
            if rec is None:
                continue
            # `Priced(k, w, *rest, bool(...))` - a splat in the middle means the
            # index of everything after it is unknowable, so positional mapping
            # stops there and the remainder is charged to an unknown writer.
            # Guessing would put the last argument on the wrong field, which is
            # the exact defect this sweep exists to catch.
            blind = next((i for i, a in enumerate(node.args)
                          if isinstance(a, ast.Starred)), len(node.args))
            for i, arg in enumerate(node.args[:blind]):
                if i < len(rec.fields):
                    out[f"{rec.owner}.{rec.fields[i]}"].append(seen(short, arg, here))
            if blind < len(node.args):
                for f in rec.fields[blind:]:
                    out[f"{rec.owner}.{f}"].append(
                        Writer(short, node.lineno, False, "*", here))
            for kw in node.keywords:
                if kw.arg is None:
                    for f in rec.fields:
                        out[f"{rec.owner}.{f}"].append(
                            Writer(short, kw.value.lineno, False, "**", here))
                elif kw.arg in rec.fields:
                    out[f"{rec.owner}.{kw.arg}"].append(seen(short, kw.value, here))
    return out


def seen(file: str, node: ast.expr, site: str = "") -> Writer:
    """One handover, and whether what it hands over could have been anything else.

    A literal is a literal; an empty container spelled inline is one too. A
    name, a call, an attribute or a comprehension is not, even when it happens
    to evaluate the same way every time - the sweep's job is to say what the
    syntax admits, and observation says the rest.
    """
    hollow = (isinstance(node, (ast.Tuple, ast.List, ast.Dict, ast.Set))
              and not getattr(node, "elts", None)
              and not getattr(node, "keys", None))
    const = isinstance(node, ast.Constant) or hollow
    value = node.value if isinstance(node, ast.Constant) else \
        ({} if isinstance(node, ast.Dict) else []) if hollow else None
    return Writer(file, node.lineno, const, ast.unparse(node)[:40], site, value)


# -------------------------------------------------------------- the dynamic half


def token(value: Any) -> tuple[str, str, bool]:
    """A value's identity, its short spelling, and whether it is empty.

    `0` and `false` are values; a field that is always false may be exactly
    right and is reported `flat`. `{}`, `[]`, `""` and null are the absence of
    one, and a field that has only ever held those is reported `void` - which
    is a different sentence and deserves a different word.
    """
    if value is None:
        return "\u2205", "null", True
    if isinstance(value, bool):
        return f"b{value}", str(value).lower(), False
    if isinstance(value, (int, float)):
        return f"n{value}", str(value), False
    if isinstance(value, str):
        if not value:
            return "\u2205s", '""', True
        if len(value) <= 24:
            return f"s{value}", value, False
        return "s#" + hashlib.blake2b(value.encode(), digest_size=8).hexdigest(), \
            value[:21] + "\u2026", False
    if isinstance(value, (list, dict)):
        mark = "[]" if isinstance(value, list) else "{}"
        if not value:
            return "\u2205" + mark, mark, True
        blob = json.dumps(value, sort_keys=True, default=str)
        return f"c{len(value)}#" + hashlib.blake2b(
            blob.encode(), digest_size=8).hexdigest(), \
            f"{mark[0]}{len(value)} item(s){mark[1]}", False
    return "?", str(type(value).__name__), False


class Tally:
    """What one field has been observed holding."""

    __slots__ = ("values", "empties", "seen", "silent", "docs")

    def __init__(self) -> None:
        self.values: dict[str, tuple[int, str]] = {}
        self.empties: set[str] = set()
        self.seen = 0
        self.silent = 0
        self.docs: set[str] = set()

    def note(self, value: Any, doc: str) -> None:
        key, show, empty = token(value)
        n, _ = self.values.get(key, (0, show))
        self.values[key] = (n + 1, show)
        if empty:
            self.empties.add(key)
        self.seen += 1
        self.docs.add(doc)

    @property
    def spread(self) -> str:
        if len(self.values) < 2:
            return ""
        least = min(n for n, _ in self.values.values())
        return f"{least}/{self.seen}"


def documents(scopes: Iterable[str], budget: int) -> tuple[list[Path], int, int, int]:
    """The population, in a fixed order, up to a byte budget.

    Smallest first, which is not a tie-break but the whole point of the budget.
    An instrument's board is a few kilobytes of records; the megabytes in this
    tree are span and leaf dumps carrying no record at all. Spending 16 MB on
    the smallest documents reads 1,400 of 2,500 of them and attributes 4,700
    objects; spending the same 16 MB in path order reads eight. Size is the
    best available proxy for record density and it costs a `stat`.

    Deterministic rather than newest-first, so two runs on the same tree read
    the same documents and a finding is reproducible without pinning a clock.
    What the budget left unread is returned, and printed.
    """
    found: list[tuple[int, Path]] = []
    for scope in scopes:
        root = ROOT / scope if not Path(scope).is_absolute() else Path(scope)
        for p in ([root] if root.is_file() else
                  sorted(root.rglob("*.json")) if root.is_dir() else []):
            try:
                found.append((p.stat().st_size, p)) if p.is_file() else None
            except OSError:
                continue
    whole = sum(size for size, _ in found)
    found.sort(key=lambda kv: (kv[0], str(kv[1])))
    took: list[Path] = []
    spent = 0
    for size, p in found:
        if budget and spent + size > budget:
            break
        took.append(p)
        spent += size
    return sorted(took), spent, whole, len(found)


def spot(recs: list[Record]) -> dict[str, list[Record]]:
    """Index records by their rarest field, so attribution is one lookup."""
    common: dict[str, int] = defaultdict(int)
    for r in recs:
        for f in r.required:
            common[f] += 1
    index: dict[str, list[Record]] = defaultdict(list)
    for r in recs:
        if not r.required:
            continue
        anchor = min(r.required, key=lambda f: (common[f], f))
        index[anchor].append(r)
    return index


def harvest(docs: list[Path], recs: list[Record], tallies: dict[str, Tally],
            whole: dict[str, int]) -> tuple[int, int, int]:
    """Walk every object in every document and attribute what can be attributed.

    An object belongs to a record when it carries all of that record's
    non-defaulted fields; where two records both fit, the one that fits more
    tightly wins and a genuine tie is counted as ambiguous rather than charged
    to either. Objects that match nothing - leaves, spans, config - are counted
    too, because "how much of what this tree writes does this sweep read" is
    the honest coverage statement and it has to be a number.

    Matching on the *required* fields only is deliberate and it is also the
    loosest thing this sweep does: a record with four non-defaulted columns
    will accept any object carrying those four, however many others it has and
    however many of the record's own it lacks. That tolerance is what lets a
    board written before a field existed still be read - and it is also how
    `walls.Priced`, seven columns of which four are required, came to be
    charged 501 stale `owners.Wall` boards it explains four keys of, and to
    report `roofed` a defect on the strength of them. So `whole` counts, per
    record, the objects that carried **every** declared column: an object that
    can only be that record's own rendering. A record with none of those has
    never demonstrably reached disk, and `judge` says so instead of reading
    somebody else's values as its own.
    """
    index = spot(recs)
    hit = miss = tied = 0
    for path in docs:
        doc = stamp.here(path)
        try:
            top = json.loads(path.read_bytes())
        except (OSError, ValueError):
            continue
        stack: list[Any] = [top]
        while stack:
            node = stack.pop()
            if isinstance(node, list):
                stack.extend(node)
                continue
            if not isinstance(node, dict):
                continue
            stack.extend(node.values())
            keys = node.keys()
            fits = [r for k in keys for r in index.get(k, ())
                    if r.required <= keys]
            if not fits:
                miss += 1
                continue
            best = max(len(r.required) for r in fits)
            fits = [r for r in fits if len(r.required) == best]
            if len(fits) > 1:
                tied += 1
                continue
            hit += 1
            rec = fits[0]
            gaps = 0
            for name in rec.fields:
                tally = tallies.setdefault(f"{rec.owner}.{name}", Tally())
                for spelling in aliases(name):
                    if spelling in node:
                        tally.note(node[spelling], doc)
                        break
                else:
                    gaps += 1
                    tally.silent += 1
                    tally.docs.add(doc)
            whole[rec.owner] = whole.get(rec.owner, 0) + (not gaps)
    return hit, miss, tied


# ------------------------------------------------------------------ the judgment


class Verdict(NamedTuple):
    """One field's row. Kept by `--keep`, and therefore swept like any other."""

    field: str
    at: str
    verdict: str
    why: str
    held: str
    observations: int
    documents: int
    silent: int
    writers: int
    excuse: str
    red: bool

    def line(self) -> str:
        return (f"{self.field:<38}{self.verdict:<8}{self.why:<11}"
                f"{self.observations:>5}{self.documents:>6}  {self.held[:30]}")


def judge(field: Field, tally: Tally, moved: set[str], unchosen: dict[str, set[str]],
          adrift: bool = False, dormant: bool = False) -> Verdict:
    """One field's verdict, and the reason it is or is not a defect.

    `open` is the whole point and it is the `vacuous` argument moved down a
    level: the record demonstrably responded - some sibling column took several
    values across these same observations - so the population is not the
    explanation for this one standing still.
    """
    values = tally.values
    if adrift:
        # Objects were charged to this record and not one of them carried all
        # of its columns, so none of them was its own rendering and none of
        # these values is its. Reporting the sweep's reach is the honest
        # answer; reporting a verdict off another record's values is the
        # failure this instrument is named for.
        return Verdict(field=f"{field.owner}.{field.name}", at=field.where,
                       verdict="unseen", why="adrift",
                       held=f"{tally.seen + tally.silent} foreign object(s)",
                       observations=0, documents=len(tally.docs), silent=0,
                       writers=len(field.writers), excuse=field.excuse, red=False)
    if len(values) >= 2:
        verdict, show = "budged", f"{len(values)} value(s), least {tally.spread}"
    elif values and set(values) <= tally.empties:
        verdict = "void"
        show = next(iter(values.values()))[1] + f" \u00d7{tally.seen}"
    elif values:
        verdict = "flat"
        show = next(iter(values.values()))[1] + f" \u00d7{tally.seen}"
    elif tally.silent:
        # The record reached disk and this column was not on it. That is a
        # different sentence from "the record was never written", and folding
        # the two would hide the one that is a finding inside the one that is
        # a hole in the sweep.
        verdict, show = "silent", f"{tally.silent} record(s), key absent"
    else:
        verdict, show = "unseen", "never observed"

    # Observation outranks syntax. `unwritten` and `sealed` are claims about
    # what the source admits; a field seen holding two values has falsified
    # both of them, and the contradiction is counted in the footer rather than
    # allowed to redden a field that demonstrably works.
    if verdict == "budged":
        why = "-"
    elif not field.writers:
        why = "unwritten"
    elif field.sealed:
        why = "sealed"
    elif verdict == "flat" and next(iter(values.values()))[1] in \
            unchosen.get(field.owner.split(".")[0], ()):
        why = "unasked"
    elif dormant:
        why = "unreached"
    elif field.owner in moved and len(tally.docs) > 1:
        why = "open"
    else:
        why = "thin"
    return Verdict(field=f"{field.owner}.{field.name}", at=field.where,
                   verdict=verdict, why=why, held=show, observations=tally.seen,
                   documents=len(tally.docs), silent=tally.silent,
                   writers=len(field.writers), excuse=field.excuse,
                   red=finding(verdict, why, field.excuse))


def finding(verdict: str, why: str, excuse: str) -> bool:
    """Is this row a finding, or a note?

    `unseen` never is: the sweep read no document carrying that record and has
    no opinion, which is a statement about this sweep's reach rather than about
    the field. `thin` never is either - it belongs to `absent.py`, and it is
    answered by widening the corpus rather than by editing anything.
    `unreached` never is: the writers that would move it have not run, the
    sweep names the observation that would show they had, and the excuse lapses
    by itself the moment that observation arrives.
    """
    if excuse or verdict == "unseen" or why == "unreached":
        return False
    return why == "unwritten" or (
        verdict in ("void", "flat", "silent") and why == "open")


def unreached(fields: dict[str, Field], tallies: dict[str, Tally]) -> set[str]:
    """Fields whose only value-bearing writers provably never ran.

    `field.Press.reason` is `""` on all 640 rows this tree has written, against
    four writers three of which build a real string, and that reads exactly
    like the defect this sweep was built for. It is not one. Each of those
    three sits in a `Press(...)` that also hands `outcome` a *literal* -
    `absent`, `refused`, `timeout` - and `outcome` is a column this same sweep
    has watched take four values across those 640 rows, none of them those
    three. So the sweep is not looking at a string that was built and lost; it
    is looking at three constructions that have never been executed, and it can
    say which observation would prove otherwise.

    That is the `unasked` argument one level in. `unasked` reads a default off
    an `add_argument` and says nobody passed the flag; this reads a literal off
    the construction beside the field and says nobody took the branch. Both are
    facts about how the instrument has been driven and neither is an edit.

    Three deliberate narrownesses, because an excuse that fires easily is worse
    than no excuse:

    - Every site that could have handed over **something other than the value
      observed** must be marked. The site spelling the observed value is the
      one that ran and it is not evidence of anything; a splat re-hydrating a
      record off its own JSON originates no value and is not either. One
      unmarked site that could have moved the column is a defect and stays one.
    - The discriminant must be a **string literal** whose sibling has been
      observed holding *something*. An unobserved sibling proves nothing, and
      matching `0` / `False` / `""` would turn real findings amber by
      coincidence - the same reason `defaults` takes strings only.
    - It is checked against the population, so it **dissolves the moment it
      stops being true**: the first row on disk carrying `outcome: "refused"`
      makes that literal observed, the excuse lapses, and if `reason` is still
      empty the row goes red on its own. It cannot be spent twice.

    It also cannot reach the bug this sweep exists for. `still.Witness.oracles`
    is minted at one site whose every argument is computed, so there is no
    literal to read and no excuse to find - which is the test `verify` runs.
    """
    out: set[str] = set()
    for key, field in fields.items():
        held = tallies.get(key)
        if not held or len(held.values) != 1:
            continue
        stood = next(iter(held.values))
        homes: dict[str, dict[str, Writer]] = defaultdict(dict)
        for name in (f for f in fields if f.startswith(f"{field.owner}.")):
            for w in fields[name].writers:
                if w.site:
                    homes[w.site][name.rsplit(".", 1)[1]] = w
        alive = [homes[w.site] for w in field.writers if w.site
                 and w.text not in ("*", "**")
                 and not (w.const and token(w.value)[0] == stood)]
        if not alive:
            continue
        if all(any(argued(field.owner, sib, w, tallies)
                   for sib, w in site.items() if sib != field.name)
               for site in alive):
            out.add(key)
    return out


def argued(owner: str, sibling: str, w: Writer, tallies: dict[str, Tally]) -> bool:
    """Does this sibling's literal name a case the population has never shown?"""
    if not (w.const and isinstance(w.value, str) and w.value):
        return False
    tally = tallies.get(f"{owner}.{sibling}")
    return bool(tally and tally.values) and token(w.value)[0] not in tally.values


def responded(recs: list[Record], tallies: dict[str, Tally]) -> set[str]:
    """Records that demonstrably moved: some field of theirs took two values."""
    out = set()
    for r in recs:
        for name in r.fields:
            t = tallies.get(f"{r.owner}.{name}")
            if t and len(t.values) >= 2:
                out.add(r.owner)
                break
    return out


class Board(NamedTuple):
    rows: list[Verdict]
    read: dict[str, Any]
    fields: dict[str, Field]
    tallies: dict[str, Tally]
    adrift: dict[str, int]


def source() -> tuple[list[Record], dict[str, Field], dict[str, set[str]]]:
    """The static half, parsed once.

    It is a pure function of the tree's source and every sweep in one process
    reads the same tree, so `verify` - which takes six of them - was paying six
    AST passes over 108 modules to reach the same answer. The gate is meant to
    be cheap enough to run on a hook, and an instrument that taxes the machine
    it is checking gets turned off.
    """
    global CACHED
    if CACHED is None:
        paths = modules()
        recs, fields = declared(paths)
        for key, ws in writers(paths, recs).items():
            if key in fields:
                fields[key] = fields[key]._replace(writers=tuple(ws))
        CACHED = (recs, fields, defaults(paths))
    return CACHED


CACHED: tuple[list[Record], dict[str, Field], dict[str, set[str]]] | None = None


def sweep(scopes: Iterable[str], budget: int, owner: str = "") -> Board:
    scopes = list(scopes)
    recs, fields, unchosen = source()
    docs, spent, size, found = documents(scopes, budget)
    tallies: dict[str, Tally] = {}
    entire: dict[str, int] = {}
    hit, miss, tied = harvest(docs, recs, tallies, entire)
    charged: dict[str, int] = defaultdict(int)
    for key, t in tallies.items():
        charged[key.rsplit(".", 1)[0]] += t.seen + t.silent
    adrift = {r.owner: charged[r.owner] for r in recs
              if charged.get(r.owner) and not entire.get(r.owner)}
    moved = responded(recs, tallies)
    dormant = unreached(fields, tallies)
    rows = [judge(f, tallies.get(k, Tally()), moved, unchosen,
                  f.owner in adrift, k in dormant)
            for k, f in sorted(fields.items())
            if not owner or owner in f.owner]
    read = {
        "records": len(recs), "fields": len(fields),
        "documents": len(docs), "found": found,
        "bytes": spent, "whole": size, "budget": budget,
        "scopes": sorted(str(s) for s in scopes),
        "attributed": hit, "unattributed": miss, "ambiguous": tied,
        "adrift": sum(adrift.values()),
    }
    return Board(rows, read, fields, tallies, adrift)


def keep(board: Board) -> Path:
    """File this board where the next run will read it, and only then.

    Written after the sweep has finished reading, so the run that writes a
    board never counts it - `still.sealed` exists because an instrument that
    writes into its own evidence is scoring its own homework, and a sweep about
    self-flattery earning that finding would be a poor joke.
    """
    where = ROOT / KEEP
    where.mkdir(parents=True, exist_ok=True)
    when = stamp.iso(time.time())
    out = where / f"{when.replace(':', '')}.json"
    out.write_text(json.dumps({"read": {**board.read, "when": when},
                               "row": [r._asdict() for r in board.rows]}))
    return out


def against(board: Board, prior: Path) -> int:
    """This sweep against a kept one - the part that is cheap enough to gate.

    Measured on this tree 2026-08-06, a budgeted sweep is **not** a subset of a
    full one. At 8 MB eleven fields read red that read green over all 250 MB -
    all six of `walls.Warm`'s among them - and five read green that read red,
    including `field.Press.reason`, the largest finding on the board. A partial
    population changes the verdict in both directions, so two boards taken over
    different populations cannot be differenced - which is `still against`'s
    rule about arms, arriving here for the same reason and refused the same
    way, at exit 4.
    """
    try:
        was = json.loads(prior.read_text())
    except (OSError, ValueError) as e:
        print(f"budge: cannot read {stamp.here(prior)} ({e})", file=sys.stderr)
        return 2
    old, new = was.get("read", {}), board.read
    for key in ("budget", "scopes"):
        if old.get(key) != new.get(key):
            how = (f"--budget {old.get('budget', 0) // (1 << 20)}" if key == "budget"
                   else " ".join(f"--scope {s}" for s in old.get("scopes", ())))
            print(f"budge: these two boards were taken over different"
                  f" populations ({key}: {old.get(key)!r} vs {new.get(key)!r}),"
                  f" so a field reading differently between them has not been"
                  f" shown to have changed - the population alone moves it."
                  f" Re-sweep the way the kept board was taken:"
                  f" python3 tool/budge.py {how} against",
                  file=sys.stderr)
            return 4
    before = {r["field"]: r for r in was.get("row", ())}
    worse = [r for r in board.rows
             if r.red and not before.get(r.field, {}).get("red", False)]
    better = [r for r in board.rows
              if not r.red and before.get(r.field, {}).get("red", False)]
    born = [r for r in board.rows if r.field not in before]
    print(f"budge: against {stamp.here(prior)} ({old.get('when', 'undated')})")
    for r in worse:
        was_row = before.get(r.field)
        print(f"  WORSE  {r.field} \u2192 {r.verdict}/{r.why}"
              + (f" (was {was_row['verdict']}/{was_row['why']})" if was_row
                 else " (new field, red on arrival)"))
    for r in better:
        print(f"  fixed  {r.field} \u2192 {r.verdict}/{r.why}")
    print(f"  {len(born)} field(s) declared since; {len(worse)} newly red,"
          f" {len(better)} no longer red")
    return 1 if worse else 0


# ---------------------------------------------------------------- the falsifiers


def grammars(where: Path, n: int) -> list[Path]:
    """Three grammar homes the falsifier owns, rather than three it borrows.

    The obvious source is `.local/differential/lang`, and it is the wrong one
    twice over. A gate that needs a corpus a sibling lane happened to lower is
    a gate that is red on a fresh clone for a reason that is not its own; and a
    falsifier reading nine other agents' scratch cannot say whether it held
    because the detector works or because of what was lying around. So it
    plants its own, in the temporary tree it deletes on the way out.

    The bytes only have to be *distinct* and reachable through the same path
    shape a real one has - `lang/<name>/src/grammar.json` - because what is
    under test is which of two rules recovers `<name>` from that path.
    `differential.named` reads the directory under `lang`, which these have,
    and the retired rule reads the file's stem, which is `grammar` here exactly
    as it is on the real corpus. That is the whole bug, reproduced without it.
    """
    out = []
    for i, name in enumerate(("alpha", "beta", "gamma")[:n]):
        home = where / "lang" / name / "src"
        home.mkdir(parents=True, exist_ok=True)
        seed = home / "grammar.json"
        seed.write_text(json.dumps({"name": name, "rules": {"source": {
            "type": "STRING", "value": f"{i}" * (i + 1)}}}))
        out.append(seed)
    return out


def restored(where: Path, retired: bool, seed, fed: list[Path]) -> Path:
    """Write one witness per grammar, with `oracles` filled by one of two rules.

    The shipped bug is still in the tree under its own name - `still.stems`,
    kept so the fix has something to be a fix *of* - so restoring it needs no
    vandalism of a tree nine other lanes are working in, and no edit to
    `still.py` that a sibling would have to merge around. Three witnesses,
    because two documents is the floor for `open`: one document cannot show
    that anything moved, and a falsifier that leans on a population too thin to
    reach its own verdict has proved nothing.
    """
    import still
    where.mkdir(parents=True, exist_ok=True)
    for i, path in enumerate(fed):
        stamp.FED.clear()
        stamp.FED[str(path)] = [stamp.Sight(str(path), f"{i:x}", 0, 0.0, 0.0, 0)]
        if retired:
            held = still.stems()
        else:
            court = still.seen_oracles()
            held = {r.name: r.tree for r in (court.rows if court else ()) if r.tree}
        it = seed._replace(arm=f"budge-{i}", when=1.0 + i, binary=f"{i:064x}",
                           oracles=held, artifacts={str(path): f"{i:x}"})
        (where / f"budge-{i}.json").write_text(json.dumps(it.as_dict()))
    stamp.FED.clear()
    return where


def presses(where: Path, arm: str) -> Path:
    """Three press rows, in one of three shapes, for the two newer rules.

    `field.Press` is the right subject for both because it is the record that
    taught them: nineteen columns of which two are required, so it accepts an
    object carrying almost none of itself, and a `reason` whose three
    real-string writers each pin `outcome` to a literal.

    - `whole` - three complete rows, outcomes `clean`/`residual`/`refusing`.
      `reason` is empty on all three and must read `unreached`, because no
      `absent`/`refused`/`timeout` row exists for it to describe.
    - `partial` - the same three cut down to the two required columns. Nothing
      carries all nineteen, so every column must read `unseen/adrift` rather
      than a verdict harvested off an object that is not a `Press`.
    - `reached` - `whole` plus a fourth row that *is* `refused` and still
      carries an empty `reason`. The literal `outcome` was standing on is now
      observed, the excuse lapses on its own, and the row must go red.
    """
    import field
    where.mkdir(parents=True, exist_ok=True)
    outcomes = ["clean", "residual", "refusing"] + (["refused"] * (arm == "reached"))
    # One document per row, because `open` needs two before it can be reached
    # at all - a falsifier leaning on a population too thin to carry its own
    # verdict proves nothing, which is the rule `restored` is written to too.
    # Every column but `name` and `outcome` is held equal across the rows, so
    # a field that moves between the arms moved for the reason under test.
    for i, out in enumerate(outcomes):
        row = field.Press(f"g{i}", out, "", bytes_=10, sha="a", terminals=3,
                          literal=2, regex=1, states=7, cells=9, ms=1.0)._asdict()
        if arm == "partial":
            row = {"name": row["name"], "outcome": row["outcome"]}
        (where / f"g{i}.json").write_text(json.dumps({"rows": [row]}))
    return where


def verify() -> int:
    """Break it and watch the right row go red - and only that row.

    Two arms over the same three witnesses, differing in one thing: which rule
    fills `oracles`. The shipped rule takes the stem of `grammar.json`, asks for
    a language called "grammar", and misses for every input there is. The
    current one reads the grammar out of the path. A sweep worth running turns
    `oracles` red under the first and green under the second, and reports the
    same verdict for every other field of the same record either way. A sweep
    that goes red everywhere when one field breaks is a sweep that gets passed
    with a flag by the second person who meets it.
    """
    import shutil
    import tempfile
    import still
    ok = True
    hold = Path(tempfile.mkdtemp(prefix="budge-"))
    try:
        fed = grammars(hold / "corpus", 3)
        seed = still.take("budge-seed")
        arms = (("retired", True, "void",
                 "the shipped rule (stem of grammar.json, so always 'grammar')"),
                ("current", False, "budged",
                 "the current rule (the grammar its path names)"))
        boards: dict[str, dict[str, Verdict]] = {}
        for slug, retired, want, label in arms:
            scope = restored(hold / slug, retired, seed, fed)
            board = sweep([str(scope)], 0, owner="still.Witness")
            boards[slug] = {r.field.rsplit(".", 1)[1]: r for r in board.rows}
            got = boards[slug]["oracles"]
            good = got.verdict == want
            ok &= good
            print(f"{'held' if good else 'MISSED':<7} {label}")
            print(f"        Witness.oracles reads {got.verdict}/{got.why}"
                  f" - {got.held}; wanted {want}."
                  f" {board.read['attributed']} witness object(s) attributed")
        broke, fixed = boards["retired"], boards["current"]
        moved = sorted(k for k in broke
                       if (broke[k].verdict, broke[k].why)
                       != (fixed[k].verdict, fixed[k].why))
        good = moved == ["oracles"]
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} restoring the bug moved"
              f" {len(moved)} of {len(broke)} field(s) of the same record:"
              f" {', '.join(moved) or 'none'}")
        print("        wanted exactly ['oracles']")

        empty = sweep([str(hold / "nothing")], 0, owner="still.Witness").rows
        good = all(r.verdict == "unseen" for r in empty) and bool(empty)
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} a scope with no documents reports"
              f" {sum(r.verdict == 'unseen' for r in empty)} of {len(empty)}"
              f" field(s) unseen, and no field budged")
        print("        an empty population must say it has no opinion, not that"
              " everything is fine")

        good = not any(r.red for r in empty)
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} and it fails nothing:"
              f" {sum(r.red for r in empty)} red")
        print("        a sweep that reddens on absence of evidence is noise, and"
              " noise gets a flag")

        presses(hold / "whole", "whole")
        board = sweep([str(hold / "whole")], 0, owner="field.Press")
        rows = {r.field.rsplit(".", 1)[1]: r for r in board.rows}
        got = rows["reason"]
        good = (got.verdict, got.why) == ("void", "unreached")
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} Press.reason over three rows none"
              f" of which failed reads {got.verdict}/{got.why}; wanted void/unreached")
        print("        every writer that builds a string also pins `outcome` to"
              " a literal no row holds")

        good = not got.red
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} and `unreached` is not a finding:"
              f" reason is {'RED' if got.red else 'green'}")
        print("        the other columns here are red on purpose - they are held"
              " equal across the three rows so\n        that the one field that"
              " moves between the arms moved for the reason under test")

        presses(hold / "partial", "partial")
        thin = sweep([str(hold / "partial")], 0, owner="field.Press")
        good = (all(r.verdict == "unseen" and r.why == "adrift" for r in thin.rows)
                and not any(r.red for r in thin.rows) and bool(thin.adrift))
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} objects carrying two of nineteen"
              f" columns leave {sum(r.why == 'adrift' for r in thin.rows)} of"
              f" {len(thin.rows)} field(s) unseen/adrift, {sum(r.red for r in thin.rows)}"
              f" red")
        print("        a record that never reached disk whole must not read a"
              " verdict off somebody else's object")

        presses(hold / "reached", "reached")
        back = sweep([str(hold / "reached")], 0, owner="field.Press")
        rows = {r.field.rsplit(".", 1)[1]: r for r in back.rows}
        got = rows["reason"]
        good = got.red and (got.verdict, got.why) == ("void", "open")
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} one `refused` row on disk and the"
              f" same empty `reason` reads {got.verdict}/{got.why},"
              f" {'red' if got.red else 'GREEN'}; wanted void/open, red")
        print("        the excuse is checked against the population, so it lapses"
              " the moment the population contradicts it")

        moved = sorted(k for k in rows
                       if (rows[k].verdict, rows[k].why)
                       != (board.rows and {r.field.rsplit('.', 1)[1]: (r.verdict, r.why)
                                           for r in board.rows}.get(k))
                       and k != "outcome")
        good = moved == ["reason"]
        ok &= good
        print(f"{'held' if good else 'MISSED':<7} and adding that row moved"
              f" {len(moved)} of {len(rows)} field(s) besides `outcome`:"
              f" {', '.join(moved) or 'none'}")
        print("        wanted exactly ['reason']")
    finally:
        shutil.rmtree(hold, ignore_errors=True)
    print(f"\nbudge: {'every falsifier held' if ok else 'a falsifier did not hold'}")
    return 0 if ok else 1


# ---------------------------------------------------------------------- the CLI


def report(board: Board, show: int) -> int:
    rows, read = board.rows, board.read
    reds = [r for r in rows if r.red]
    excused = [r for r in rows if r.excuse and r.verdict != "budged"]
    grid: dict[tuple[str, str], int] = defaultdict(int)
    for r in rows:
        grid[(r.verdict, r.why)] += 1

    print(f"static:  {read['records']} record(s), {read['fields']} declared"
          f" field(s). Complete over the tree, blind to values.")
    print(f"dynamic: {read['documents']} of {read['found']} document(s),"
          f" {read['bytes'] / 1e6:.0f} of {read['whole'] / 1e6:.0f} MB read."
          f" {read['attributed']} object(s) attributed,"
          f" {read['unattributed']} matched no record,"
          f" {read['ambiguous']} fit two equally.")
    if read["documents"] < read["found"]:
        print(f"         {read['found'] - read['documents']} document(s) past the"
              f" budget were not read. Raise it with --budget or pass 0 for all"
              f" of them.")

    print(f"\n{'field':<38}{'verdict':<8}{'why':<11}{'obs':>5}{'docs':>6}  what it held")
    print("-" * 100)
    for r in sorted(reds, key=lambda r: (r.why != "unwritten", r.verdict,
                                         -r.observations))[:show]:
        print(r.line())
    if len(reds) > show:
        print(f"... and {len(reds) - show} more. --show to see them.")
    if not reds:
        print("(none)")

    columns = (("unwritten", 10), ("sealed", 8), ("unasked", 9),
               ("unreached", 11), ("open", 7), ("thin", 7), ("adrift", 8), ("-", 7))
    print("\n" + f"{'verdict':<10}" + "".join(f"{w:>{n}}" for w, n in columns))
    for verdict in ("budged", "flat", "void", "silent", "unseen"):
        cells = "".join(f"{grid[(verdict, w)]:>{n}}" for w, n in columns)
        print(f"{verdict:<10}{cells}")
    lied = sum(1 for r in rows if r.verdict == "budged" and not r.writers)
    if lied:
        print(f"\n{lied} field(s) the static half called unwritten or sealed and"
              f" the dynamic half saw move.\nThe static half is a claim about"
              f" what the syntax admits; observation outranks it, and\nthose"
              f" rows are green. Each one is a writer shape the source reader"
              f" cannot follow.")

    if board.adrift:
        print("\ncharged objects, and never one of their own:")
        for owner, n in sorted(board.adrift.items(), key=lambda kv: -kv[1])[:show]:
            print(f"  {owner:<38} {n} object(s) fit its required columns and"
                  f" none carried them all")
        print("  Those values are somebody else's, so every column of these"
              " records reads `unseen/adrift`\n  rather than a verdict."
              " Objects on disk in a shape nothing in this tree declares are a"
              "\n  finding about the disk - usually a board written before a"
              " column existed.")

    if excused:
        print("\ndeclared constant, and why:")
        for r in excused[:show]:
            print(f"  {r.field:<38} {r.excuse[:56]}")

    print(f"\nbudge: {len(reds)} field(s) that should have moved and did not.")
    print("A red row is a field to LOOK at, not a field proven broken. `open`"
          " says the record\nmoved and this column did not, which is the shape"
          " of a misnamed field and also the\nshape of a corpus with one"
          " tree-sitter installed on it. What it is not is unexamined.")
    print("A `thin` row is a corpus finding, not a field finding - `absent.py`"
          " reports what the\ncorpus lacks and `specimen` exercises what it"
          " declares. Widening those moves `thin`\nrows without touching a line"
          " of the field they name.")
    print("An `unseen` row is a hole in THIS sweep: the record it belongs to was"
          " never written\nto disk under the scopes read, so the sweep has no"
          " opinion and says so.")
    return 1 if reds else 0


def one(board: Board, name: str) -> int:
    hits = [r for r in board.rows if name in r.field]
    if not hits:
        print(f"budge: no declared field matches {name!r}", file=sys.stderr)
        return 2
    for r in hits:
        field = board.fields[r.field]
        tally = board.tallies.get(r.field, Tally())
        print(f"\n{r.field}  declared at {r.at}")
        print(f"  {r.verdict}/{r.why} - {r.held}")
        if r.excuse:
            print(f"  declared constant: {r.excuse}")
        print(f"  {len(field.writers)} writer(s):")
        for w in field.writers[:8]:
            print(f"    {w.file}:{w.line:<5} {'literal' if w.const else 'computed'}"
                  f"  {w.text}")
        print(f"  {len(tally.values)} distinct value(s) over {tally.seen}"
              f" observation(s) in {len(tally.docs)} document(s)"
              + (f", {tally.silent} silent" if tally.silent else "") + ":")
        for _, (n, said) in sorted(tally.values.items(),
                                   key=lambda kv: -kv[1][0])[:8]:
            print(f"    {n:>5}\u00d7  {said[:60]}")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--scope", action="append", default=[],
                    help="a directory or file of JSON to read; repeatable."
                         f" Default {' '.join(SCOPES)}")
    ap.add_argument("--budget", type=int, default=BUDGET >> 20, metavar="MB",
                    help="stop reading documents past this many MB; 0 for all")
    ap.add_argument("--owner", default="", help="only fields of records matching this")
    ap.add_argument("--show", type=int, default=24)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--keep", action="store_true",
                    help=f"file this board under {KEEP}, so the next run sweeps"
                         f" this sweep's own fields alongside everyone else's")
    sub = ap.add_subparsers(dest="verb")
    s = sub.add_parser("show", help="one field: its writers, its values, its documents")
    s.add_argument("name")
    a = sub.add_parser("against", help="this sweep against a kept board - the ratchet")
    a.add_argument("prior", nargs="?", help=f"a kept board; newest under {KEEP}"
                                            f" when omitted")
    sub.add_parser("verify", help="the falsifiers, restored, against this sweep")
    got = ap.parse_args(argv)

    if got.verb == "verify":
        return verify()
    board = sweep(got.scope or list(SCOPES), got.budget << 20, got.owner)
    if got.verb == "show":
        return one(board, got.name)
    if got.verb == "against":
        kept = sorted((ROOT / KEEP).glob("*.json")) if (ROOT / KEEP).is_dir() else []
        prior = Path(got.prior) if got.prior else (kept[-1] if kept else None)
        if prior is None:
            print(f"budge: no kept board under {KEEP}; run `--keep` once first",
                  file=sys.stderr)
            return 2
        return against(board, prior)
    code = 1 if any(r.red for r in board.rows) else 0
    if got.json:
        json.dump({"read": board.read, "row": [r._asdict() for r in board.rows]},
                  sys.stdout, indent=1)
        print()
    else:
        code = report(board, got.show)
    if got.keep:
        print(f"budge: kept at {stamp.here(keep(board))}", file=sys.stderr)
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
