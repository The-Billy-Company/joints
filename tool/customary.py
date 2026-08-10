#!/usr/bin/env python3
"""Rung 1 of `research/customary/TESTING.md`: does the frozen algebra hold?

Two questions, and the point of asking them here rather than in Zig is that both
can be answered before the engine exists. If either fails, the engine would have
been built against a specification the census got wrong.

**1a expressiveness** (`check`). A customary is a program over two stacks and a
register bank. Executed against real bytes, does it emit the terminals
tree-sitter's own scanner emits, at the same offsets? The oracle is the
tree-sitter CLI's tree, read for its leaves - a leaf named by an external
terminal is that scanner's answer, positioned. Kill: a mismatch no edit to the
customary fixes, which means the algebra is short a test or an action.

The permission set is deliberately **not** modelled. A customary run here sees
`wanted` as "everything", because there is no parse table on this side, and that
is the more useful question anyway: it measures how much of a scanner's answer
the bytes and the organs decide on their own. A rule that genuinely needs the
parse state shows up as a mismatch and is reported as one rather than being
hidden by a synthesized set.

**1b composition** (`compose`). An organ effect over a segment is a stack
effect - pop k, push a suffix, and a register map - and stack effects compose.
Cut a file at every offset in a schedule, take each segment's effect, multiply
them, and the product must be the effect of the whole file. Kill: one cut where
it is not. This is `../joinery/TESTING.md` rung 1 asked about the lexer instead
of the parser, and it is what the `O(log n)` edit inside a heredoc rests on.

  python3 tool/customary.py check markdown [FILE...]
  python3 tool/customary.py compose markdown [FILE...]  [--cuts N]
  python3 tool/customary.py run markdown FILE            the token stream
  python3 tool/customary.py verify                       every customary parses

Exit 0 the question held, 1 it did not, 2 could not be asked.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
BOOK = ROOT / "customary"
CORPUS = ROOT / "research" / "joinery" / "corpus"
SOURCES = ROOT / "upstream" / "sources"
GRAMMARS = ROOT / "upstream" / "grammars"
ORACLE = ROOT / ".local" / "differential" / "cli" / "node_modules" / ".bin" / "tree-sitter"

TAB_STOP = 8


def read(path: Path) -> str:
    """A file as one character per byte.

    tree-sitter counts in bytes and so does the folio, so a run that counted
    characters would agree with the oracle on every ASCII file and disagree by
    the width of every em dash on the rest - which reads as a wrong decision when
    it is a wrong *ruler*. `latin-1` is total over bytes, so this cannot fail on
    a file the grammar itself would accept, and no probe in the eight asks about
    a byte above 0x7F except through a negated class.
    """
    return path.read_bytes().decode("latin-1")


#: PCRE2's absolute end of subject, and python's spelling of the same assertion.
#: The two languages disagree about `\Z` - in PCRE2 it permits a final newline,
#: in python it does not - so a book is written in the engine's dialect and this
#: is the one token that has to be carried across. Spelling `$` instead would be
#: wrong in both: a heredoc that runs to the end of a file ending in a newline
#: would report its content one byte short.
def dialect(pattern: str) -> str:
    return re.sub(r"(?<!\\)((?:\\\\)*)\\z", r"\1\\Z", pattern)


# ---------------------------------------------------------------- the program


@dataclass(frozen=True)
class Rule:
    """One guarded arm of a scanner, read off the C and written down.

    A rule with no `emit` in its actions is **effect-only**: its guard held, its
    organ writes stand, and the ask carries on to the rule behind it. The C has
    these too - every path that updates the delimiter stack or a register and then
    returns false - and they are how a customary remembers something about bytes
    it does not claim.
    """

    name: str
    phase: str
    when: tuple
    then: tuple
    emits: tuple
    #: Groups this rule answers for, so another rule's `fires` test can score it
    #: without committing. markdown's recursive `scan(s, lexer,
    #: paragraph_interrupt_symbols)` is the only caller in the eight, and the
    #: group is that constant array read as what it is: a named set of rules.
    groups: tuple = ()
    #: For a rule in the `matched` phase, the organ kind it answers for. Those
    #: rules are never swept: the `pass` test selects one by the kind of the
    #: frame under its cursor, which is `match(s, lexer, block)` in the C.
    kind: str | None = None
    #: The organ kind this rule ends. Only meaningful for an `opaque` kind, where
    #: it is the one thing still askable inside the region - see `Book.opaque`.
    closes: str | None = None


@dataclass(frozen=True)
class Book:
    grammar: str
    cohort: tuple
    kinds: dict
    probes: dict
    classes: dict
    rules: tuple
    #: How wide a tab is *for this grammar*. markdown's own `advance` says four
    #: (GFM's tab stop); python and haskell say eight. A per-grammar fact, so it
    #: is in the book and not a constant in the engine.
    tab: int = 8
    #: The register a grammar carries consumed-but-unspent indentation in, if it
    #: has one. Where it is set, `lead` in the `layout` phase means that register
    #: plus the whitespace at the offset, which is `s->indentation` exactly.
    budget: int | None = None
    #: Where a caller of *this* grammar's scanner asks. A property of the caller,
    #: never of the customary, and rung 1 has to state which one it is simulating
    #: because it has no parser to ask for it. `line` is a block scanner's two
    #: ask points - a line start and a line ending - and `token` is every offset,
    #: which is what a scanner called between adjacent tokens sees. In the engine
    #: this field does not exist: `Scanner.read` is called where it is called.
    asks: str = "line"
    #: Organ kinds whose inside is **opaque**: while one is the innermost frame,
    #: the only layout answer available is the rule that ends it. A fenced code
    #: block, a heredoc, and a raw string all have this shape - their content is
    #: bytes the grammar reads, not layout the scanner decides - and without it a
    #: deeply indented line inside a fence reads as the start of indented code.
    #: tree-sitter gets this from `valid_symbols`; a customary declares it.
    opaque: tuple = ()
    #: The probe matching what lies BETWEEN two tokens, if this grammar's extras
    #: do not cover it. A grammar whose every terminal is external declares no
    #: whitespace extra, because in its C the scanner soaks its own:
    #: tree-sitter-yaml opens every `scan` with a loop over spaces, tabs and line
    #: breaks before it looks at anything. That loop is one fact about the
    #: grammar, not a clause in each of its arms, so it is declared once and the
    #: step advances over it before any rule is scored.
    trivia: str | None = None

    PHASES = ("inside", "matched", "layout", "commanded", "opening",
              "enclosing", "bounded", "ordered")
    #: Phases the sweep never enters on its own. A `matched` rule is reached only
    #: through the `pass` test that selects it by organ kind.
    CALLED = ("matched",)

    @staticmethod
    def load(name: str) -> "Book":
        raw = json.loads((BOOK / f"{name}.json").read_text())
        kinds = raw.get("kinds", {})
        probes = {k: re.compile(dialect(v)) for k, v in raw.get("probes", {}).items()}
        classes = {
            k: [(re.compile(dialect(pat)), sym) for pat, sym in arms]
            for k, arms in raw.get("classes", {}).items()
        }
        rules = []
        for r in raw["rules"]:
            phase = r["phase"]
            if phase not in Book.PHASES:
                raise SystemExit(f"customary: {name}: unknown phase {phase!r}")
            then = tuple(tuple(a) for a in r["then"])
            emits = tuple(a[1] for a in then if a[0] == "emit")
            rules.append(
                Rule(
                    r["name"], phase, tuple(tuple(t) for t in r["when"]), then, emits,
                    tuple(r.get("groups", ())), r.get("kind"), r.get("closes"),
                )
            )
        book = Book(
            raw["grammar"], tuple(raw.get("cohort", ())), kinds, probes, classes,
            tuple(rules), raw.get("tab", 8), raw.get("budget"),
            raw.get("asks", "line"), tuple(raw.get("opaque", ())),
            raw.get("trivia"),
        )
        if book.asks not in ("line", "token"):
            raise SystemExit(f"customary: {name}: unknown ask points {book.asks!r}")
        book.audit()
        return book

    def matchers(self, kind: int) -> tuple:
        """The `matched`-phase rules that answer for one organ kind, in order.

        Several, because the C's arms have alternatives inside them - a list item
        matches on its own indentation *or* on a line that just ends - and an
        ordered list of guarded arms is how this algebra already spells a choice.
        Putting a conditional inside a matcher instead would be a second control
        structure for something the rule list already does.
        """
        return tuple(r for r in self.rules
                     if r.phase == "matched" and self.kind(r.kind) == kind)

    def audit(self) -> None:
        """Every name a rule reaches for has to resolve. A customary whose probe
        is misspelled would silently never match, which is the failure mode this
        design holds to be worse than refusing to load."""
        for r in self.rules:
            if (r.phase == "matched") != (r.kind is not None):
                raise SystemExit(
                    f"customary: {self.grammar}: {r.name}: a `matched` rule needs a "
                    f"`kind` and only a `matched` rule may carry one"
                )
            for t in r.when:
                named = t[1:3] if t[0] == "nest" else t[1:2]
                if (t[0].startswith("probe") or t[0] in ("no_probe", "nest")):
                    for p in named:
                        if p not in self.probes:
                            raise SystemExit(
                                f"customary: {self.grammar}: {r.name} probes unknown {p!r}"
                            )
                # A kind test reads `(op, "="|"in", kind)` addressed at the top and
                # `(op, index, "="|"in", kind)` addressed anywhere, so the operator
                # sits at 1 or 2 - the audit asks that one of them is an operator
                # rather than that a particular one is.
                if t[0].endswith(".kind") and not any(x in ("in", "=") for x in t[1:3]):
                    raise SystemExit(f"customary: {self.grammar}: {r.name} bad kind test {t!r}")
            for a in r.then:
                if a[0] == "emit" and len(a) > 2 and a[2] == "classified" and a[3] not in self.classes:
                    raise SystemExit(f"customary: {self.grammar}: {r.name} unknown class {a[3]!r}")

    def kind(self, name) -> int:
        if isinstance(name, int):
            return name
        if name not in self.kinds:
            raise SystemExit(f"customary: {self.grammar}: unknown kind {name!r}")
        return self.kinds[name]


# ------------------------------------------------------------------ the organs


@dataclass
class Organs:
    """Two stacks and a register bank, and nothing else - the frozen set.

    Immutably copied rather than mutated in place wherever a comparison is
    coming, because the composition falsifier holds two of these side by side
    and a shared list would make them agree by aliasing.
    """

    frames: list = field(default_factory=list)  # (width, kind)
    marks: list = field(default_factory=list)  # (kind, count, tag)
    regs: list = field(default_factory=lambda: [0] * 8)
    #: Where the last answer that had extent ended - the mark `Facts.broke` is
    #: measured from, and the only organ that is an offset rather than a state.
    #: The C's `scanner->row`, which only a `mark_end` moves, so a run of
    #: zero-width closes stays on the far side of the newline it crossed.
    since: int = 0

    def copy(self) -> "Organs":
        return Organs(list(self.frames), list(self.marks), list(self.regs), self.since)

    def key(self) -> tuple:
        return (tuple(self.frames), tuple(self.marks), tuple(self.regs), self.since)

    def depth(self) -> tuple:
        return (len(self.frames), len(self.marks))


@dataclass
class Facts:
    """What grain measures, restated for one offset. Not state: a function of the
    bytes, so it is recomputed per ask and never carried."""

    bol: bool
    lead: int
    blank: bool
    #: Whether the line *before* this one is blank. A blank line is where markdown
    #: ends an html block, and the grammar spends the blank line first and only
    #: then asks for the close - so the question at the offset that answers it is
    #: about the line just left, not the line arrived at. Same family as `blank`:
    #: a function of the bytes, measured once, carried nowhere.
    lull: bool
    column: int
    eof: bool
    #: Whether the inter-token skip this ask arrived over held a line ending.
    #: The one thing about a line no offset can be asked - tree-sitter-yaml's
    #: `has_nwl` is a fact about the gap between two tokens, and its nearest
    #: local proxy ("the line's first non-blank byte") disagrees with it at the
    #: first token of a file, which has no previous token. Only a book that
    #: declares `trivia` can see it; elsewhere the gap was the caller's extras
    #: and the customary never saw them.
    broke: bool = False


def soak(text: str, at: int, tab: int, carry: int = 0) -> tuple:
    """Blanks from `at`, as a new offset and the columns they are worth.

    The whole of the C's `while (lookahead == ' ' || '\\t') indentation +=
    advance(...)`, and the reason it is a function: the layout sweep does it once
    before deciding anything, and each block matcher does it again against its
    own target, so it is one operation with two callers rather than a shape two
    rules repeat.
    """
    off, col = at, carry
    while off < len(text) and text[off] in " \t":
        col = col + tab - (col % tab) if text[off] == "\t" else col + 1
        off += 1
    return off, col


def facts(text: str, at: int, tab: int = TAB_STOP, carry: int = 0) -> Facts:
    bol = at == 0 or text[at - 1] == "\n"
    line_start = text.rfind("\n", 0, at) + 1
    end = text.find("\n", at)
    end = len(text) if end < 0 else end
    i, lead = soak(text, line_start, tab, carry)
    lull = False
    if line_start:
        j, _ = soak(text, text.rfind("\n", 0, line_start - 1) + 1, tab)
        lull = j >= line_start - 1
    return Facts(
        bol=bol,
        lead=lead,
        blank=i >= end,
        lull=lull,
        column=at - line_start,
        eof=at >= len(text),
    )


# ------------------------------------------------------------- the interpreter


class Hit:
    __slots__ = ("symbol", "start", "length", "rule")

    def __init__(self, symbol, start, length, rule):
        self.symbol, self.start, self.length, self.rule = symbol, start, length, rule

    def __repr__(self):
        return f"{self.start}+{self.length} {self.symbol} [{self.rule}]"


class Engine:
    """One interpreter for every customary, which is the whole claim in one
    class: the per-language part is the book, never the code that runs it."""

    #: How many zero-width answers may stack at one offset before the run is
    #: called stalled. Every organ is bounded (a frame stack is 96 deep), so a
    #: legitimate run of them is bounded; past this a customary is looping.
    STALL = 512

    #: The tests this side answers by fiat rather than by reading anything. The
    #: permission set is the caller's, and rung 1 has no parse table, so `wanted`
    #: is yes and `not_wanted` is no for every terminal at every offset. That is
    #: the least-wrong constant for a book whose rows are told apart by the
    #: *bytes*, and it fabricates an impossible state for one whose rows are told
    #: apart by the *permission* - elixir's twenty quoted bodies are mutually
    #: exclusive, so a state admitting two of them is one no parser presents, and
    #: it is exactly the state a row's exclusivity guard exists to refuse. A rule
    #: turned away here was turned away by this tool's own blindness, and `fiat`
    #: is where that is written down so the verdict can say so.
    FABRICATED = frozenset(("wanted", "not_wanted", "named", "not_named", "sole",
                            "mending"))

    def __init__(self, book: Book):
        self.book = book
        #: offset -> the terminals whose every rule a fabricated test turned away.
        self.fiat: dict = {}

    def step(self, text: str, at: int, organs: Organs, fresh: bool = True,
             spent: frozenset = frozenset()) -> Hit | None:
        """The customary's answer at one offset, or `None` if it has none.

        `spent` carries the terminals already answered at this offset, and a rule
        that only emits one of them is passed over. It is this side's stand-in for
        the permission set: the parser that already took a `_blank_line_start`
        here will ask for something else next, never for that again, and without
        the suppression a zero-width answer wins its offset forever and every
        terminal ordered behind it is unreachable. See the module header for why
        `wanted` itself is not modelled.
        """
        # A book whose grammar declares no whitespace extra soaks its own, and
        # says so once in its preamble rather than in every arm. Step over it
        # before any rule is scored - the bytes come back as the hit's `skip`, so
        # a token's extent is still only the token - and remember whether a line
        # ending was among them, which is the one fact no offset can be asked.
        over = 0
        if self.book.trivia is not None:
            m = self.book.probes[self.book.trivia].match(text, at)
            over = m.end() - at if m else 0
        # Measured over the whole gap the mark opens, not over `over` alone: a
        # zero-width close already ate the newline this run is still behind.
        mark = min(organs.since, at)
        broke = self.book.trivia is not None and any(
            c in "\r\n" for c in text[mark:at + over])
        at += over
        for phase in Book.PHASES:
            if phase in Book.CALLED or (phase == "layout" and not fresh):
                continue
            off, f = self.stand(phase, text, at, organs)
            f = replace(f, broke=broke)
            sealed = self.sealed(organs)
            for rule in self.book.rules:
                if rule.phase != phase:
                    continue
                if phase == "layout" and sealed and rule.closes != sealed:
                    continue
                if rule.emits and all(e in spent for e in rule.emits):
                    continue
                hit, abstained = self.attempt(rule, text, off, organs, f, fresh)
                if hit is not None:
                    # The C's `flush` after a `mark_end`, and only after one: an
                    # answer with no extent never marked an end, so the gap it
                    # stands in stays open for whatever answers next.
                    if hit.length > 0:
                        organs.since = hit.start + hit.length
                    return hit
                if abstained:
                    return None
        return None

    def sealed(self, organs: Organs) -> str | None:
        """The opaque kind we are inside, if the innermost frame names one."""
        if not organs.frames:
            return None
        top = organs.frames[-1][1]
        return next((k for k in self.book.opaque if self.book.kind(k) == top), None)

    def stand(self, phase: str, text: str, at: int, organs: Organs) -> tuple:
        """Where a phase starts reading, and what it knows about the line there.

        Everywhere but `layout` that is just the offset. In `layout` the blanks
        are already behind us: the C soaks them into `s->indentation` once,
        before the switch that decides anything, so every rule in that phase sees
        an offset past them and a `lead` that is the carried budget plus what was
        just soaked. Doing it here rather than in fifteen rules is the difference
        between engine structure and copied data.
        """
        carry = organs.regs[self.book.budget] if self.book.budget is not None else 0
        if phase != "layout":
            return at, facts(text, at, self.book.tab)
        off, lead = soak(text, at, self.book.tab, carry)
        return off, replace(facts(text, off, self.book.tab), lead=lead)

    def attempt(self, rule: Rule, text: str, at: int, organs: Organs, f: Facts, fresh: bool):
        """Score a rule's guard without committing, then apply. markdown's
        `simulate` flag is exactly this, and it is the engine's structure rather
        than an input a rule reads."""
        bound = {}
        for test in rule.when:
            # Cleared per test so the taint names the test that turned the rule
            # away, not one that a passing `fires` left behind earlier in the same
            # guard. Every other key in `bound` is a binding and outlives its test.
            bound.pop("fiat", None)
            if not self.holds(test, text, at, organs, f, fresh, bound):
                if test[0] in Engine.FABRICATED or bound.get("fiat"):
                    self.fiat.setdefault(at, set()).update(rule.emits)
                return None, False
        return self.apply(rule, text, at, organs, bound), bound.get("abstain", False)

    def sweep(self, text: str, at: int, organs: Organs, start: int,
              lead: int | None = None, until: int | None = None) -> dict:
        """One bounded pass of the open-organ matchers, on a scratch copy.

        This is the C's `while (s->matched < open_blocks.size) match(...)` loop,
        and it is the one control shape the census's tests and actions could not
        express: not a loop over bytes but a loop over **one organ**, bounded by
        that organ's own depth, whose body is selected by the entry's own kind.
        Bounded the way `pop until` is bounded - a frame stack is 96 deep - so it
        adds iteration without adding unboundedness.

        Nothing here commits. The pass reports how far it got, what the budget
        became, and how many bytes it ate; the calling rule's own actions are what
        write those back, so a guard stays a guard. `lead` seeds the budget the
        matchers spend, which is what lets the same pass be run as a *simulation*
        on the next line from a stated cursor and a stated indentation, the way
        the C rewinds `s->matched` around its own look-ahead loop.

        `until` is the exclusive ceiling on the cursor, and it defaults to the
        whole stack. A grammar that can flag "close the innermost block" bounds
        the pass one short with it, reserving that frame for whichever rule
        actually closes it - the C's `if (matched == size - 1 && CLOSE_BLOCK)
        break`, said as arithmetic rather than as a second loop.
        """
        scratch = organs.copy()
        if lead is not None and self.book.budget is not None:
            scratch.regs[self.book.budget] = lead
        off, ran, cursor = at, 0, start
        ceiling = len(scratch.frames) if until is None else min(until, len(scratch.frames))
        while cursor < ceiling:
            carry = scratch.regs[self.book.budget] if self.book.budget is not None else 0
            f = replace(facts(text, off, self.book.tab), lead=carry)
            took = None
            for rule in self.book.matchers(scratch.frames[cursor][1]):
                bound = {"cursor": cursor, "eaten": 0}
                if all(self.holds(t, text, off, scratch, f, True, bound) for t in rule.when):
                    took = (rule, bound)
                    break
            if took is None:
                break
            self.apply(took[0], text, off, scratch, took[1])
            off += took[1].get("eaten", 0)
            cursor += 1
            ran += 1
        budget = scratch.regs[self.book.budget] if self.book.budget is not None else 0
        return {
            "pass.ran": ran,
            "pass.cursor": cursor,
            "pass.budget": budget,
            "pass.eaten": off - at,
            "pass.at": off,
            "pass.more": 1 if cursor < len(scratch.frames) else 0,
        }

    def holds(self, test, text, at, organs, f, fresh, bound) -> bool:
        op = test[0]
        if op == "probe" or op == "probe_at":
            # A probe reads where the rule has read to, never where it began, so
            # a soak and a probe in one guard compose without either knowing
            # about the other. `probe_at` is that behaviour under its old name.
            off = at + bound.get("eaten", 0)
            m = self.book.probes[test[1]].match(text, off)
            if m is None:
                return False
            bound["eaten"] = bound.get("eaten", 0) + (m.end() - m.start())
            bound["width"] = bound["eaten"]
            bound.setdefault("match", m)
            return True
        if op == "no_probe":
            return self.book.probes[test[1]].match(text, at + bound.get("eaten", 0)) is None
        # A balanced run: from where the guard has read to, count the opener the
        # rule already matched as depth one and read forward until it is paid off.
        # Nested block comments are not a regular language, so no probe can spell
        # this - and the census saw the counter (swift keeps its comment depth on
        # the C stack, kotlin and scala in a local) without saying who increments
        # it. This is who. Bounded by the bytes it claims, like every other guard,
        # and the depth never outlives the rule: an unterminated comment ends at
        # end of input, which is what all three C scanners decided to do.
        if op == "nest":
            open_, close = self.book.probes[test[1]], self.book.probes[test[2]]
            off, depth = at + bound.get("eaten", 0), 1
            while off < len(text) and depth:
                if (m := close.match(text, off)) is not None:
                    off, depth = m.end(), depth - 1
                elif (m := open_.match(text, off)) is not None:
                    off, depth = m.end(), depth + 1
                else:
                    off += 1
            bound["eaten"] = off - at
            bound["width"], bound["depth"] = bound["eaten"], depth
            return True
        # Blanks, up to a target the organ entry names - `while (s->indentation <
        # list_item_indentation(block))`. A guard rather than an action because
        # what follows it is a *test* on how far the budget got.
        if op == "soak":
            want, limit, base = 1 << 30, 1 << 30, None
            rest = list(test[1:])
            while rest:
                word = rest.pop(0)
                if word == "to":
                    want = self.value(rest.pop(0), organs, f, bound)
                elif word == "one":
                    limit = 1
                elif word == "from":
                    base = self.value(rest.pop(0), organs, f, bound)
                else:
                    raise SystemExit(f"customary: soak: unknown word {word!r}")
            off = at + bound.get("eaten", 0)
            col = base if base is not None else bound.get(
                "lead",
                f.lead if self.book.budget is None else organs.regs[self.book.budget],
            )
            eaten = 0
            while off < len(text) and text[off] in " \t" and col < want and eaten < limit:
                col = col + self.book.tab - (col % self.book.tab) if text[off] == "\t" else col + 1
                off, eaten = off + 1, eaten + 1
            bound["eaten"], bound["lead"] = off - at, col
            return True
        # One bounded pass of the matchers over the open frames, from a stated
        # cursor. `after` runs it on the *next* line - past what this guard has
        # already eaten, blanks soaked, budget starting from those blanks - which
        # is the C's look-ahead simulate rather than its committing loop.
        #
        # Bare, it binds and holds, exactly like `soak`: the C's look-ahead runs
        # unconditionally and only its *result* decides anything, so a rule that
        # wants the numbers without the verdict says `["pass", 0, "after"]` and
        # reads `pass.ran` in its actions. Add a comparison to make it a guard.
        if op == "pass":
            start, rest = self.value(test[1], organs, f, bound), list(test[2:])
            off, lead, until = at, None, None
            while rest and rest[0] in ("after", "until"):
                if rest.pop(0) == "after":
                    off, lead = soak(text, at + bound.get("eaten", 0), self.book.tab)
                else:
                    until = self.value(rest.pop(0), organs, f, bound)
            bound.update(self.sweep(text, off, organs, start, lead, until))
            if not rest:
                return True
            return compare(bound["pass.ran"], rest[0], self.value(rest[1], organs, f, bound))
        if op == "bol":
            return f.bol
        if op == "not_bol":
            return not f.bol
        if op == "blank":
            return f.blank
        if op == "not_blank":
            return not f.blank
        if op == "lull":
            return f.lull
        if op == "not_lull":
            return not f.lull
        if op == "broke":
            return f.broke
        if op == "not_broke":
            return not f.broke
        if op == "eof":
            return f.eof
        if op == "not_eof":
            return not f.eof
        if op == "fresh":
            return fresh
        # The permission set is unmodelled on this side; see the module header.
        if op in ("wanted", "named", "sole", "mending"):
            return True
        if op in ("not_wanted", "not_named"):
            return False
        if op == "lead":
            # Through `value`, so a soak earlier in the same guard is what this
            # reads - the test and the value have to mean the same `lead` or a
            # matcher soaks to a target and then compares against the budget it
            # started from.
            return compare(self.value("lead", organs, f, bound), test[1],
                           self.value(test[2], organs, f, bound))
        if op == "frames.depth":
            return compare(len(organs.frames), test[1], self.value(test[2], organs, f, bound))
        if op == "marks.depth":
            return compare(len(organs.marks), test[1], self.value(test[2], organs, f, bound))
        if op == "frames.top.kind":
            if not organs.frames:
                return False
            return self.kind_test(organs.frames[-1][1], test)
        if op == "marks.top.kind":
            if not organs.marks:
                return False
            return self.kind_test(organs.marks[-1][0], test)
        # Indexed addressing, forced by markdown and by nothing else in the
        # eight: its matching pass walks the open blocks outward under a cursor
        # it keeps in `s->matched`, so the element under test is not the top.
        if op == "frames.at.kind":
            i = self.value(test[1], organs, f, bound)
            if not 0 <= i < len(organs.frames):
                return False
            return self.kind_test(organs.frames[i][1], (op,) + tuple(test[2:]))
        if op == "frames.at.width":
            i = self.value(test[1], organs, f, bound)
            if not 0 <= i < len(organs.frames):
                return False
            return compare(organs.frames[i][0], test[2], self.value(test[3], organs, f, bound))
        # Score a named group of rules here without committing any of them.
        # markdown calls its own `scan` with a constant permission set to ask
        # "would a block start on this line?"; the constant array is a named set
        # of rules, and this is that question with the recursion flattened.
        if op == "fires" or op == "no_fires":
            # `after` scores past what this rule's own probe already matched,
            # which is how markdown asks "would a block start on the *next*
            # line?" - it consumes the newline first, then scans.
            #
            # `from V` anchors it at a stated offset with a stated indentation
            # instead, and the offset that matters is where a `pass` in the same
            # guard stopped. The C's look-ahead is one lexer walking forward: it
            # soaks the blanks, *matches the open blocks* - consuming their
            # markers - and only then scans for an interrupt. A `>` on the next
            # line of an open block quote is that block's continuation, and the
            # interrupt scan never sees it, because the match already ate it.
            if len(test) > 3 and test[2] == "from":
                off = self.value(test[3], organs, f, bound)
                lead = self.value(test[4], organs, f, bound) if len(test) > 4 else 0
            else:
                off = at + (bound.get("eaten", 0)
                            if len(test) > 2 and test[2] == "after" else 0)
                off, lead = soak(text, off, self.book.tab)
            any_holds, fiat = self.scored(test[1], text, off, organs, fresh, lead)
            if fiat:
                bound["fiat"] = True
            return any_holds if op == "fires" else not any_holds
        if op == "frames.top.width":
            if not organs.frames:
                return False
            return compare(organs.frames[-1][0], test[1], self.value(test[2], organs, f, bound))
        if op == "marks.top.count":
            if not organs.marks:
                return False
            return compare(organs.marks[-1][1], test[1], self.value(test[2], organs, f, bound))
        if op in ("marks.top.tag", "marks.has.tag"):
            if not organs.marks:
                return False
            reach = organs.marks[-1:] if op == "marks.top.tag" else organs.marks
            words = [w for w in test[1:] if isinstance(w, str)]
            fold = "folded" in words
            # The grouped form compares whole - one capture group's text against
            # the whole remembered tag - so a longer name cannot pass on its
            # prefix. The offset form reads exactly as many bytes as the tag is
            # long, which is what a heredoc's close needs and all it has.
            caught = None
            if "group" in words:
                m = bound.get("match")
                caught = (m.group(test[test.index("group") + 1]) or "") if m else ""
            for _, _, tag in reach:
                got = caught if caught is not None else text[at : at + len(tag)]
                if caught is not None and len(got) != len(tag):
                    continue
                if (got.upper() == tag.upper()) if fold else (got == tag):
                    return True
            return False
        if op == "frames.has":
            return any(k == self.book.kind(test[1]) for _, k in organs.frames)
        if op == "marks.has":
            return any(k == self.book.kind(test[1]) for k, _, _ in organs.marks)
        if op == "reg":
            return compare(organs.regs[test[1]], test[2], self.value(test[3], organs, f, bound))
        raise SystemExit(f"customary: unknown test {op!r}")

    def scored(self, group: str, text, at, organs: Organs, fresh, lead: int = 0) -> tuple:
        """Whether any rule in `group` would hold here, guard only, and whether
        that verdict rested on a test this side fabricates.

        A copy of the organs goes in, so nothing a scored guard reads can be
        changed by scoring it - which is the whole difference between this and
        actually running the rule, and it is why the recursion is one level deep
        by construction: a scored rule's own `fires` test scores against the same
        frozen copy and cannot descend into a group that scores it back.

        The second half of the answer is what keeps `FABRICATED` from leaking: a
        `no_fires` is a plain test to the rule that names it, so a group admitted
        by a fiat `wanted` would otherwise turn away a row for a reason that reads
        like the bytes and is not.
        """
        f = replace(facts(text, at, self.book.tab), lead=lead)
        frozen = organs.copy()
        fiat = False
        for rule in self.book.rules:
            if group not in rule.groups:
                continue
            held, guessed = True, False
            for t in rule.when:
                if t[0] in ("fires", "no_fires"):
                    continue
                guessed = guessed or t[0] in Engine.FABRICATED
                if not self.holds(t, text, at, frozen, f, fresh, {}):
                    held = False
                    break
            if held:
                return True, guessed
            fiat = fiat or guessed
        return False, fiat

    def kind_test(self, got: int, test) -> bool:
        if test[1] == "in":
            return any(got == self.book.kind(k) for k in test[2])
        return got == self.book.kind(test[2])

    def value(self, v, organs, f, bound):
        if isinstance(v, int):
            return v
        if v == "lead":
            # What a soak in this same guard arrived at, else the line's own.
            return bound.get("lead", f.lead)
        if v == "column":
            return f.column
        if v == "width" or v == "eaten":
            return bound.get("eaten", bound.get("width", 0))
        if v == "cursor":
            return bound.get("cursor", 0)
        if isinstance(v, list) and v[0] == "span":
            # How wide one group of the guard's match was. The count a scanner
            # keeps is nearly always the length of a run it just read - swift's
            # `#`s, kotlin's `$`s, a fence's backticks - and reading it off the
            # match is how a rule states that without arithmetic.
            m = bound.get("match")
            got = m.group(v[1]) if m else None
            return len(got) if got else 0
        if isinstance(v, list) and v[0] == "number":
            # The figure the group spells rather than its length, truncated at
            # the first byte that is not a digit and capped where a column stops
            # being a column.
            m = bound.get("match")
            got = (m.group(v[1]) if m else None) or ""
            digits = ""
            for c in got:
                if not c.isdigit():
                    break
                digits += c
            return min(int(digits), 0xFFFF) if digits else 0
        if isinstance(v, str) and v.startswith("pass."):
            return bound[v]
        if v == "frames.top.width":
            return organs.frames[-1][0] if organs.frames else 0
        if v == "frames.depth":
            return len(organs.frames)
        if v == "marks.depth":
            return len(organs.marks)
        if v == "marks.top.count":
            return organs.marks[-1][1] if organs.marks else 0
        if isinstance(v, list) and v[0] == "reg":
            return organs.regs[v[1]]
        if isinstance(v, list) and v[0] == "frames.at.width":
            i = self.value(v[1], organs, f, bound)
            return organs.frames[i][0] if 0 <= i < len(organs.frames) else 0
        if isinstance(v, list) and v[0] in ("+", "-", "max", "min"):
            a = self.value(v[1], organs, f, bound)
            b = self.value(v[2], organs, f, bound)
            return {"+": a + b, "-": a - b, "max": max(a, b), "min": min(a, b)}[v[0]]
        raise SystemExit(f"customary: unknown value {v!r}")

    def apply(self, rule: Rule, text, at, organs: Organs, bound) -> Hit | None:
        f = facts(text, at, self.book.tab)
        hit = None
        skip = 0
        for act in rule.then:
            head = act[0]
            if head == "refuse":
                return None
            # `return false` after a state write, which every one of the eight
            # does somewhere. `refuse` withdraws the rule and lets the one behind
            # it answer; this withdraws the whole *ask*, which is the difference
            # between "not me" and "nothing here" - and a customary that could
            # only say the first would let the rule behind it answer at an offset
            # the rule in front had just accounted for.
            elif head == "abstain":
                bound["abstain"] = True
                return None
            elif head == "emit":
                sym, width = act[1], bound.get("eaten", bound.get("width", 0))
                if len(act) > 3 and act[2] == "classified":
                    # The classifier renames its own answer; the width is
                    # whatever the probe matched, since that is the text it read.
                    sym = self.classify(act[3], text, at, width, sym)
                elif len(act) > 2:
                    width = self.value(act[2], organs, f, bound)
                hit = Hit(sym, at + skip, max(0, width), rule.name)
            elif head == "skip":
                skip += self.value(act[1], organs, f, bound)
            elif head == "push":
                if act[1] == "frames":
                    organs.frames.append(
                        (self.value(act[2], organs, f, bound), self.book.kind(act[3]))
                    )
                else:
                    tag = ""
                    if len(act) > 4:
                        tag = self.slice(act[4], text, at, bound)
                    organs.marks.append(
                        (self.book.kind(act[2]), self.value(act[3], organs, f, bound), tag)
                    )
            elif head == "pop":
                stack = organs.frames if act[1] == "frames" else organs.marks
                if len(act) > 2 and act[2] == "until":
                    want = self.book.kind(act[3])
                    idx = 1 if act[1] == "frames" else 0
                    while stack and stack[-1][idx] != want:
                        stack.pop()
                    if stack:
                        stack.pop()
                elif stack:
                    stack.pop()
            elif head == "set":
                organs.regs[act[1]] = self.value(act[2], organs, f, bound)
            else:
                raise SystemExit(f"customary: unknown action {head!r}")
        return hit

    def classify(self, name, text, at, width, fallback):
        """The one action a `Provision` structurally cannot have: a second
        pressed table over the text just matched, renaming the answer. yaml's
        schema resolver, and the reason it is an action rather than an input."""
        got = text[at : at + width]
        for pattern, sym in self.book.classes[name]:
            if pattern.fullmatch(got):
                return sym
        return fallback

    def slice(self, spec, text, at, bound):
        if spec == "match":
            m = bound.get("match")
            return m.group(0) if m else ""
        if isinstance(spec, list) and spec[0] == "group":
            m = bound.get("match")
            return m.group(spec[1]) if m else ""
        return spec

    def walk(self, text: str, organs: Organs | None = None, limit: int = 1 << 22,
             asked=None, lo: int = 0, hi: int | None = None, journal: list | None = None):
        """Every answer the customary gives over a whole file, in order.

        A zero-width answer leaves the offset where it was, so the ask repeats with
        that terminal spent - which is how a run of zero-width answers at one line
        start (`block_continuation`, `_blank_line_start`, `_line_ending`) comes out
        in order instead of the first one winning its offset forever.

        Spent by *terminal and organ state*, not by terminal alone. Three open
        blocks ending on one line owe three `_block_close`es at one offset, and
        each is a different question because the one before it popped a frame. So
        an answer that moved the organs clears the set, and only one that left them
        exactly as they were is spent. Progress is what bounds the repeat, and the
        organs are finite, so `STALL` is a diagnostic rather than the guarantee.

        **Where the asks happen is itself a claim.** There is no slate on this side
        to lex what the customary declined, and asking at every byte is not the
        cheap version of a parse - it is a different question, one that finds a
        `*` in the middle of a sentence and calls it a list marker. So the ask
        points are the two a block scanner's caller structurally has: the start of
        a line, and the line's own ending, plus wherever an answer left off. A
        decline walks to the next of those rather than to the next byte.

        `asked(hit) -> bool` is the optional envelope: an answer it refuses is one
        no caller could have asked for there, so the ask is void rather than
        declined. It is how this side separates the engine's answers from the
        permission set's - see `envelope` for what supplies it and why that is not
        circular. Nothing inside a customary can read it.

        `lo`/`hi` bound it to one **segment**, half-open, so segments tile: the
        offset a segment stops at is the next segment's first ask and never both.
        `journal` collects `(offset, organ key)` at every point the cursor moves,
        which is the whole file's answer to "what was the state here" and what the
        composition falsifier compares a product against.
        """
        organs = organs or Organs()
        end = len(text) if hi is None else hi
        out, at, steps, held = [], lo, 0, 0
        spent: set = set()
        if journal is not None:
            journal.append((at, organs.key()))
        # `<=` only at the true end of input, where a customary still has one ask
        # to make - markdown closes its open blocks there, zero-width.
        while (at < end or (at == end == len(text))) and steps < limit:
            steps += 1
            was = organs.key()
            keep = organs.copy() if asked is not None else None
            hit = self.step(text, at, organs, fresh=True, spent=frozenset(spent))
            if hit is not None and asked is not None and not asked(hit):
                # A rule commits its organ effects as it answers, so voiding the
                # answer voids the effects too - otherwise a refused list marker
                # still leaves its item frame open and everything the envelope was
                # built to explain comes back one line later. Then ask again with
                # that terminal spent, because a permission set that forbids one
                # terminal is not a caller that stopped asking: the parser wants
                # the next thing the customary would say here.
                organs = keep
                spent = spent | {hit.symbol}
                continue
            if hit is not None:
                out.append(hit)
                if hit.length == 0 and hit.start == at:
                    held += 1
                    if held > self.STALL:
                        raise SystemExit(
                            f"customary: {self.book.grammar}: {self.STALL} zero-width "
                            f"answers at offset {at} without leaving it - a rule is "
                            f"pushing what it pops"
                        )
                    spent = set() if organs.key() != was else spent | {hit.symbol}
                    continue
                at, spent, held = hit.start + hit.length, set(), 0
                if journal is not None:
                    journal.append((at, organs.key()))
                continue
            if at >= len(text):
                break
            if self.book.asks == "token":
                at, spent, held = at + 1, set(), 0
            else:
                stop = text.find("\n", at)
                stop = len(text) if stop < 0 else stop
                at, spent, held = (stop if at < stop else stop + 1), set(), 0
            if journal is not None:
                journal.append((at, organs.key()))
        return out, organs


def compare(a: int, op: str, b: int) -> bool:
    return {
        "=": a == b, "!=": a != b, "<": a < b,
        "<=": a <= b, ">": a > b, ">=": a >= b,
    }[op]


# ---------------------------------------------------------------- 1a: the oracle


def externals_of(grammar: str) -> set:
    lang = json.loads((GRAMMARS / f"{grammar}.json").read_text())
    return {e["name"] for e in lang.get("externals", []) if e.get("type") == "SYMBOL"}


_TREES: dict = {}


def cst(grammar: str, path: Path) -> list | None:
    """Every node tree-sitter's own parser put in the tree, at a byte offset.

    Through `differential.py` rather than beside it, all the way down to reading
    the render: that module owns generating a pinned grammar, keeping each lane's
    compiled libraries apart, telling a file with an `ERROR` in it from a CLI
    that refused, and - the part nobody should write twice - inverting the CLI's
    own column arithmetic to recover a row's depth. A second reader of that
    format would be a second place for it to be wrong.
    """
    # One tree per (grammar, file) per process. `check` and any cross-check over
    # the same file would otherwise each pay a `tree-sitter parse`, and the oracle
    # dominates a corpus run by two orders of magnitude.
    seen = (grammar, str(path))
    if seen in _TREES:
        return _TREES[seen]
    try:
        import differential as diff
    except ImportError:
        return None
    if not diff.oracle_ready():
        return None
    home = diff.oracle_home(grammar)
    pin = GRAMMARS / f"{grammar}.json"
    if not pin.exists():
        return None
    try:
        diff.oracle_build(home, pin)
        # Absolute, because the CLI is run from the workspace and not from here.
        text = diff.oracle_run(home, path.resolve(), "--cst")
        root, _ = diff.cst_tree(text, diff.Lines(path.read_bytes()))
    except (ValueError, OSError):
        _TREES[seen] = None
        return None
    out: list = []

    def flatten(node) -> None:
        out.append((node.start, node.name, node.end, not node.kids))
        for kid in node.kids:
            flatten(kid)

    flatten(root)
    _TREES[seen] = out
    return out


def surface(grammar: str) -> dict:
    """Each external, and the node name it *wears* in tree-sitter's own tree.

    A token whose name begins with `_` is invisible: it does the scanner's work
    and leaves no leaf behind, so most of markdown's 47 externals cannot be read
    out of a tree under their own names. Two things bring them back, and both are
    facts in `grammar.json` rather than a table anyone has to maintain here:

      * an **alias** - `_block_quote_start` is spelled `block_quote_marker`;
      * a **thin wrapper rule** whose whole body is a choice of externals -
        `list_marker_minus` is `_list_marker_minus` or its dont_interrupt twin,
        so a leaf under that name is one of the two, positioned.

    Anything left over is genuinely unobservable in a tree (`_line_ending`,
    `_block_close`), and the value is `None` so `check` can count it as an honest
    hole rather than score it as agreement.
    """
    doc = json.loads((GRAMMARS / f"{grammar}.json").read_text())
    ext = externals_of(grammar)
    worn = {e: (None if e.startswith("_") else e) for e in ext}

    def alias(node) -> None:
        if isinstance(node, dict):
            body = node.get("content")
            if (
                node.get("type") == "ALIAS"
                and isinstance(body, dict)
                and body.get("type") == "SYMBOL"
                and body["name"] in ext
            ):
                worn[body["name"]] = node.get("value")
            for v in node.values():
                alias(v)
        elif isinstance(node, list):
            for v in node:
                alias(v)

    def only_externals(node):
        """The externals this body is made of, or `None` if it is made of
        anything else - which is what makes a wrapper thin enough to trust."""
        if not isinstance(node, dict):
            return None
        kind = node.get("type")
        if kind == "SYMBOL":
            return {node["name"]} if node["name"] in ext else None
        if kind == "CHOICE":
            got = set()
            for m in node["members"]:
                inner = only_externals(m)
                if inner is None:
                    return None
                got |= inner
            return got
        if kind in ("PREC", "PREC_LEFT", "PREC_RIGHT", "PREC_DYNAMIC", "FIELD",
                    "TOKEN", "IMMEDIATE_TOKEN"):
            return only_externals(node.get("content"))
        return None

    alias(doc["rules"])
    for name, body in doc["rules"].items():
        if name.startswith("_"):
            continue
        inner = only_externals(body)
        for e in inner or ():
            worn.setdefault(e, None)
            if worn[e] is None:
                worn[e] = name
    return worn


def oracle_leaves(grammar: str, path: Path, cohort: tuple = ()) -> list | None:
    """The scanner's answers as the tree spells them: `(offset, worn name)`.

    Scoped to the book's `cohort` when it declares one, because a customary is
    answerable for the terminals it claims and for nothing else. Kotlin's book
    claims the string and comment families and leaves automatic-semicolon
    insertion - four keyword look-aheads gated on `valid_symbols` - to the engine
    that has a permission set; counting those as misses would report the *scope*
    of the transcription as a defect in the algebra.
    """
    nodes = cst(grammar, path)
    if nodes is None:
        return None
    surf = surface(grammar)
    worn = {v for k, v in surf.items() if v and (not cohort or k in cohort)}
    return sorted((off, name) for off, name, _, _ in nodes if name in worn)


def enclosing(grammar: str, path: Path, off: int) -> str:
    """The smallest tree node that spans an offset, or `-` if none does.

    What a disagreement is *for*. An answer the customary gave inside a
    `paragraph` or an `inline` is one the parse table could not have asked for
    there, so the permission set - unmodelled here on purpose, per the module
    header - accounts for it. An answer inside a block node the terminal belongs
    to would be a real defect. Saying which, per row, is the difference between
    reporting a residue and explaining it.
    """
    nodes = cst(grammar, path) or ()
    span = [n for n in nodes if n[0] <= off < n[2]]
    return min(span, key=lambda n: n[2] - n[0])[1] if span else "-"


def reachable(grammar: str) -> dict:
    """Per visible rule, every symbol a parse of it can ever contain.

    Pure `grammar.json` closure - no LR table, no states, and no reading of any
    tree. `_atx_heading_content` aliases `_line` to the name `inline`, `_line` is
    a repeat of words, whitespace and punctuation, and nothing under it reaches
    `_list_marker_dot`. So "can a `_list_marker_dot` live inside an `inline`?" is
    answerable from the grammar alone, and the answer is no.

    Over-approximate on purpose: reachability admits every symbol some parse of
    that rule could hold, where `valid_symbols` at one LR state admits fewer. An
    over-approximation is the safe direction - it can only *fail* to explain a
    spurious answer, never manufacture an explanation.
    """
    if grammar in _REACH:
        return _REACH[grammar]
    doc = json.loads((GRAMMARS / f"{grammar}.json").read_text())
    rules = doc.get("rules", {})
    direct: dict = {}
    # One tree name can be several rules: `inline` is an alias of `_line` under a
    # heading and of `repeat1(_line | _soft_line_break)` under a paragraph. A name
    # keyed to one of them would be wrong about the other, so an alias name
    # collects the union of every occurrence - the safe direction again.
    alias: dict = {}

    def scan(node, into: set) -> None:
        if isinstance(node, list):
            for kid in node:
                scan(kid, into)
            return
        if not isinstance(node, dict):
            return
        if node.get("type") == "SYMBOL":
            into.add(node["name"])
            return
        if node.get("type") == "ALIAS" and node.get("named") and node.get("value"):
            scan(node.get("content"), alias.setdefault(node["value"], set()))
        for key in ("content", "members", "value"):
            if key in node:
                scan(node[key], into)

    for name, body in rules.items():
        direct[name] = set()
        scan(body, direct[name])
    # A fixpoint rather than a recursion: grammar rules are mutually recursive
    # (`_block` holds a `list` holds a `_block`), and a depth-first closure would
    # memoize whichever half of a cycle it happened to see first.
    out = {name: set(kids) for name, kids in direct.items()}
    moved = True
    while moved:
        moved = False
        for name, got in out.items():
            grew = got.union(*(out.get(k, ()) for k in got)) if got else got
            if grew != got:
                out[name], moved = grew, True
    for name, seeds in alias.items():
        out.setdefault(name, set()).update(
            seeds.union(*(out.get(s, ()) for s in seeds)) if seeds else seeds
        )
    _REACH[grammar] = out
    return _REACH[grammar]


_REACH: dict = {}


def envelope(grammar: str, path: Path):
    """Every ask a real caller could make here, and no others. Two halves.

    **Positional.** A lexer is called *between* tokens, never inside one, so an
    offset strictly interior to a leaf of tree-sitter's own tree is one the
    scanner provably was never asked at. That half reads only offsets.

    **Grammatical.** At an offset the parser *is* between tokens, it still only
    asks for the terminals its state allows - `valid_symbols`, the one engine
    input this offline side does not have. `reachable` supplies the sound
    over-approximation of it: the innermost tree node the offset sits in names a
    grammar rule, and a terminal that rule cannot reach is a terminal the parser
    cannot have asked for there.

    Not circular, and worth being exact. The tree supplies *where* and *inside
    what*; it never supplies which terminal is right. A customary answering
    `list_marker_dot` at a line start where the tree holds a heading is still
    caught, because `section` reaches both. What the envelope removes is only the
    class of answer that no parse table would have requested.
    """
    nodes = cst(grammar, path)
    if nodes is None:
        return None
    # Sized by the whole tree, not by the leaves: markdown's leaves stop at the
    # last punctuation the inline grammar named, and an array that stops there
    # would silently admit every ask past it.
    reach_end = max((n[2] for n in nodes), default=0) + 2
    span = [(s, e) for s, _, e, leaf in nodes if leaf and e - s > 1]
    # A difference array over the leaf interiors, so an ask costs one index rather
    # than a scan of the tree - over a corpus that is the whole cost.
    edge = [0] * reach_end
    for s, e in span:
        edge[s + 1] += 1
        edge[e] -= 1
    run, void = 0, bytearray(len(edge))
    for i, d in enumerate(edge):
        run += d
        void[i] = 1 if run > 0 else 0

    reach = reachable(grammar)
    # The seat of an offset: the innermost node that *strictly* contains it,
    # painted widest-first. Strictly, because a boundary offset belongs to what
    # surrounds the node starting there, not to the node itself - the parser
    # standing at the front of a `list_marker_minus` has not shifted it yet, and
    # that is exactly where the `_block_close` closing the item before it goes.
    home: list = [""] * (len(void) + 1)
    for s, name, e, _ in sorted(nodes, key=lambda n: n[0] - n[2]):
        for i in range(s + 1, min(e, len(home))):
            home[i] = name
    worn = surface(grammar)
    spell = {v: k for k, v in worn.items() if v}

    def asked(hit) -> bool:
        off = hit.start
        if off < len(void) and void[off]:
            return False
        seat = home[off] if off < len(home) else ""
        if seat not in reach:
            return True  # an anonymous token or the root: no rule to consult
        return {hit.symbol, spell.get(worn.get(hit.symbol), hit.symbol)} & reach[seat] != set()

    return asked


def sight(text: str, off: int) -> str:
    """The line an offset lands in, with the offset's column marked.

    A bare byte offset says a disagreement happened; it does not say what the
    scanner was looking at. This renders `line:col |<the line, caret at col>` so
    a report reads as evidence.
    """
    head = text.rfind("\n", 0, off) + 1
    tail = text.find("\n", off)
    line, col = text.count("\n", 0, off) + 1, off - head
    body = text[head : tail if tail >= 0 else len(text)]
    return f"{line}:{col} |{body[:col]}<{body[col:col + 40]}"


def check(book: Book, paths: list, loud: bool = False, quiet: bool = False) -> tuple:
    """Agreement between a customary's answers and tree-sitter's own, per file.

    Compared under the names the *tree* uses (`surface`), so `_list_marker_minus`
    and `list_marker_minus` are one fact rather than two spellings of it. An
    answer whose terminal is invisible in a tree is not scored either way - it is
    counted, printed as a hole, and left for the differential to settle once the
    engine exists.
    """
    engine = Engine(book)
    bad, tally = 0, [0, 0, 0, 0]  # matched · missed · spurious · unobservable
    by: dict = {}
    where: Counter = Counter()
    fenced = [0, 0]  # under the envelope: missed · spurious
    left: Counter = Counter()
    # Why a zero could be a zero. A cohort of hidden terminals wears no name in a
    # tree, so `oracle_leaves` filters every one of them out and the comparison is
    # empty for a reason that has nothing to do with agreement; a grammar with no
    # oracle installed here is empty for a third reason. Counted so the verdict can
    # name which silence it is standing in instead of printing `held` over nothing.
    mute = 0
    #: Answers the permission set would have settled; see `Engine.FABRICATED`.
    fiats = 0
    for path in paths:
        text = read(path)
        engine.fiat = {}
        got, _ = engine.walk(text)
        theirs = oracle_leaves(book.grammar, path, book.cohort)
        worn = {k: v for k, v in surface(book.grammar).items()
                if not book.cohort or k in book.cohort}
        blind = [h for h in got if not worn.get(h.symbol)]
        mine = [(h.start, worn[h.symbol]) for h in got if worn.get(h.symbol)]
        if theirs is None:
            print(f"  {path.name}: oracle unavailable, {len(got)} emitted")
            mute += 1
            continue
        ours, ts = set(mine), set(theirs)
        hit = ours & ts
        # A miss the permission set would have decided is this tool's hole, not the
        # book's error: `Engine.fiat` says which terminals a fabricated test turned
        # away and where. Counted with the invisible terminals, which are the other
        # thing a tree cannot settle.
        fiat = {(off, name) for off, name in (ts - ours)
                if any(worn.get(t) == name for t in engine.fiat.get(off, ()))}
        miss = sorted(ts - ours - fiat)
        spur = sorted(ours - ts)
        blind += sorted(fiat)
        fiats += len(fiat)
        share = 100.0 * len(hit) / len(ts) if ts else 100.0
        tally[0] += len(hit)
        tally[1] += len(miss)
        tally[2] += len(spur)
        tally[3] += len(blind)
        for off, name in miss:
            by.setdefault(name, [0, 0, 0])[1] += 1
        for off, name in spur:
            by.setdefault(name, [0, 0, 0])[2] += 1
            where[enclosing(book.grammar, path, off)] += 1
        for off, name in hit:
            by.setdefault(name, [0, 0, 0])[0] += 1
        if miss or spur:
            asked = envelope(book.grammar, path)
            walled, _ = engine.walk(text, asked=asked)
            inside = {(h.start, worn[h.symbol]) for h in walled if worn.get(h.symbol)}
            fenced[0] += len(ts - inside)
            fenced[1] += len(inside - ts)
            for off, name in sorted(inside - ts):
                left[name] += 1
        if not quiet:
            print(
                f"  {path.name}: {len(hit)}/{len(ts)} agreed ({share:.1f}%), "
                f"{len(miss)} missed, {len(spur)} spurious, {len(blind)} unobservable"
            )
            for tag, rows in (("missed  ", miss), ("spurious", spur)):
                for off, name in rows[: 8 if loud else 3]:
                    inside = enclosing(book.grammar, path, off)
                    print(f"      {tag} {off:>7} {name:<28} in {inside:<12} "
                          f"{sight(text, off)}")
        if miss or spur:
            bad += 1
    print(
        f"  --- {tally[0]} agreed · {tally[1]} missed · {tally[2]} spurious · "
        f"{tally[3]} unobservable"
    )
    for name in sorted(by, key=lambda n: -(by[n][1] + by[n][2])):
        got, missed, spurs = by[name]
        recall = 100.0 * got / (got + missed) if got + missed else 100.0
        print(f"      {name:<34} {got:>6} agreed  {missed:>6} missed "
              f"({recall:5.1f}% recall)  {spurs:>6} spurious")
    if where:
        print("      spurious answers, by the tree node they landed inside:")
        for node, n in where.most_common():
            print(f"        {node:<32} {n:>6}")
    if tally[1] or tally[2]:
        print(f"      asked only where a lexer is called, and only for terminals "
              f"the grammar reaches there: {fenced[0]} missed · {fenced[1]} spurious")
        for name, n in left.most_common():
            print(f"        {name:<32} {n:>6}")
    surf = surface(book.grammar)
    seen = tuple(k for k in (book.cohort or surf) if surf.get(k))
    return bad, tally, fenced, Silence(mute, len(paths), seen, tuple(book.cohort), fiats)


class Silence(NamedTuple):
    """Why a check that scored nothing scored nothing.

    Four zeros read identically on the page and mean different things, so the
    verdict needs them apart: no oracle answered (`mute`), the cohort is hidden
    terminals no tree names (`seen` empty), the corpus was there and the answers
    were the *permission set's* to decide, which this side fabricates (`fiat`), or
    there were simply no files. Only the fifth reading - a corpus that holds no
    instance of a claimed terminal - is a corpus problem rather than a harness
    one, and it is what is left when the four are ruled out.
    """

    mute: int
    files: int
    seen: tuple
    cohort: tuple
    fiat: int = 0

    def why(self) -> str | None:
        if not self.files:
            return "no files"
        if not self.seen:
            return (f"none of the {len(self.cohort)} terminal(s) this book claims wears a "
                    f"name in a tree, so nothing it answers is observable here")
        if self.mute >= self.files:
            return f"no oracle answered for any of {self.files} file(s)"
        if self.fiat:
            return (f"{self.fiat} answer(s) were the permission set's to decide, and rung 1 "
                    f"has no parse table - this book's rows are told apart by which terminal "
                    f"the state admits, so the board is its gate")
        return f"the corpus holds no instance of any claimed terminal"


# ------------------------------------------------------- 1b: the composition


def effect(engine: Engine, text: str, lo: int, hi: int, entry: Organs) -> Organs:
    """This segment's organ effect, applied to one entry state.

    Per entry state, exactly as `joints survey` measures an LR segment effect
    per entry state, and for the same reason: a guard reads the organs, so the
    effect is a function rather than a constant. What composition asks is
    whether the function factors through the cut, not whether it is constant.

    The same `walk` the whole file gets, bounded. One code path on purpose: a
    segment that read its bytes by a second rule would be measuring the harness.
    """
    _, organs = engine.walk(text, entry.copy(), lo=lo, hi=hi)
    return organs


def compose(book: Book, paths: list, schedules: list) -> int:
    """Rung 1b: is the state at a cut all a resumption needs?

    Compared **at every cut**, not only at end of input. A file that closes what
    it opens has an empty state at EOF, so an end-state comparison would pass a
    customary whose middle was wrong everywhere - which is most of them, since
    strings and blocks close. The whole-file walk journals the state at every
    offset it moves the cursor to; the product has to match that journal entry
    the moment it arrives there.

    Cuts land on those journalled offsets rather than on arbitrary bytes, and
    that is not a weakening: an offset the whole-file walk never asked at is not
    a place any caller resumes. Lexer state is defined between tokens - it is
    where tree-sitter reuses a token and where weave will re-enter - so a cut
    through the middle of one is a question about a token, not about composition.
    """
    engine = Engine(book)
    bad = 0
    for path in paths:
        text = read(path)
        journal: list = []
        _, whole = engine.walk(text, journal=journal)
        # A journal entry is the state on *arrival* at an offset, before anything
        # is answered there, which is the only reading a resumption can use. The
        # end of input is therefore not a checkpoint: markdown closes its open
        # blocks there zero-width, and those answers move no cursor, so the last
        # entry describes the file before its own ending. The end state is
        # compared against `whole` instead, which has them.
        seen = {off: key for off, key in journal if off < len(text)}
        marks = sorted(seen)
        held = max((len(k[0]) + len(k[1]) for _, k in journal), default=0)
        for cuts in schedules:
            step = max(1, len(marks) // cuts)
            product, at, worst = Organs(), 0, None
            for hi in [*marks[step::step], len(text)]:
                if hi <= at:
                    continue
                product = effect(engine, text, at, hi, product)
                at = hi
                want = seen[hi] if hi in seen else (whole.key() if hi == len(text) else None)
                if want is not None and product.key() != want:
                    worst = worst or (hi, product.key(), want)
            print(
                f"  {path.name}: {cuts:>4} cuts  "
                f"{'agrees' if worst is None else 'DISAGREES'}  "
                f"deepest state {held}"
            )
            if worst is not None:
                bad += 1
                print(f"      at {worst[0]}: {sight(text, worst[0])}")
                print(f"      whole   {worst[2]}")
                print(f"      product {worst[1]}")
    return bad


# ------------------------------------------------------------------------ main


def corpus_for(grammar: str) -> list:
    """Files to ask about, when a caller names none.

    The differential's corpus first, then a per-grammar fallback: the package's
    own tree, where markdown in particular is abundant, real, and adversarial in
    exactly the way hand-written specimens are not - nested lists inside block
    quotes, fenced blocks inside list items, tables, setext underlines.
    """
    kinds = suffixes(grammar)
    if not kinds:
        return []
    out = []
    for base in (CORPUS, SOURCES, *FALLBACK.get(grammar, ())):
        if not base.exists():
            continue
        for p in sorted(base.rglob("*")):
            if p.is_file() and p.suffix in kinds and ".local" not in p.parts:
                out.append(p)
    return out


#: Where else to look for a grammar's own language in this tree.
FALLBACK = {
    "markdown": (ROOT / "research", ROOT / "src", ROOT / "changelog.d"),
    "python": (ROOT / "tool",),
    "zig": (ROOT / "src",),
    # The specimens under `research/joinery/specimen/<lang>/` are the adversarial
    # half of these corpora - escaped quotes at a close, greedy `"""`, nested
    # interpolation, an unterminated string - and they were written against these
    # exact scanners. A transcription that agrees on one 966-line real file and
    # not on those has not been tested.
    "kotlin": (ROOT / "research",),
    "scala": (ROOT / "research",),
    "swift": (ROOT / "research",),
    "haskell": (ROOT / "research",),
    "html": (ROOT / "research",),
    "yaml": (ROOT / "research",),
    "elixir": (ROOT / "research",),
}


def suffixes(grammar: str) -> tuple:
    return {
        "markdown": (".md",),
        "kotlin": (".kt",),
        "yaml": (".yml", ".yaml"),
        "scala": (".scala",),
        "swift": (".swift",),
        "haskell": (".hs",),
        "html": (".html",),
        "elixir": (".ex", ".exs"),
        "python": (".py",),
    }.get(grammar, ())


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(prog="customary", description=__doc__)
    ap.add_argument("verb", choices=("check", "compose", "run", "verify"))
    ap.add_argument("grammar", nargs="?")
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--cuts", type=int, action="append", default=None)
    ap.add_argument("--loud", action="store_true", help="print more of each disagreement")
    ap.add_argument("--limit", type=int, default=0, help="how many corpus files to ask about")
    ap.add_argument("--quiet", action="store_true", help="totals only, no per-file rows")
    args = ap.parse_args(argv)

    if args.verb == "verify":
        books = sorted(BOOK.glob("*.json"))
        if not books:
            print("customary: no books under customary/")
            return 2
        for b in books:
            book = Book.load(b.stem)
            probes = len(book.probes)
            print(
                f"  {b.stem:<10} {len(book.rules):>3} rules · {probes} probes · "
                f"{len(book.kinds)} kinds · {len(book.cohort)} cohort"
            )
        return 0

    if not args.grammar:
        ap.error("check/compose/run need a grammar")
    book = Book.load(args.grammar)
    paths = args.files or corpus_for(args.grammar)
    paths = [p for p in paths if p.is_file()]
    if args.limit:
        # Evenly spread rather than the first N, so a limited run is a sample of
        # the corpus and not of whatever sorts first.
        step = max(1, len(paths) // args.limit)
        paths = paths[::step][: args.limit]
    if not paths:
        print(f"customary: no files for {args.grammar}")
        return 2

    if args.verb == "run":
        engine = Engine(book)
        for path in paths:
            hits, organs = engine.walk(read(path))
            print(f"{path}:")
            for h in hits:
                print(f"  {h}")
            print(f"  organs: {organs.key()}")
        return 0

    print(f"customary {args.verb}: {book.grammar}, {len(paths)} file(s)")
    if args.verb == "check":
        bad, tally, fenced, quiet_as = check(book, paths, loud=args.loud, quiet=args.quiet)
        if not bad and not any(tally[:3]):
            # `held` over nothing compared is the vacuous pass the module header
            # calls a kill, so it exits 2 - "could not be asked" - and says which
            # silence it is. The board is what gates these books until the harness
            # can see them; a count of zero should not have to be read as a hint.
            print(f"UNASKED: nothing was compared - {quiet_as.why()}")
            return 2
        if not bad:
            print(f"held: every answer agrees over {tally[0]} compared, "
                  f"asked at every offset")
            return 0
        if not any(fenced):
            # The residue is over-generation the parse table forbids, and the
            # envelope says so exactly rather than by argument. That is a pass:
            # this side does not have `valid_symbols`, and Rung 2 does.
            print(f"held under the permission envelope: {bad} file(s) over-generate "
                  f"where no parse table would have asked")
            return 0
        print(f"{bad} file(s) disagreed")
        return 1

    schedules = args.cuts or [2, 3, 7, 16, 64, 256]
    bad = compose(book, paths, schedules)
    print(f"{'composition held at every cut' if not bad else str(bad) + ' cut(s) disagreed'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
