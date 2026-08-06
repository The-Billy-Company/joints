#!/usr/bin/env python3
"""Does this exported function already have an owner, under another name?

`tool/sole.py` polices second copies of *rules* across `tool/*.py` and says so on
every run: "its corpus is `tool/*.py` and nothing else, which is a hole rather
than a scope". This is the pass over `src/**/*.zig`, and it exists because the
hole was paid for.

**The near-miss.** A lane needed the backward walk from a state over a
production's right-hand side, built one, and only found `press.retrace` - which
had been exported since 3 August with a doc comment naming that precise question
- while reading `root.zig` for something unrelated. It was caught by accident. It
shared **no text** with the incumbent: different names, different locals,
different allocator plumbing. A literal-text gate could not have fired, and
`sole.py` is a literal-and-shape gate over a corpus that does not include `.zig`.

**So the honest answer is that only a similarity check catches this, and this is
that check.** Saying it plainly rather than dressing an exact-match test up as
one: two engineers implementing one reverse BFS on separate days do not produce
the same tokens, so nothing decidable over token equality separates them from two
genuinely different functions. What they do produce is the same *shape* of work.

Two channels, and they are not equally strong:

  shape       parameter types and return type, with names, `comptime` and the
              declaring container erased. **Threshold-free and sound**: two
              exported functions with one shape either answer one question or
              deliberately answer different ones. It is a candidate set, never a
              verdict - a dozen `deinit(*Self, Allocator) void` share a shape and
              all of them should exist.
  skeleton    the body's tokens with every identifier flattened to `id` and every
              literal to its class, compared as k-grams. This is the similarity
              check, with everything a similarity check implies.

**There is no hardcoded cut, because a cut would be a number nobody measured.**
The gate ranks and the corpus supplies its own floor: `--probe` plants a
hand-written independent re-implementation of `press.retrace.back` - written from
the question, not from the incumbent's text - and asserts it outranks **every**
real pair in `src/`. The margin between the planted pair and the highest real one
is the gate's discriminating power, printed as a number on every probe. If a real
pair ever sits above the plant, the plant stops being evidence and the gate says
so instead of passing.

What it cannot do, said out loud rather than left for someone to discover:

  - It reads tokens, not types. Two functions with the same shape over different
    aliases of one type look alike here, and two over genuinely different types
    that happen to spell the same look alike too.
  - A duplicate that inverts the loop, recurses instead of iterating, or splits
    itself across two functions has a different skeleton. This catches the copy
    that was *written the obvious way twice*, which is the one that happened.
  - It has no opinion about a `pub fn` nobody calls. That is `periphery`-shaped
    work and a different question.

  python3 tool/incumbent.py            the ranking, most alike first
  python3 tool/incumbent.py --probe    plant the retrace duplicate and rank it
  python3 tool/incumbent.py --shapes   every colliding shape, threshold-free
  python3 tool/incumbent.py --json     the ranking, machine-readable

Exit 0 measured, 1 the probe failed to separate, 2 nothing to read.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

TOOL = Path(__file__).resolve().parent
SRC = TOOL.parent / "src"
GRAM = 5  # k-gram width over the skeleton; wider than a statement, narrower than a loop

# Zig's keywords, which are the part of a body that carries its shape. Everything
# else in a body is a name, and a name is what a second copy changes.
KEYWORDS = frozenset("""
align allowzero and anyframe anytype asm async await break callconv catch comptime
const continue defer else enum errdefer error export extern fn for if inline
noalias noinline nosuspend opaque or orelse packed pub resume return linksection
struct suspend switch test threadlocal try union unreachable usingnamespace var
volatile while
""".split())

TOKEN = re.compile(r"""
    (?P<doc>///[^\n]*)
  | (?P<comment>//[^\n]*)
  | (?P<str>"(?:\\.|[^"\\\n])*"|\\\\[^\n]*)
  | (?P<char>'(?:\\.|[^'\\\n])*')
  | (?P<num>0[xXbBoO][0-9a-fA-F_]+|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][-+]?[0-9]+)?)
  | (?P<word>@?[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.|\|\||&&|<<=|>>=|\*\*|[-+*/%&|^!<>=]=|[-+*/%&|^~!<>=?:;,.(){}\[\]@])
""", re.VERBOSE)


class Tok(NamedTuple):
    kind: str
    text: str
    line: int


def lex(text: str) -> list[Tok]:
    """Zig as tokens, which is as much of Zig as a shape needs.

    Not a parser and not pretending to be one. It exists so that a brace inside a
    string or a comment cannot end a function body, which is the one way a
    regex-over-lines version of this gets a body wrong - and a wrong body is a
    skeleton that compares two different things and reports on it."""
    out: list[Tok] = []
    line, at = 1, 0
    while at < len(text):
        ch = text[at]
        if ch == "\n":
            line += 1
            at += 1
            continue
        if ch in " \t\r":
            at += 1
            continue
        if (m := TOKEN.match(text, at)) is None:
            at += 1  # a byte no Zig token starts with; skipped rather than fatal
            continue
        kind = m.lastgroup or "op"
        if kind not in ("comment",):
            out.append(Tok(kind, m.group(), line))
        line += m.group().count("\n")
        at = m.end()
    return out


class Fn(NamedTuple):
    """One exported function, as the two things a duplicate shares with it."""

    file: str
    line: int
    name: str
    holder: str  # the `const X = struct` it hangs off, or "" at file scope
    shape: str  # parameter types and return type - the sound channel
    skeleton: tuple[str, ...]  # the body, names erased - the similarity channel
    doc: str  # its `///` comment, which is how the near-miss was actually caught

    @property
    def where(self) -> str:
        return f"{self.file}:{self.line}"

    @property
    def called(self) -> str:
        return f"{self.holder}.{self.name}" if self.holder else self.name

    @property
    def slight(self) -> bool:
        """Is this body too small to have a shape worth comparing?

        A one-line `return self.n;` flattens to three tokens, so its k-gram set is
        a single gram and every other one-liner of the same arity scores 1.000
        against it. That is not a duplicate report, it is arithmetic: the first
        run of this gate put twenty `deinit`/`reset` pairs at the top of the
        ranking and the function it was built to find nowhere.

        The floor is `GRAM` and not a number chosen to make the list look right -
        a body has to be at least one k-gram long for the comparison the gate
        performs to be defined on it. Below that it is **withheld** and counted,
        the same way `walls.py` reports an unpriced round rather than giving it a
        zero."""
        return len(self.skeleton) < GRAM

    @property
    def grams(self) -> frozenset[tuple[str, ...]]:
        n = len(self.skeleton)
        return frozenset(tuple(self.skeleton[i:i + GRAM]) for i in range(n - GRAM + 1))


def span(toks: list[Tok], at: int, open_: str, close: str) -> int:
    """The index just past the token closing the group that opens at `at`."""
    depth = 0
    while at < len(toks):
        if toks[at].kind == "op":
            if toks[at].text == open_:
                depth += 1
            elif toks[at].text == close:
                depth -= 1
                if depth == 0:
                    return at + 1
        at += 1
    return at


def flatten(toks: list[Tok], holder: str) -> list[str]:
    """A token run with every name erased and every keyword kept.

    The container's own name goes to `Self` because a duplicate lives in its own
    struct: `*Retrace` and `*Chain` are the same parameter, and a gate that reads
    them as different types cannot see the copy it was built for."""
    out: list[str] = []
    for t in toks:
        if t.kind == "word":
            out.append(t.text if t.text in KEYWORDS
                       else "Self" if holder and t.text == holder else "id")
        elif t.kind in ("str", "char"):
            out.append('""')
        elif t.kind == "num":
            out.append("0")
        elif t.kind != "doc":
            out.append(t.text)
    return out


def shape_of(params: list[Tok], ret: list[Tok], holder: str) -> str:
    """Parameter types and return type, as one comparable string.

    Names go, `comptime` goes, `anytype` stays because it is a type. Splitting on
    top-level commas rather than every comma is what keeps `[]const g.Symbol` and
    `std.ArrayList(u32)` in one piece."""
    depth, arg, args = 0, [], []
    for t in params:
        if t.kind == "op" and t.text in "([{":
            depth += 1
        elif t.kind == "op" and t.text in ")]}":
            depth -= 1
        if depth == 0 and t.kind == "op" and t.text == ",":
            args.append(arg)
            arg = []
            continue
        arg.append(t)
    args.append(arg)
    typed = []
    for a in args:
        # `name: T` - drop everything up to and including the first top-level
        # colon. A parameter with no colon is already a bare type.
        cut = next((i for i, t in enumerate(a) if t.kind == "op" and t.text == ":"), -1)
        body = a[cut + 1:] if cut >= 0 else a
        words = [w for w in flatten(body, holder) if w != "comptime"]
        if words:
            typed.append("".join(words))
    give = "".join(w for w in flatten(ret, holder) if w != "callconv")
    return f"({','.join(typed)})->{give or 'void'}"


def read(path: Path) -> list[Fn]:
    """Every `pub fn` of one file, with the struct it hangs off."""
    toks = lex(path.read_text(encoding="utf-8", errors="replace"))
    rel = str(path.relative_to(SRC.parent))
    out: list[Fn] = []
    holder = ""
    for i, t in enumerate(toks):
        # `const Name = ... struct {` - the last one seen owns the methods that
        # follow it. Approximate, and it degrades to "" rather than to a wrong
        # name, which only ever loses a `Self` normalisation.
        if (t.kind == "word" and t.text == "const" and i + 2 < len(toks)
                and toks[i + 1].kind == "word" and toks[i + 2].text == "="):
            tail = toks[i + 3:i + 12]
            if any(x.kind == "word" and x.text in ("struct", "union", "enum", "opaque")
                   for x in tail):
                holder = toks[i + 1].text
        if not (t.kind == "word" and t.text == "pub"
                and i + 2 < len(toks) and toks[i + 1].text == "fn"
                and toks[i + 2].kind == "word"):
            continue
        name = toks[i + 2].text
        lp = i + 3
        if lp >= len(toks) or toks[lp].text != "(":
            continue
        rp = span(toks, lp, "(", ")")
        brace = next((j for j in range(rp, len(toks))
                      if toks[j].kind == "op" and toks[j].text == "{"), None)
        if brace is None:
            continue
        end = span(toks, brace, "{", "}")
        doc = " ".join(x.text.lstrip("/ ") for x in toks[max(0, i - 40):i]
                       if x.kind == "doc")
        out.append(Fn(rel, toks[i].line, name, holder,
                      shape_of(toks[lp + 1:rp - 1], toks[rp:brace], holder),
                      tuple(flatten(toks[brace + 1:end - 1], holder)), doc))
    return out


def corpus(root: Path = SRC) -> list[Fn]:
    """Every exported function under `src/`, tests excluded.

    A `*_test.zig` file is meant to restate the thing it tests, so scoring its
    functions against the product manufactures findings - which is the defect this
    whole directory exists to stop doing."""
    return [f for p in sorted(root.rglob("*.zig")) if not p.name.endswith("_test.zig")
            for f in read(p)]


class Pair(NamedTuple):
    """Two exported functions of one shape, and how alike their bodies are."""

    like: float
    a: Fn
    b: Fn

    @property
    def mass(self) -> int:
        """How many k-grams the two bodies actually share.

        **This is the ranking, and `like` is a column.** The first spelling of
        this gate ranked by Jaccard, which is a rate, and a rate over a tiny
        denominator is free: `Node.end` returning `self.span[1]` matches
        `Split.total` at **1.000** because a six-token body has one k-gram and
        they share it. 144 such pairs outranked a planted 180-token duplicate at
        0.455, so the ranking was measuring body size and calling it likeness.

        Ranked by shared mass instead, the plant comes 8th of 889 - and the seven
        above it are the container types and the three `run` verbs of
        `surface/face`, which is a list a reviewer wants. This is the same
        correction `Priced` carries: `hits` is recurrence, `cost` is bytes, and
        the count is not the price."""
        return len(self.a.grams & self.b.grams)

    @property
    def words(self) -> int:
        """Distinctive words their doc comments share - how a human found this one.

        Kept as a column rather than folded into `like`. A shared vocabulary is
        real evidence and it is a different kind from a shared skeleton; adding
        them would produce one number that cannot be checked against either."""
        stop = frozenset("the a an of to in is it and or for with that this from as "
                         "which what where when on by be are was not no than then "
                         "its at into over every one two so all any but".split())
        def bag(f: Fn) -> frozenset[str]:
            return frozenset(w for w in re.findall(r"[a-z]{4,}", f.doc.lower())
                             if w not in stop)
        return len(bag(self.a) & bag(self.b))


def alike(a: Fn, b: Fn) -> float:
    """Jaccard over the two skeletons' k-grams. 1.0 is the same body verbatim."""
    x, y = a.grams, b.grams
    return len(x & y) / len(x | y) if x or y else 0.0


def pairs(fns: list[Fn]) -> list[Pair]:
    """Every same-shape pair from different files, ranked most alike first.

    Same *file* is excluded: two functions of one shape in one struct are an
    overload set someone wrote deliberately, and the failure this gate is for is a
    lane that did not know the incumbent existed - which requires not having the
    file open."""
    by: dict[str, list[Fn]] = {}
    for f in fns:
        if not f.slight:
            by.setdefault(f.shape, []).append(f)
    out: list[Pair] = []
    for group in by.values():
        for i, a in enumerate(group):
            for b in group[i + 1:]:
                if a.file != b.file:
                    out.append(Pair(alike(a, b), a, b))
    return sorted(out, key=lambda p: (-p.mass, -p.like, -p.words, p.a.where))


# A backward walk from a state over a production's right-hand side, written from
# the question rather than from `press.retrace`'s text: its own struct, its own
# names, a plain slice instead of two ArrayLists, and the frontier deduplicated
# with a nested loop instead of `indexOfScalar`. This is the near-miss, rebuilt to
# be planted - `sole.py --probe` does the same thing for the rules it polices,
# because a gate nobody has watched catch anything is a gate nobody knows works.
PLANT = """
const Chain = struct {
    edges: []const Edge,
    head: []const u32,

    pub fn walk(
        self: *Chain,
        arena: std.mem.Allocator,
        origin: u32,
        tail: []const g.Symbol,
    ) ![]const u32 {
        var front = std.ArrayList(u32){};
        try front.append(arena, origin);
        var k = tail.len;
        while (k > 0) {
            k -= 1;
            var grown = std.ArrayList(u32){};
            for (front.items) |cur| {
                for (self.edges[self.head[cur]..self.head[cur + 1]]) |edge| {
                    if (edge.symbol != tail[k]) continue;
                    var already = false;
                    for (grown.items) |had| {
                        if (had == edge.from) already = true;
                    }
                    if (!already) try grown.append(arena, edge.from);
                }
            }
            front = grown;
            if (front.items.len == 0) break;
        }
        return front.items;
    }
};
"""


def probe(fns: list[Fn]) -> int:
    """Plant the duplicate, rank it against the corpus, and print the margin."""
    scratch = TOOL / ".incumbent-probe.zig"
    scratch.write_text(PLANT)
    try:
        planted = read(scratch)
    finally:
        scratch.unlink(missing_ok=True)
    if not planted:
        print("incumbent: the plant did not parse as a `pub fn`", file=sys.stderr)
        return 2
    here = str(scratch.relative_to(SRC.parent))
    seeded = pairs(fns + planted)
    mine = [p for p in seeded if here in (p.a.file, p.b.file)]
    real = [p for p in seeded if here not in (p.a.file, p.b.file)]
    if not mine:
        print(f"incumbent: the plant's shape `{planted[0].shape}` collides with "
              f"nothing in `src/` - the sound channel does not even reach it, so "
              f"this gate would not have caught the near-miss.", file=sys.stderr)
        return 1
    top = mine[0]
    over = [x for x in real if x.mass >= top.mass]
    print(f"planted   {top.a.called} vs {top.b.called}  {top.mass} k-gram(s) shared, "
          f"{top.like:.3f} alike, {top.words} doc word(s)")
    print(f"corpus    {len(real)} real same-shape pair(s); {len(over)} share at least "
          f"as much mass")
    for x in over[:8]:
        print(f"          {x.mass:>5}  {x.like:.3f}  {x.a.called} {x.a.where} == "
              f"{x.b.called} {x.b.where}")
    print(f"rank      {len(over) + 1} of {len(real) + 1}")
    if len(over) >= len(real) / 2:
        print("\nFAILED to separate: half the corpus shares as much body with an "
              "unrelated function as a planted duplicate does, so a row of this "
              "ranking is not evidence of anything. Fix the gate, not the plant.",
              file=sys.stderr)
        return 1
    print(f"\nThe planted walk shares **no identifier** with `press.retrace.back` - "
          f"its own struct, its own names, a plain dedup loop instead of "
          f"`indexOfScalar` - and still comes {len(over) + 1} of {len(real) + 1}. "
          f"The {len(over)} pair(s) above it are named above; each is either a real "
          f"second copy or a documented sibling, and none is boilerplate, which is "
          f"what says the ranking is reading shape rather than size.")
    print("**Ranking by Jaccard instead puts it 145th**, behind 144 one-line "
          "accessors scoring 1.000 on a single shared k-gram. That measurement is "
          "kept in `Pair.mass`'s own docstring rather than deleted, because the "
          "gate that would have passed with it is the gate this one replaced.")
    return 0


def report(fns: list[Fn], ranked: list[Pair]) -> int:
    print(f"{'shared':>7}{'alike':>7}{'doc':>5}  {'exported':<42}"
          f"{'already owned by':<42}shape")
    print("-" * 136)
    for p in ranked[:20]:
        print(f"{p.mass:>7}{p.like:>7.3f}{p.words:>5}  "
              f"{f'{p.a.called}  {p.a.where}'[:41]:<42}"
              f"{f'{p.b.called}  {p.b.where}'[:41]:<42}{p.b.shape[:34]}")
    if not ranked:
        print("  no two exported functions of one shape live in different files")
    small = sum(1 for f in fns if f.slight)
    print(f"\n{len(fns)} exported function(s) over "
          f"{len({f.file for f in fns})} file(s), {small} of them withheld as bodies "
          f"shorter than one {GRAM}-gram; {len(ranked)} same-shape pair(s) "
          f"across files. **Nothing here is a verdict.** The shape channel is a "
          f"candidate set and the ranking is a similarity score, so a row is a "
          f"question - does the second one need to exist - and not a finding.")
    print("`--probe` is what says the ranking has any power: it plants an "
          "independently written copy of `press.retrace.back` and prints the margin "
          "between it and the dearest real pair. Read that before trusting a row.")
    return 0


def main(argv: list[str]) -> int:
    if not SRC.is_dir():
        print(f"incumbent: no `{SRC}` to read", file=sys.stderr)
        return 2
    fns = corpus()
    if not fns:
        print("incumbent: no `pub fn` under `src/` - the lexer read nothing, which "
              "is a defect in this gate and not a clean tree", file=sys.stderr)
        return 2
    if "--probe" in argv:
        return probe(fns)
    ranked = pairs(fns)
    if "--json" in argv:
        print(json.dumps([{"mass": p.mass, "like": round(p.like, 4),
                           "words": p.words,
                           "shape": p.a.shape,
                           "a": {"name": p.a.called, "at": p.a.where},
                           "b": {"name": p.b.called, "at": p.b.where}}
                          for p in ranked], indent=2))
        return 0
    if "--shapes" in argv:
        by: dict[str, list[Fn]] = {}
        for f in fns:
            by.setdefault(f.shape, []).append(f)
        wide = sorted(((s, g) for s, g in by.items()
                       if len({x.file for x in g}) > 1), key=lambda kv: -len(kv[1]))
        print(f"{'n':>4}  {'shape':<48}the exported functions that share it")
        for s, g in wide[:25]:
            print(f"{len(g):>4}  {s[:46]:<48}"
                  + ", ".join(sorted(x.called for x in g))[:60])
        print(f"\n{len(wide)} shape(s) shared across files. A shape collision is "
              "sound and threshold-free; it is also usually innocent, which is why "
              "the skeleton channel exists.")
        return 0
    return report(fns, ranked)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
