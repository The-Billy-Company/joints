#!/usr/bin/env python3
"""What does the corpus not contain? Nothing in this tree could answer that.

A correctness fix landed for Swift's `multiline_comment`. Before it, `/* c\\n d
*/` read as a `custom_operator` over a multiplicative expression - a comment
parsed as arithmetic, one root, zero mends - and **every instrument here scored
it a clean success**. After it, one `multiline_comment`. The board moved zero
bytes. `rack`'s swift row moved zero bytes. `Chunked.swift` contains no `/*`.

The corpus was silent, not the metric. Every measurement this repository takes
is bounded above by what thirty found files happen to hold, and until this file
existed nobody could say what that bound was. `specimen.py coverage` asks the
question one layer in - *which declared externals does anything reach* - and it
is the right question about **externals**, of which there are 461 and of which
this instrument can witness 38. A grammar spells **5,284** literal terminals.

So this is the inverse of the coverage gate, and it is deliberately not a
parser measurement at all.

## It is the coverage gate's complement, not its rival

The two populations do not overlap and neither knows the other exists. **456 of
the 461 declared externals have no rule body in `grammar.json`** - their
spelling lives in a hand-written C scanner, which is the whole reason they are
externals - so this reader is structurally blind to them and says so per row.
`specimen.py coverage` owns that half and can witness 38 of the 461. This owns
the other 5,284 spellings, which that gate never looks at. Read one without the
other and you have a number for a fifteenth of the terminal vocabulary.

## Absent spelling - the finest reading, and the one the Swift case needs

Harvest every `STRING` and `PATTERN` leaf out of `grammar.json`. Ask of the
**bytes** whether each occurs in that grammar's corpus file: a substring test
for a string, a regex search for a pattern.

Swift lands here and not one level up. `multiline_comment` is an external with
no body, so no rule of its own can be judged - but `[\\/]+[*]+` **is** spelled,
by `custom_operator`, which is exactly the token that ate the comment, and that
spelling is absent from `Chunked.swift`. The absence is visible at the spelling
and invisible at the rule, which is why both are reported.

## Impossible rule - the propagation, and a proof rather than a heuristic

Push presence upward through the grammar's own combinators - `SEQ` needs all of
its members, `CHOICE` needs one, `REPEAT` needs nothing because zero is a
repetition - and a named rule whose body cannot be satisfied by the literals
present is **impossible**: no byte of the corpus can be that construct, whatever
any parser says about it.

That is a claim about the *corpus*, and it holds where nothing else does. The
oracle has no verdict on 34,687 built bytes because tree-sitter itself ERRORs
there; this needs no parser, no folio and no oracle, so it is the only reading
available exactly where parsing is hardest.

**A `SYMBOL` is treated as satisfiable and never descended into.** A rule
referring to another rule is that rule's business, and following the reference
would make the answer depend on cycle handling rather than on the corpus. It
costs reach - a construct absent only because a *referenced* rule is absent is
reported possible - and the cost is entirely in the safe direction: this
**under**-reports absence and can never invent it.

Two more ways to be wrong, both in the same direction, both named per row:

  a pattern Python's `re` will not compile - 54 of the 5,284 - is `unreadable`
  and treated as present, so a rule that hangs off one is never called
  impossible on the strength of a regex nobody parsed;

  a literal is *bytes*, not a construct. `/*` inside a string literal reads as
  present. So `present` is a ceiling and `impossible` is a floor: this will
  never say the corpus lacks something it holds, and will sometimes say it
  holds something it only mentions.

The second of those was an admission for as long as this file existed, sitting
under the numerator of every `present` it printed. It is now **measured**, by
`oracle`, and the size of it is the reason: **288 of the 1,261 judgeable
present spellings - 22.8% - are never tokenised by tree-sitter at all**, and
253 of those occur only ever inside some other token. `ledger.go` is the case
small enough to check by eye: it holds two `!` bytes and both are the head of a
`!=`, so the byte reading says the corpus contains `!` and the corpus does not.

## Present as a token - what `oracle` adds, and what it cannot answer

The node reading asks whether the oracle's lexer ever emitted a leaf that IS
the spelling, whole. It brackets the byte reading rather than replacing it, in
the opposite direction: the byte reading over-counts presence, so `impossible`
is a floor; the node reading under-counts it, so `unreachable` is a ceiling.

Two exclusions keep the ceiling honest, and both matter more than they sound.
A literal the grammar only ever spells inside a `token(...)` can never be a
leaf of its own - go's `//` lives inside `token(seq('//', /.*/))`, so a file
full of comments still yields no `//` token. Asking the tree about it is asking
a question the grammar already answered, so those spellings are **sealed** and
sit outside both numbers; `present = sealed + asked` closes by construction.
And the ceiling's remaining error is countable from the same tree - a rule it
calls unreachable that the oracle *built* - so it is counted rather than
argued: 6 of 1,094 corpus-wide.

That is deliberately the shape the byte reading's own error does not have. A
rule the oracle did not build may still be possible, so nothing here can size
the floor's error, and this file says so instead of picking a number.

## Oracle-silent - the second reading, where there is one

A named rule the **oracle's** parse of the corpus yields no node for. Read from
tree-sitter rather than from outliner on purpose: outliner misreading a
construct would otherwise present as the corpus lacking it, which is the exact
confusion this file exists to end. It needs an oracle, so it is missing on the
grammars the lexical half matters most for, and the two are printed side by
side rather than merged.

The two disagreeing is a defect in **this file**: a rule the oracle built a node
for cannot be lexically impossible, and `verify` asserts that against every
grammar it can reach rather than arguing it.

## And what the specimen tier closes

Every impossible rule the corpus cannot present is a construct nothing here
grades. `research/joinery/specimen/` is the population built to present them,
so the last column is the one that turns this from an inventory into a target:
of the constructs the corpus cannot reach, how many does an authored file now
reach.

    python3 tool/absent.py run                 every grammar, lexical only (~2s)
    python3 tool/absent.py run swift           one grammar
    python3 tool/absent.py show swift          the impossible rules, named
    python3 tool/absent.py oracle swift        present as a TOKEN, and the overcount
    python3 tool/absent.py oracle --oracle=frame   ...from a frozen oracle pin
    python3 tool/absent.py aim                 the widest untested constructs, ranked
    python3 tool/absent.py verify              prove this can say no

Exit 0 measured, 1 a clean negative, 2 could not run. `--json` on the read
verbs.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import attest  # noqa: E402
import plumb  # noqa: E402 - the path has to be set first
import specimen  # noqa: E402
import stamp  # noqa: E402

ROOT = plumb.ROOT
GRAMMARS = plumb.GRAMMARS

# A literal that matches the empty string is satisfied by every file ever
# written, so asking whether the corpus contains it is not a question. Held
# apart from `unreadable` because the two are different admissions: one is a
# regex this reader could not parse, the other is a regex that parsed fine and
# says nothing.
VACUOUS = "matches the empty string"
UNREADABLE = "python's re will not compile it"


class Lit(NamedTuple):
    """One spelling a grammar declares, and what the corpus said about it."""

    kind: str  # STRING · PATTERN
    text: str

    def hunt(self, blob: bytes, text: str) -> tuple[bool, str]:
        """(present, why-unjudgeable). Unjudgeable counts as present."""
        if self.kind == "STRING":
            if not self.text:
                return (True, VACUOUS)
            return (self.text.encode() in blob, "")
        try:
            rx = re.compile(self.text)
        except (re.error, RecursionError):
            return (True, UNREADABLE)
        if rx.match(""):
            return (True, VACUOUS)
        return (bool(rx.search(text)), "")


class Said(NamedTuple):
    """A spelling the file only ever MENTIONS, and the token that swallowed it."""

    kind: str
    text: str
    host: str  # the oracle leaf every occurrence sits inside


class Rule(NamedTuple):
    """One named production, and whether the corpus could possibly hold it."""

    name: str
    spelled: frozenset[Lit]  # the literals its own body spells
    possible: bool  # can its body be satisfied by what the corpus contains
    external: bool


class Row(NamedTuple):
    grammar: str
    source: str
    rules: tuple[Rule, ...]
    lits: int  # distinct literals this grammar spells
    seen: int  # ...of which the corpus contains
    vacuous: int
    unreadable: int
    gone: tuple[Lit, ...]  # the spellings the corpus does not contain
    closed: tuple[str, ...]  # impossible rules a specimen now presents
    reached: tuple[Lit, ...]  # absent spellings a specimen now presents
    unspelled: int  # externals with no body here: the coverage gate's half
    silent: tuple[str, ...] = ()  # oracle built no node (empty unless asked)
    oracled: bool = False
    why: str = ""
    # The node reading. Empty unless an oracle was asked; see `witness`.
    asked: int = 0  # of `seen`, the ones the node reading can judge at all
    ghost: tuple[Lit, ...] = ()  # in the bytes, never a token: the byte reading's overcount
    mention: tuple[Said, ...] = ()  # ...of those, the ones only ever INSIDE another token
    unreachable: tuple[str, ...] = ()  # impossible under the node reading: the ceiling
    overreach: tuple[str, ...] = ()  # ...of those, ones the oracle BUILT: the ceiling's error

    @property
    def judgeable(self) -> int:
        return self.lits - self.vacuous - self.unreadable

    @property
    def sealed(self) -> int:
        """Present in the bytes and spelled only inside a `token(...)`.

        Derived so `present = sealed + asked` closes by construction: a count
        kept beside it would be over the whole vocabulary and would not.
        """
        return self.seen - self.asked

    @property
    def nodal(self) -> int:
        """Spellings the oracle actually tokenised, of the `asked` it could judge."""
        return self.asked - len(self.ghost)

    @property
    def impossible(self) -> tuple[str, ...]:
        return tuple(r.name for r in self.rules if not r.possible)

    @property
    def scored(self) -> tuple[Rule, ...]:
        """Rules this can say anything about: the ones that spell something.

        A rule whose body is pure `SYMBOL` reference has no literal of its own,
        so the lexical reading has no opinion on it and it is out of every
        denominator here. Folding it in as `possible` would inflate the
        coverage of a grammar this file cannot see, which is the shape of
        failure the coverage gate was built to refuse.
        """
        return tuple(r for r in self.rules if r.spelled)

    @property
    def share(self) -> float:
        return self.seen / self.judgeable if self.judgeable else 0.0

    def as_dict(self) -> dict:
        return {"grammar": self.grammar, "source": self.source,
                "literals": self.lits, "present": self.seen,
                "judgeable": self.judgeable, "vacuous": self.vacuous,
                "unreadable": self.unreadable, "share": round(self.share, 4),
                "unspelled_externals": self.unspelled,
                "absent_spelling": [[l.kind, l.text] for l in self.gone],
                "reached_by_specimen": [[l.kind, l.text] for l in self.reached],
                "scored_rules": len(self.scored), "impossible": list(self.impossible),
                "closed_by_specimen": list(self.closed),
                "oracle_silent": list(self.silent), "oracled": self.oracled,
                "sealed_in_token": self.sealed, "node_judgeable": self.asked,
                "present_as_node": self.nodal,
                "bytes_only": [[l.kind, l.text] for l in self.ghost],
                "mention_only": [list(m) for m in self.mention],
                "unreachable": list(self.unreachable),
                "ceiling_overreach": list(self.overreach),
                "why": self.why}


# ------------------------------------------------------------------- the walk

def spells(node, out: set[Lit]) -> None:
    """Every literal this body spells directly, not descending into a SYMBOL."""
    if isinstance(node, dict):
        kind = node.get("type")
        if kind in ("STRING", "PATTERN"):
            out.add(Lit(kind, node.get("value", "")))
            return
        if kind == "SYMBOL":
            return
        for key, val in node.items():
            if key != "type":
                spells(val, out)
    elif isinstance(node, list):
        for v in node:
            spells(v, out)


def satisfiable(node, have: set[Lit]) -> bool:
    """Could this body match, given only the literals the corpus contains?

    The grammar's own combinators, read literally. `REPEAT` is the one worth
    stating: zero is a repetition, so a body of nothing but a `REPEAT` is
    always satisfiable and a rule is never called impossible for lacking an
    optional part. Every combinator this reader does not know is satisfiable,
    which keeps an unfamiliar grammar shape out of the finding column.
    """
    if isinstance(node, list):
        return all(satisfiable(n, have) for n in node)
    if not isinstance(node, dict):
        return True
    match node.get("type"):
        case "STRING" | "PATTERN":
            return Lit(node["type"], node.get("value", "")) in have
        case "SEQ":
            return all(satisfiable(m, have) for m in node.get("members", ()))
        case "CHOICE":
            return any(satisfiable(m, have) for m in node.get("members", ()))
        case "REPEAT" | "BLANK" | "SYMBOL":
            return True
        case "REPEAT1":
            return satisfiable(node.get("content"), have)
        case _:
            return satisfiable(node["content"], have) if "content" in node else True


def blob_of(paths: list[Path]) -> tuple[bytes, str]:
    raw = b"".join(p.read_bytes() for p in paths)
    return raw, raw.decode("utf-8", "replace")


def read(name: str, source: Path, extra: list[Path]) -> Row:
    """One grammar's rules, judged against the bytes of one corpus file.

    `extra` is the specimen population, judged as a **second, separate** pass
    rather than concatenated in. The corpus number has to stay the corpus
    number: this whole file exists because a measurement quietly widened its
    own input once already.
    """
    doc = json.loads((GRAMMARS / f"{name}.json").read_text())
    rules = doc.get("rules", {})
    ext = {e["name"] for e in doc.get("externals", ()) if e.get("name")}

    every: set[Lit] = set()
    body: dict[str, set[Lit]] = {}
    for rule, node in rules.items():
        got: set[Lit] = set()
        spells(node, got)
        body[rule] = got
        every |= got

    raw, text = blob_of([source])
    have, vacuous, unreadable = set(), 0, 0
    for lit in every:
        here, why = lit.hunt(raw, text)
        vacuous += why == VACUOUS
        unreadable += why == UNREADABLE
        if here:
            have.add(lit)
    gone = tuple(sorted(every - have))

    made = tuple(Rule(r, frozenset(body[r]), satisfiable(n, have), r in ext)
                 for r, n in rules.items())
    dead = {r.name for r in made if not r.possible}

    closed: tuple[str, ...] = ()
    reached: tuple[Lit, ...] = ()
    if extra and (dead or gone):
        s_raw, s_text = blob_of(extra)
        s_have = {lit for lit in every if lit.hunt(s_raw, s_text)[0]}
        reached = tuple(l for l in gone if l in s_have)
        closed = tuple(sorted(r for r in dead if satisfiable(rules[r], s_have)))

    return Row(name, source.name, made, len(every), len(have), vacuous,
               unreadable, gone, closed, reached,
               sum(1 for e in ext if e not in rules))


def slate(want: set[str]) -> list[plumb.Case]:
    cases = [c for c in plumb.slate() if not want or c.name in want]
    return [c for c in cases if c.source.exists()
            and (GRAMMARS / f"{c.name}.json").exists()]


def sweep(want: set[str]) -> list[Row]:
    return [read(c.name, c.source, specimen.specimens_for(c.name))
            for c in slate(want)]


# ----------------------------------------------------------------- the oracle

def seal(node, out: set[Lit], shut: bool) -> None:
    """The literals this body spells from INSIDE a `token(...)` wrapper."""
    if isinstance(node, list):
        for n in node:
            seal(n, out, shut)
        return
    if not isinstance(node, dict):
        return
    kind = node.get("type")
    if kind in ("STRING", "PATTERN"):
        if shut:
            out.add(Lit(kind, node.get("value", "")))
    elif kind != "SYMBOL":
        for key, val in node.items():
            if key != "type":
                seal(val, out, shut or kind in ("TOKEN", "IMMEDIATE_TOKEN"))


def aliased(node, out: set[str]) -> set[str]:
    """Every node name an `ALIAS` in this grammar can put on the tree.

    The oracle built a `toml` node called `escape_sequence` whose text is a
    backslash-newline, which the rule of that name cannot spell - because a
    *different* rule is aliased to the name. A name that any alias can produce
    is therefore not evidence about the rule that owns it, and the cross-check
    below has to say so instead of reporting a defect that is not one.
    """
    if isinstance(node, list):
        for n in node:
            aliased(n, out)
    elif isinstance(node, dict):
        if node.get("type") == "ALIAS" and node.get("named") and node.get("value"):
            out.add(node["value"])
        for key, val in node.items():
            if key != "type":
                aliased(val, out)
    return out


def wrapped(doc: dict) -> set[Lit]:
    """The literals this grammar can only ever spell inside a single token.

    `token(seq('//', /.*/))` makes the whole comment one leaf, so `//` is not a
    token of its own however many comments the file holds - and asking the tree
    whether the lexer produced one is asking a question the grammar already
    answered no to. Held apart so the node reading can say "I am blind here"
    rather than count it an absence, which is the author of `hunt`'s defect
    with the sign flipped.

    Sealed in EVERY rule that spells it, not in one: a literal free anywhere
    can appear as a leaf, so one free spelling makes it judgeable again.
    """
    shut: set[Lit] = set()
    free: set[Lit] = set()
    for body in doc.get("rules", {}).values():
        every: set[Lit] = set()
        under: set[Lit] = set()
        spells(body, every)
        seal(body, under, False)
        shut |= under
        free |= every - under
    return shut - free


def spoken(lit: Lit, toks: frozenset[str]) -> bool:
    """Did the lexer produce a token that IS this spelling?

    The whole text of a leaf, never a substring of one. A leaf is what the
    oracle's lexer decided the bytes are, so `//` inside `// see http://x` is
    one `comment` token and no `//` token - which is the case this reading
    exists for and the one the author of `hunt` wrote down and did not close.
    Unreadable and vacuous patterns count present here for the same reason they
    do there: an admission is not a finding.
    """
    if lit.kind == "STRING":
        return not lit.text or lit.text in toks
    try:
        rx = re.compile(lit.text)
    except (re.error, RecursionError):
        return True
    return bool(rx.match("")) or any(rx.fullmatch(t) for t in toks)


def witness(case: plumb.Case, row: Row) -> Row:
    """Both oracle readings of one grammar: which rules it built, and which
    spellings it actually tokenised.

    The oracle and not outliner, because outliner misreading a construct would
    otherwise present as the corpus lacking it - which is the confusion this
    whole file is here to end.

    ## Present as bytes is not present

    `hunt` asks whether a spelling's bytes occur anywhere in the file, and its
    own docstring admits what that costs: "`/*` inside a string literal reads
    as present". That admission is load-bearing in the wrong direction - it is
    the numerator of every `present` figure this file prints, and the thing
    every `impossible` is computed against. So it is measured rather than
    admitted: **`ghost`** is a spelling whose bytes are in the file and which
    the lexer never once produced a token for, and **`mention`** is the sharp
    subset where every occurrence sits strictly inside some other token.

    The two readings bracket the truth and neither is the truth:

      the byte reading over-counts presence, so its `impossible` is a FLOOR -
      it cannot invent an absence and will sometimes miss one;

      the node reading under-counts presence, because a literal folded into a
      `token(...)` or an external scanner is never a token of its own however
      often the construct occurs - so `unreachable` is a CEILING.

    Reporting one of them as the answer would be the same silence this file was
    written to end, one level in. They are printed side by side, and the gap
    between them is the number nobody could quote before.
    """
    try:
        blob = case.source.read_bytes()
        nodes = plumb.oracle(case, blob)
    except (OSError, ValueError, RuntimeError) as bad:
        return row._replace(why=str(bad)[:60])
    # NAMED nodes only. An anonymous token carries its own text as its name, so
    # typescript's `'string'` keyword read as the oracle having built the rule
    # `string` - and this file's own tripwire has been printing that as a defect
    # in itself, correctly, on a corpus-wide run nobody took.
    built = {n.name for n in nodes if n.named}
    named = [r.name for r in row.rules if not r.name.startswith("_")]

    text = blob.decode("utf-8", "replace")
    toks = frozenset(blob[n.start:n.end].decode("utf-8", "replace")
                     for n in nodes if n.leaf and n.end > n.start)
    doc = json.loads((GRAMMARS / f"{row.grammar}.json").read_text())
    # Sealed literals are outside every number below. The tree cannot answer
    # for them, and counting a question nobody can ask as an absence is the
    # move this whole file exists to refuse.
    shut = wrapped(doc)
    here = {l for r in row.rules for l in r.spelled} - set(row.gone) - shut
    spelt = {l for l in here if spoken(l, toks)} | shut
    ghost = tuple(sorted(here - spelt))
    # Where the bytes actually landed. `paint` gives the deepest node over a
    # byte; if that is a leaf that PROPERLY contains the occurrence, the file
    # mentions the spelling inside something else rather than spelling it.
    deep = plumb.paint(nodes, len(blob))
    mention = tuple(Said(l.kind, l.text, host)
                    for l in ghost if (host := inside(l, blob, text, nodes, deep)))

    roof = tuple(sorted(r for r, n in doc.get("rules", {}).items()
                        if not satisfiable(n, spelt)))
    # The ceiling's error, measured rather than argued. A rule the oracle built
    # a node for is in the file, so calling it unreachable is this reading
    # over-reaching - and unlike the floor's error, which nothing here can see,
    # this one is countable from the same tree.
    return row._replace(silent=tuple(sorted(n for n in named if n not in built)),
                        oracled=True, asked=len(here),
                        ghost=ghost, mention=mention, unreachable=roof,
                        overreach=tuple(r for r in roof if r in built))


def inside(lit: Lit, blob: bytes, text: str, nodes: list[plumb.Node],
           deep: list[int]) -> str:
    """The token every occurrence of this spelling sits strictly inside, or "".

    EVERY occurrence, not one: a spelling that appears once inside a comment
    and once as a token of its own is spelled by the file, and calling it a
    mention on the strength of the first occurrence would be the same
    over-claim in the other direction. A spelling with no occurrence at all is
    not a mention - there is nothing to have been mentioned. The name is
    returned rather than a flag so the finding carries what swallowed it.
    """
    spots: list[tuple[int, int]] = []
    if lit.kind == "STRING":
        want, at = lit.text.encode(), blob.find(lit.text.encode())
        while at >= 0 and len(spots) < 64:
            spots.append((at, at + len(want)))
            at = blob.find(want, at + 1)
    else:
        try:
            rx = re.compile(lit.text)
        except (re.error, RecursionError):
            return ""
        # Byte offsets, and the file may not be ASCII: measure the prefix.
        spots = [(len(text[:m.start()].encode()), len(text[:m.end()].encode()))
                 for m in list(rx.finditer(text))[:64] if m.end() > m.start()]
    if not spots:
        return ""
    host = ""
    for lo, hi in spots:
        at = deep[lo] if lo < len(deep) else -1
        node = nodes[at] if at >= 0 else None
        if not (node and node.leaf and node.start <= lo and node.end >= hi
                and (node.start, node.end) != (lo, hi)):
            return ""
        host = host or node.label()
    return host


# ------------------------------------------------------------------- the verbs

def run(rows: list[Row], as_json: bool, mark: stamp.Stamp) -> int:
    if as_json:
        print(json.dumps({"stamp": mark.as_dict(),
                          "row": [r.as_dict() for r in rows]}, indent=2))
        return 0
    print("\nWHAT THE CORPUS DOES NOT CONTAIN — read from the bytes, with no parser\n")
    print(f"{'grammar':<19}{'source':<24}{'spelled':>8}{'ABSENT':>8}{'reach':>7}"
          f"{'rules':>7}{'IMPOSSIBLE':>11}{'closed':>8}{'ext':>6}  unreadable/vacuous")
    print("-" * 124)
    for r in sorted(rows, key=lambda r: -len(r.gone)):
        note = f"{r.unreadable}/{r.vacuous}" if (r.unreadable or r.vacuous) else "—"
        print(f"{r.grammar:<19}{r.source[:23]:<24}{r.lits:>8}{len(r.gone):>8}"
              f"{r.share * 100:>6.0f}%{len(r.scored):>7}{len(r.impossible):>11}"
              f"{len(r.closed):>8}{r.unspelled:>6}  {note}")

    lits = sum(r.judgeable for r in rows)
    seen = sum(r.seen for r in rows)
    scored = sum(len(r.scored) for r in rows)
    dead = sum(len(r.impossible) for r in rows)
    shut = sum(len(r.closed) for r in rows)
    got = sum(len(r.reached) for r in rows)
    ext = sum(r.unspelled for r in rows)
    mute = [r for r in rows if not r.scored]
    print(f"\n  {len(rows)} grammar(s) · {lits} judgeable spelling(s) · {seen} present"
          f" ({seen / lits:.1%}) · {lits - seen} ABSENT from the corpus")
    print(f"  {dead} of {scored} rules that spell something of their own CANNOT occur in"
          f" the corpus at all ({dead / scored:.1%}).")
    print(f"  the specimen tier reaches {got} of the {lits - seen} absent spelling(s) and"
          f" closes {shut} of the {dead} impossible rule(s).")
    print(f"\n  {ext} declared external(s) have NO body in grammar.json — their spelling is"
          f" in a C\n  scanner and this reader cannot see any of them. That population is"
          f" `specimen.py\n  coverage`'s, which witnesses 38 of 461. Neither number covers"
          f" the other's half.")
    print(f"  {sum(r.unreadable for r in rows)} pattern(s) this reader could not compile"
          f" and {sum(r.vacuous for r in rows)} that match the empty string are counted"
          f"\n  PRESENT, so ABSENT is a floor: it cannot invent an absence, only miss one.")
    print("\n  and `present` above is a CEILING, because it is a search for bytes: a"
          " spelling that\n  occurs only inside a comment or a string counts. `absent.py"
          " oracle` asks the second\n  question — whether the lexer ever produced that token"
          " — and prints the gap. Quote\n  this column without that one and you are quoting"
          " mentions as constructs.")
    if mute:
        print(f"\n  {len(mute)} grammar(s) spell no literal this can judge and are outside"
              f" every number above:\n    " + ", ".join(r.grammar for r in mute)
              + "\n  Their rules are externals, so the lexical reading has nothing to"
                " read. Say so rather\n  than counting them clean.")
    print(mark.line())
    return 0


def show(rows: list[Row], as_json: bool) -> int:
    if as_json:
        print(json.dumps([r.as_dict() for r in rows], indent=2))
        return 0
    for r in rows:
        dead = [x for x in r.rules if not x.possible]
        got = set(r.reached)
        print(f"\n# {r.grammar}  {r.source}")
        if r.why:
            print(f"  {r.why}")
        print(f"\n  {len(r.gone)} spelling(s) the corpus does not contain"
              f" — the finest reading, and the level the Swift case is visible at")
        for lit in sorted(r.gone, key=lambda l: (l.kind, l.text))[:80]:
            print(f"    {lit.kind:<8}{lit.text!r:<44}"
                  f"{'  ← a specimen presents it' if lit in got else ''}")
        if len(r.gone) > 80:
            print(f"    … and {len(r.gone) - 80} more")
        print(f"\n  {len(dead)} rule(s) the corpus cannot hold at all")
        for x in sorted(dead, key=lambda x: (x.name.startswith("_"), x.name)):
            miss = sorted(l.text for l in x.spelled)[:6]
            tag = "external " if x.external else ""
            note = "  ← a specimen presents it" if x.name in r.closed else ""
            print(f"    {tag}{x.name:<32}{' · '.join(repr(m) for m in miss)[:56]}{note}")
        if r.unspelled:
            print(f"\n  {r.unspelled} external(s) have no body here and are invisible to"
                  f" this reading entirely.")
    return 0


def oracle(rows: list[Row], want: set[str], as_json: bool, pin: str = "") -> int:
    """Both readings side by side, and the disagreement between them."""
    by = {c.name: c for c in attest.consult(slate(want), pin)}
    got = [witness(by[r.grammar], r) for r in rows if r.grammar in by]
    if as_json:
        print(json.dumps({"oracle": attest.SEATED.as_dict() if attest.SEATED else None,
                          "row": [r.as_dict() for r in got]}, indent=2))
        return 0
    print("\nPRESENT AS BYTES vs PRESENT AS A TOKEN — and the two readings of `impossible`\n")
    print(f"{'grammar':<19}{'present':>8}{'sealed':>7}{'asked':>7}{'token':>7}"
          f"{'BYTES ONLY':>11}{'mention':>8}{'floor':>7}{'CEILING':>8}"
          f"  what the oracle could not say")
    print("-" * 114)
    for r in got:
        cell = (f"{r.sealed:>7}{r.asked:>7}{r.nodal:>7}{len(r.ghost):>11}{len(r.mention):>8}"
                f"{len(r.impossible):>7}{len(r.unreachable) - len(r.overreach):>8}"
                if r.oracled else
                f"{'—':>7}{'—':>7}{'—':>7}{'—':>11}{'—':>8}{len(r.impossible):>7}{'—':>8}")
        print(f"{r.grammar:<19}{r.seen:>8}{cell}  {r.why[:30]}")
    live = [r for r in got if r.oracled]
    if live:
        seen = sum(r.seen for r in live)
        shut = sum(r.sealed for r in live)
        ask = sum(r.asked for r in live)
        ghost = sum(len(r.ghost) for r in live)
        said = sum(len(r.mention) for r in live)
        floor = sum(len(r.impossible) for r in live)
        roof = sum(len(r.unreachable) for r in live)
        worst = max(live, key=lambda r: len(r.ghost) / (r.asked or 1))
        print(f"\n  of the {seen} spelling(s) the byte reading calls PRESENT over"
              f" {len(live)} grammar(s), {shut}\n  are spelled only inside a `token(...)`"
              f" and no tree can answer for them. Of the {ask}\n  that remain,"
              f" **{ghost} are never tokenised by the oracle at all**"
              f" ({ghost / ask:.1%}) — that is\n  the byte reading's overcount, and it is"
              f" the number `present` was quietly carrying.")
        print(f"\n  {said} of the {ghost} occur only ever INSIDE another token: the file"
              f" mentions them,\n  it does not spell them. Widest share is"
              f" {worst.grammar} at {len(worst.ghost)} of {worst.asked}"
              f" ({len(worst.ghost) / (worst.asked or 1):.0%}).")
        over = sum(len(r.overreach) for r in live)
        print(f"\n  so `impossible` is a range and not a number: {floor} rule(s) under the byte"
              f"\n  reading, {roof} under the node reading. The first cannot invent an absence"
              f" and\n  misses some; the second cannot miss one and invents some, because a"
              f" literal folded\n  into a `token(...)` or a C scanner is never a token of its"
              f" own however often the\n  construct occurs.")
        print(f"\n  and the ceiling's error is countable from the same tree: {over} of its"
              f" {roof} rule(s)\n  are rules the oracle BUILT a node for, so"
              f" {roof - over} is the most this reading can\n  honestly claim. The floor's error"
              f" is not countable by any means here — a rule the\n  oracle did not build may"
              f" still be possible. The answer is between {floor} and {roof - over},\n  and this"
              f" file will not pick one.")
        shown = [(r.grammar, m) for r in live for m in r.mention]
        if shown:
            print("\n  what a mention looks like — the spelling, and the one token every"
                  " occurrence\n  of it sits inside:\n")
            for g, m in sorted(shown, key=lambda s: (s[0], s[1].text))[:14]:
                print(f"    {g:<14}{m.kind:<8}{m.text!r:<26}inside {m.host}")
            if len(shown) > 14:
                print(f"    … and {len(shown) - 14} more")
        # A name any ALIAS can produce is not evidence about the rule that owns
        # it: the oracle's toml `escape_sequence` is a backslash-newline, which
        # the rule of that name cannot spell, because another rule wears it.
        wrong = [(r.grammar, sorted(set(r.impossible) - set(r.silent)
                                    - aliased(json.loads(
                                        (GRAMMARS / f"{r.grammar}.json").read_text()), set())
                                    - {n for n in r.impossible if n.startswith("_")}))
                 for r in live]
        broke = [(g, n) for g, n in wrong if n]
        print(f"\n  {len(live)} grammar(s) had an oracle. A named rule the oracle BUILT"
              f" cannot be lexically\n  impossible, so any name below is a defect in"
              f" tool/absent.py and not a finding:")
        for g, names in broke:
            print(f"    {g}: {' '.join(names[:8])}")
        if not broke:
            print("    none — the two readings never contradict each other")
    print(attest.told())
    return 0


def aim(rows: list[Row], as_json: bool) -> int:
    """The constructs nothing in this tree grades, ranked by how many spell them.

    Ranked by the grammar's own weight rather than by a list kept here: a rule
    referred to by many other rules is load-bearing in that language, and the
    reference count is a fact in the file rather than an opinion about which
    languages matter.
    """
    out = []
    for r in rows:
        doc = json.loads((GRAMMARS / f"{r.grammar}.json").read_text())
        pull: dict[str, int] = {}
        for node in doc.get("rules", {}).values():
            for hit in re.finditer(r'"type":\s*"SYMBOL",\s*"name":\s*"([^"]+)"',
                                   json.dumps(node)):
                pull[hit[1]] = pull.get(hit[1], 0) + 1
        for name in r.impossible:
            if name not in r.closed:
                out.append((pull.get(name, 0), r.grammar, name))
    out.sort(key=lambda t: (-t[0], t[1], t[2]))
    if as_json:
        print(json.dumps([{"pull": p, "grammar": g, "rule": n} for p, g, n in out],
                         indent=2))
        return 0
    print("\nUNTESTED CONSTRUCTS — the corpus cannot present them and no specimen does\n")
    print(f"{'pull':>5}  {'grammar':<19}rule")
    print("-" * 62)
    for pull, g, name in out[:60]:
        print(f"{pull:>5}  {g:<19}{name}")
    print(f"\n  {len(out)} construct(s). `pull` is how many places the grammar itself"
          f" refers to the rule,\n  read out of the grammar rather than judged here — a"
          f" rule nothing refers to is a\n  top-level form, so a low pull is not a low"
          f" stake.")
    return 0


# ------------------------------------------------------------------- tripwire

def verify() -> int:
    """Prove this can say no, on answers known without it.

    The first two are the calibration: the one absence in this tree whose
    consequence is already known has to come back, and a construct the corpus
    obviously holds has to not.
    """
    out: list[tuple[bool, str]] = []
    rows = {r.grammar: r for r in sweep({"swift", "json", "go"})}

    # RED. The Swift case, reproduced — at the SPELLING and not at the rule,
    # which is the calibration this file failed on its first run and the reason
    # spellings are reported at all. `multiline_comment` is an external with no
    # body in grammar.json, so no rule-level reading here can ever reach it;
    # what IS spelled is `[\/]+[*]+`, by `custom_operator` — the very token that
    # ate the comment — and that spelling is absent from `Chunked.swift`.
    sw = rows.get("swift")
    dead = set(sw.impossible) if sw else set()
    lost = {l.text for l in sw.gone} if sw else set()
    out.append((r"[\/]+[*]+" in lost,
                "the Swift case reproduces at the spelling: `[\\/]+[*]+` is absent from"
                f" {sw.source if sw else '?'}"))
    blob = next(c.source for c in slate({"swift"})).read_bytes()
    out.append((b"/*" not in blob,
                "and for the stated reason — the file contains no `/*` at all"))
    # And that the rule-level reading is honestly blind to it rather than
    # silently calling it fine: the external has no body to judge.
    doc = json.loads((GRAMMARS / "swift.json").read_text())
    out.append(("multiline_comment" not in doc["rules"] and sw is not None
                and sw.unspelled > 0,
                f"and the rule-level reading admits it cannot see the external:"
                f" {sw.unspelled if sw else 0} swift external(s) have no body here"))

    # GREEN. A construct the file plainly holds must not be called impossible,
    # or every row above is noise.
    out.append((sw is not None and "line_string_literal" not in dead,
                "a construct the file plainly holds is NOT impossible:"
                " swift line_string_literal"))
    out.append((sw is not None and b'"' in blob
                and not any(l.text == '"' for l in sw.gone),
                "and a spelling it plainly holds is NOT absent: swift `\"`"))

    # ANTI-VACUITY, both directions. A sweep that called everything impossible
    # and a sweep that called nothing impossible would each satisfy some of the
    # assertions above by arithmetic.
    js = rows.get("json")
    out.append((js is not None and 0 < len(js.impossible) < len(js.scored),
                f"json is neither wholly possible nor wholly not:"
                f" {len(js.impossible) if js else 0} impossible of"
                f" {len(js.scored) if js else 0} scored rule(s)"))

    # The propagation, asked of the predicate rather than of a run. A CHOICE
    # survives one present member; a SEQ does not survive one absent one; a
    # REPEAT of an absent thing is still satisfiable, because zero is a
    # repetition and a rule is never impossible for lacking an optional part.
    a = Lit("STRING", "a")
    A = {"type": "STRING", "value": "a"}
    B = {"type": "STRING", "value": "b"}
    checks = (
        (satisfiable({"type": "CHOICE", "members": [A, B]}, {a}), "a CHOICE needs one"),
        (not satisfiable({"type": "SEQ", "members": [A, B]}, {a}), "a SEQ needs all"),
        (satisfiable({"type": "REPEAT", "content": B}, {a}), "a REPEAT needs none"),
        (not satisfiable({"type": "REPEAT1", "content": B}, {a}), "a REPEAT1 needs one"),
        (satisfiable({"type": "SYMBOL", "name": "x"}, set()), "a SYMBOL is not descended"),
    )
    out.append((all(h for h, _ in checks),
                "the propagation holds: " + ", ".join(w for h, w in checks if h)
                + ("" if all(h for h, _ in checks) else
                   "  BROKEN: " + ", ".join(w for h, w in checks if not h))))

    # An unreadable pattern must count PRESENT, so a rule is never called
    # impossible on the strength of a regex nobody parsed.
    junk = Lit("PATTERN", "(?<foo")
    here, why = junk.hunt(b"", "")
    out.append((here and why == UNREADABLE,
                f"an uncompilable pattern reads present, not absent ({why or 'compiled'})"))
    wide = Lit("PATTERN", "[a-z]*")
    here, why = wide.hunt(b"", "")
    out.append((here and why == VACUOUS,
                f"and so does one matching the empty string ({why or 'did not'})"))

    # THE NODE READING, calibrated on a file small enough to read by hand.
    # `ledger.go` is 1,189 bytes and contains exactly two `!` bytes, both of
    # them the first half of a `!=`. So the byte reading answers "the corpus
    # contains `!`" and the corpus does not: there is no `!` token in it. That
    # is the overcount, on one spelling, verifiable by eye.
    try:
        case = next(c for c in slate({"go"}))
        got = witness(case, rows["go"])
        blob = case.source.read_bytes()
        bang = Lit("STRING", "!")
        said = {(m.text, m.host) for m in got.mention}
        out.append((bang not in got.gone and bang in set(got.ghost),
                    f"the byte reading says {case.source.name} contains `!` and the node"
                    f" reading says it never tokenises one"))
        out.append((blob.count(b"!") == 2 and blob.count(b"!=") == 2,
                    f"and for the stated reason — both of its {blob.count(b'!')} `!` bytes"
                    f" are the head of a `!=`"))
        out.append((("!", '"!="') in said,
                    f"which is what the finding says: {dict(said).get('!', 'nothing')}"
                    f" is what swallowed it"))
        # GREEN, and the anti-vacuity with it: a reading that called everything
        # a ghost would satisfy the three above and mean nothing.
        out.append((not any(m.text == "func" for m in got.mention)
                    and 0 < len(got.ghost) < got.asked,
                    f"a spelling the file plainly tokenises is NOT a ghost: `func` — and"
                    f" {len(got.ghost)} of {got.asked} are, strictly between none and all"))
        # THE SIGN FLIP. `//` occurs twice, inside comments. The byte reading
        # called it present, which was the author's defect; calling it ABSENT
        # would be the same defect mirrored, so it is neither - go seals it
        # inside `token(seq('//', ...))` and it is outside both numbers.
        out.append((blob.count(b"//") == 2
                    and Lit("STRING", "//") in wrapped(
                        json.loads((GRAMMARS / "go.json").read_text()))
                    and not any(m.text == "//" for m in got.mention),
                    "and `//` is neither: it occurs twice, go seals it inside a token,"
                    " so no tree can be asked and it is out of both readings"))
        out.append((got.seen == got.sealed + got.asked,
                    f"the population closes: {got.seen} present ="
                    f" {got.sealed} sealed + {got.asked} asked"))
    except (OSError, ValueError, RuntimeError, StopIteration, KeyError) as bad:
        out.append((False, f"the node reading could not run: {str(bad)[:60]}"))

    # THE COLLISION, which this file's own tripwire reported as a defect in
    # itself for as long as it has existed, on a corpus-wide run nobody took.
    # tree-sitter names an anonymous token after its own text, so typescript's
    # `x: string` puts three nodes called `string` on the tree and none of them
    # is the rule `string`. Asserted on the tree rather than on the fix.
    try:
        ts = next(c for c in slate({"typescript"}))
        blob = ts.source.read_bytes()
        nodes = plumb.oracle(ts, blob)
        hit = [n for n in nodes if n.name == "string"]
        out.append((bool(hit) and not any(n.named for n in hit),
                    f"an anonymous token is not its namesake rule: {len(hit)} `string`"
                    f" node(s) in {ts.source.name}, {sum(n.named for n in hit)} of them named"))
        out.append((b'"' not in blob and b"'" not in blob,
                    "and the rule really is unspellable there — the file has no quote of"
                    " either kind, only backticks"))
    except (OSError, ValueError, RuntimeError, StopIteration) as bad:
        out.append((False, f"the anonymous-token check could not run: {str(bad)[:60]}"))

    # THE CROSS-CHECK. A rule the oracle built a node for cannot be impossible.
    # This is the only assertion here that can catch the walk being wrong about
    # a real grammar, and it is asked of the oracle's own tree.
    try:
        case = next(c for c in slate({"go"}))
        nodes = plumb.oracle(case, case.source.read_bytes())
        built = {n.name for n in nodes if n.named}
        clash = sorted(built & set(rows["go"].impossible))
        out.append((not clash, "no rule the oracle BUILT is called impossible:"
                    + (f" {' '.join(clash[:6])}" if clash else " none, over"
                       f" {len(built)} node type(s) in go")))
    except (OSError, ValueError, RuntimeError, StopIteration) as bad:
        out.append((False, f"the oracle cross-check could not run: {str(bad)[:60]}"))

    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL'}  {said}")
    bad = sum(not held for held, _ in out)
    print(f"\n{len(out) - bad} of {len(out)} held")
    return 1 if bad else 0


def oops(msg: str) -> int:
    print(f"absent.py: {msg}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("verb", nargs="?", default="run",
                    choices=("run", "show", "oracle", "aim", "verify"))
    ap.add_argument("grammar", nargs="*")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--oracle", default="", metavar="TAG",
                    help="answer from a frozen oracle pin (see attest.py list)")
    args = ap.parse_args(argv)

    if args.verb == "verify":
        return verify()
    known = {c.name for c in plumb.slate()}
    if stray := sorted(set(args.grammar) - known):
        return oops(f"no grammar named {', '.join(stray)}; there are {len(known)}")
    want = set(args.grammar)
    rows = sweep(want)
    if not rows:
        return oops("no grammar resolved to a source file")
    match args.verb:
        case "show":
            return show(rows, args.json)
        case "oracle":
            return oracle(rows, want, args.json, args.oracle)
        case "aim":
            return aim(rows, args.json)
        case _:
            return run(rows, args.json, stamp.take(plumb.BIN))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
