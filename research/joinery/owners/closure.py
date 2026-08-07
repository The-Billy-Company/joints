#!/usr/bin/env python3
"""The grammar side of the ownership question: what can this position take?

`research/joinery/verilog/reach.py` answered it for six walls by handing the
closure a **governing nonterminal picked by hand** off a one-line witness. That
does not scale to 181 walls in 18 grammars, and hand-picking 181 positions is
181 chances to pick the position that makes the verdict come out the way I
expected.

So the position comes off the wall's own LR state instead — `joints state
<grammar> <n>` prints the items, and an item `A -> alpha . beta` says exactly
what this position can still consume. Which turns the closure into the textbook
question it always was:

  **viable(state) = FIRST(beta) over every item, plus FOLLOW(A) for every item
  whose beta can vanish.** That is the LR(1) viability set. A terminal outside
  it is a terminal *no* LR parser over this grammar accepts in this state, under
  any lookahead, after any sequence of reductions - an impossibility argument in
  the strict sense rather than a measurement.

Two things this file does that `reach.py` did not have to:

**It names terminals the way the press does.** `reach.py` only ever walked
`SYMBOL` nodes, because every target it was handed was a rule name. A wall names
the terminal that was *refused*, and the press spells those as the literal
itself (`;`) or as the rendered regex (`(?:[^\\"\n]+)`) - so the atoms have to
be walked too, and rendered the way `src/press/lexeme.zig` renders them. Where
the spelling is uncertain a terminal contributes **both** candidate names, which
over-approximates FIRST and therefore biases every verdict toward `conflict`.
That is the safe direction: a `gap` is the claim that goes out to the
competitive lane, so a gap has to survive a generous reading of the grammar.

**It knows an external has no derivation on purpose.** Twenty-three of the
thirty vendored grammars declare `externals`, and an external has no rule body
at all - so a closure run naively over `rules` finds no derivation for it and
would report every wall in front of one as a grammar gap. It is the opposite:
tree-sitter runs the C scanner and parses the construct fine. `declared()` is
that list, and callers are expected to route those walls away from this file's
question rather than answer it. **Every shape of declaration counts** - a
grammar may declare an external as a literal or as a pattern instead of as a
named symbol, and reading only the named shape drops 23 declarations across 9
grammars (31 spellings, since an atom answers to both its literal and its
escaped render). One of them, bash's `]`, was published as a grammar gap worth
495 bytes.

Nothing here parses, runs tree-sitter, or consults an oracle. It reads one JSON
file.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
GRAMMARS = ROOT / "upstream" / "grammars"

END = "$"  # end of input, seeded into FOLLOW(start)
# Nodes that shape the tree or the tables and never the bytes, so a name is
# whatever they wrap. Mirrors `lexeme.isWrapper` plus the metadata wrappers.
WRAPPERS = frozenset({
    "TOKEN", "IMMEDIATE_TOKEN", "ALIAS", "FIELD", "PREC", "PREC_LEFT",
    "PREC_RIGHT", "PREC_DYNAMIC",
})
HEX = re.compile(r"^[0-9A-Fa-f]+$")


def transcribe(value: str) -> str:
    """`\\uXXXX` and `\\u{...}` into the engine's `\\x{...}`, everything else
    verbatim. A byte-for-byte port of `lexeme.transcribe`, digits copied rather
    than reparsed - `\\x{00A2}` and `\\x{A2}` are the same codepoint and a
    translation that normalizes is one that can be wrong about a number."""
    out, i = [], 0
    while i < len(value):
        if value[i] != "\\" or i + 1 == len(value):
            out.append(value[i])
            i += 1
        elif value[i + 1] != "u":
            out.append(value[i:i + 2])
            i += 2
        elif (body := codepoint(value[i + 2:])) is None:
            out.append(value[i:i + 2])
            i += 2
        else:
            out.append(f"\\x{{{body[0]}}}")
            i += 2 + body[1]
    return "".join(out)


def codepoint(rest: str) -> tuple[str, int] | None:
    """The codepoint body just past a `\\u`: four bare hex digits, or braces."""
    if rest.startswith("{"):
        if (close := rest.find("}")) < 0 or not HEX.match(hexes := rest[1:close]):
            return None
        return hexes, close + 1
    return (rest[:4], 4) if len(rest) >= 4 and HEX.match(rest[:4]) else None


def render(node: dict | list | None) -> str | None:
    """The regex the press would compile this node into, or None when the node
    reaches something no regex can stand in for - a `SYMBOL`, which is how a
    `token($.rule)` and every external come back unrenderable."""
    if not isinstance(node, dict):
        return None
    kind = node.get("type")
    if kind == "STRING":
        return escape(node.get("value", ""))
    if kind == "PATTERN":
        flags = node.get("flags") or ""
        return f"(?{flags}:{transcribe(node.get('value', ''))})" if flags else \
            f"(?:{transcribe(node.get('value', ''))})"
    if kind == "BLANK":
        return ""
    if kind in WRAPPERS:
        return render(node.get("content"))
    if kind == "CHOICE":
        parts = [render(m) for m in node.get("members", [])]
        return None if any(p is None for p in parts) else f"(?:{'|'.join(parts)})"
    if kind == "SEQ":
        parts = [render(m) for m in node.get("members", [])]
        return None if any(p is None for p in parts) else "".join(parts)
    if kind in ("REPEAT", "REPEAT1"):
        inner = render(node.get("content"))
        return None if inner is None else f"(?:{inner}){'*' if kind == 'REPEAT' else '+'}"
    return None


def escape(text: str) -> str:
    """A literal written so a regex engine reads it as those exact bytes."""
    return "".join("\\" + c if c in "\\^$.|?*+()[]{}" else c for c in text)


def names(node: dict) -> tuple[str, ...]:
    """Every spelling the press might give this atom, most-likely first.

    Two rather than one, and deliberately. A bare `STRING` is interned under its
    literal value - the row prints `;` and `virtual`, not `\\;` - while anything
    composite is interned under its rendered regex. Which of the two a
    `token("foo")` gets is a question about `muster` this file has no business
    asserting, so it contributes both and the bridge matches whichever the row
    actually printed. The cost is a slightly wider FIRST set, which can only
    turn a `gap` into a `conflict` and never the other way.
    """
    inner = node
    while isinstance(inner, dict) and inner.get("type") in WRAPPERS:
        inner = inner.get("content")
    out = []
    if isinstance(inner, dict) and inner.get("type") == "STRING":
        out.append(inner.get("value", ""))
    if (drawn := render(node)) is not None and drawn not in out:
        out.append(drawn)
    return tuple(out)


class Grammar(NamedTuple):
    """One vendored grammar, flattened into productions and analysed.

    `prods` is over a symbol space that is the union of three things: the
    grammar's own rule names, one synthetic `@n` per nested node (so a `seq` of
    five `choice`es costs five symbols instead of 1,024 alternatives), and every
    terminal spelling `names()` produced. A symbol with no production is a
    terminal, which is the only definition of terminal used here.
    """

    name: str
    rules: dict          # the grammar's own rules, by name
    start: str
    prods: dict[str, list[tuple[str, ...]]]
    nullable: frozenset[str]
    first: dict[str, frozenset[str]]
    follow: dict[str, frozenset[str]]
    terminals: frozenset[str]
    blind: frozenset[str]   # declared externals, named and literal: no rule body ever
    extras: frozenset[str]  # admitted almost everywhere, so they discriminate nothing
    lists: dict[str, frozenset[str]]  # rule -> FIRST of the repeats inside it
    kin: dict[str, frozenset[str]]  # spelling -> every spelling of the same atom

    def spellings(self, sym: str) -> frozenset[str]:
        """Every name one atom might answer to, so a membership test cannot fail
        on orthography. `names()` hands a production one symbol per position -
        the literal - while the press may have interned the rendered regex, and a
        bridge that missed on that difference would report a terminal the grammar
        holds as having no derivation. Which is this project's whole failure
        genre, so the two spellings are joined rather than chosen between."""
        return self.kin.get(sym, frozenset({sym}))

    def firstof(self, syms: tuple[str, ...]) -> frozenset[str]:
        """FIRST of a sequence: each symbol's FIRST until one cannot vanish."""
        out: set[str] = set()
        for s in syms:
            out |= self.first.get(s, frozenset({s}))
            if s not in self.nullable:
                return frozenset(out)
        return frozenset(out)

    def vanishes(self, syms: tuple[str, ...]) -> bool:
        return all(s in self.nullable for s in syms)

    def known(self, sym: str) -> bool:
        """Is this press name something this grammar can speak about at all?

        The residue matters more than the answer: a press symbol nothing here
        recognises is a bridge failure, and a bridge failure that gets counted
        as `no derivation exists` is the whole class of lie this project keeps
        catching. Callers report it as unplaced rather than as a gap.
        """
        return (sym in self.prods or sym in self.terminals or sym in self.blind
                or sym in self.rules or self.listrule(sym) is not None)

    def listrule(self, sym: str) -> str | None:
        """`X_repeat27` -> `X`, when `X` is a rule that really holds a repeat.

        `spread.listSymbol` mints these, shares one body across every host with
        the same body, and lets **the first host name it** - so the name is a
        true statement about where that body first appeared and not necessarily
        about this instance. Looking inside the named host is therefore right up
        to which repeat, and when a rule holds several this over-approximates
        within that one rule. Bounded, and in the conflict-ward direction.
        """
        if (cut := sym.rfind("_repeat")) < 0 or not sym[cut + 7:].isdigit():
            return None
        return owner if (owner := sym[:cut]) in self.lists else None

    def spread(self, sym: str) -> frozenset[str]:
        """FIRST of one press symbol, resolving a minted list to its host."""
        if sym in self.first:
            return self.first[sym]
        if (owner := self.listrule(sym)) is not None:
            return self.lists[owner]
        return frozenset({sym})


def walk(node, rules: dict, prods: dict, mint) -> tuple[str, ...]:
    """One node into the sequence of symbols it stands for, minting synthetic
    nonterminals for the nested structure rather than expanding it.

    Expanding instead is the version that does not survive verilog: a `seq` of
    five `choice`es of four members is 1,024 alternatives written out, and
    `verilog.json` has 704 rules of them."""
    if not isinstance(node, dict):
        return ()
    kind = node.get("type")
    if kind == "SYMBOL":
        return (node["name"],)
    if kind == "BLANK":
        return ()
    if kind in WRAPPERS:
        # A `token(...)` is one terminal to the press even when its insides are
        # composite, so it never becomes productions. `alias`/`field`/`prec` are
        # transparent and do.
        if kind in ("TOKEN", "IMMEDIATE_TOKEN"):
            # Unrenderable (`token($.rule)`) falls through to the content, which
            # widens FIRST rather than dropping the position - the press turns
            # that node into an unlexable terminal, and a missing FIRST entry
            # would read as `no derivation exists`.
            got = names(node)
            return (got[0],) if got else walk(node.get("content"), rules, prods, mint)
        return walk(node.get("content"), rules, prods, mint)
    if kind in ("STRING", "PATTERN"):
        got = names(node)
        return (got[0],) if got else ()
    if kind == "SEQ":
        out: list[str] = []
        for m in node.get("members", []):
            out.extend(walk(m, rules, prods, mint))
        return tuple(out)
    if kind == "CHOICE":
        me = mint()
        prods[me] = [walk(m, rules, prods, mint) for m in node.get("members", [])]
        return (me,)
    if kind in ("REPEAT", "REPEAT1"):
        me = mint()
        body = walk(node.get("content"), rules, prods, mint)
        prods[me] = [body, (me,) + body] if kind == "REPEAT1" else [(), (me,) + body]
        return (me,)
    return ()


def alias(node, into: set[str]) -> None:
    """Every terminal spelling anywhere under `node`, for the terminal census.

    Separate from `walk` because `walk` takes only the *first* candidate name
    into a production - a production needs one symbol per position - while the
    bridge has to recognise either spelling. Both names go in the census; one
    goes in the grammar.
    """
    if isinstance(node, list):
        for x in node:
            alias(x, into)
    elif isinstance(node, dict):
        if node.get("type") in ("STRING", "PATTERN") or node.get("type") in WRAPPERS:
            into.update(names(node))
        for k, v in node.items():
            if k != "name":
                alias(v, into)


def sibling(node, into: list[tuple[str, ...]]) -> None:
    """Every atom that has more than one possible spelling, as one group each."""
    if isinstance(node, list):
        for x in node:
            sibling(x, into)
    elif isinstance(node, dict):
        if len(got := names(node)) > 1:
            into.append(got)
        for k, v in node.items():
            if k != "name":
                sibling(v, into)


def repeats(body, into: set[str], rules: dict, prods: dict, mint) -> None:
    """The symbols every repeat inside one rule can start with."""
    if isinstance(body, list):
        for x in body:
            repeats(x, into, rules, prods, mint)
    elif isinstance(body, dict):
        if body.get("type") in ("REPEAT", "REPEAT1"):
            into.update(walk(body.get("content"), rules, prods, mint))
        for k, v in body.items():
            if k != "name":
                repeats(v, into, rules, prods, mint)


def declared(g: dict, literals: bool = True) -> set[str]:
    """Every spelling of every declared `external`, both shapes it comes in.

    Tree-sitter lets a grammar declare an external as a **literal** or as a
    **pattern** rather than as a named symbol; those carry `"type": "STRING"` or
    `"type": "PATTERN"` with a `value` and no `name`. Reading only the `SYMBOL`
    shape drops 23 declarations across 9 grammars - bash's `]`, `}`, `(`,
    `esac`, `<<`, `<<-` and its `\\n`; scala's six keywords; python's three
    closers and `except`; haskell's `\\n`; html's `/>`; ocaml's `"`; ruby's `/`;
    `||` in each of javascript and typescript - and one of them, bash's `]`, is
    a wall the board reported as a grammar gap for 495 bytes. A declaration is a
    declaration whichever shape it is written in.

    **Declarations and spellings are different units and the difference bit this
    docstring.** Those 23 declarations are 31 spellings, because an atom answers
    both to its literal and to its escaped render (`]` and `\\]`), and `--externals`
    counts spellings. An earlier revision of this paragraph read `21 across 8`,
    which is neither: it is the count under the `("SYMBOL", "STRING")` filter
    refused two paragraphs down, quoted as if it described the live population.

    A literal contributes `names()` rather than its bare value, for the same
    reason every other terminal here does: the press may have interned the
    escaped render (`\\]`) instead of the literal (`]`), and a membership test
    that missed on orthography is the exact failure this bridge exists to stop.
    `spellings()` joins the two wherever a rule body also mentions the atom -
    but nothing guarantees a rule body does, and an external declared and never
    written literally is precisely the case where it would not.

    **Not an enumeration of the shapes I have seen.** The dossier that found
    this proposed `type in ("SYMBOL", "STRING")`, which still drops the two
    `PATTERN` externals the corpus holds - bash's and haskell's `\\n`, each in a
    grammar that has walls. Listing the shapes someone has already met is how
    the first spelling of this line got it wrong, and `walls.family` was fixed
    for the same defect one directory over. So: a `SYMBOL` answers to its name
    and **everything else answers to `names()`**, which is total over the node
    kinds `render()` knows and contributes nothing for one it does not.

    Totality here is worth **0 bytes on today's board**, and that is the honest
    price rather than an argument against it. Neither `\\n` is the terminal of
    any of the 170 walls, and no walled terminal's `spellings()` reaches one, so
    the `("SYMBOL", "STRING")` filter would move no verdict - measured over the
    whole survey through `kin`, which is what `verdict()` actually tests, not by
    reading terminal names. The shape is right on the argument that a
    declaration is a declaration; it is not right because it paid this time.
    Bash's `]` is what the same argument was worth when it did pay.

    `literals=False` reconstructs the narrow set, so the counterfactual stays
    runnable rather than being a paragraph in a dossier: see `owners.py
    --externals`.
    """
    out: set[str] = set()
    for e in g.get("externals") or ():
        if not isinstance(e, dict):
            continue
        if e.get("type") == "SYMBOL":
            out.update({e["name"]} if "name" in e else ())
        elif literals:
            out.update(names(e))
    return out


def load(name: str, literals: bool = True) -> Grammar:
    """Flatten one vendored grammar and analyse it. Pure; no binary involved."""
    g = json.loads((GRAMMARS / f"{name}.json").read_text())
    rules: dict = g["rules"]
    prods: dict[str, list[tuple[str, ...]]] = {}
    seq = [0]

    def mint() -> str:
        seq[0] += 1
        return f"@{seq[0]}"

    for rule, body in rules.items():
        alts = body.get("members") if isinstance(body, dict) and body.get("type") == "CHOICE" else None
        prods[rule] = [walk(m, rules, prods, mint) for m in alts] if alts else \
            [walk(body, rules, prods, mint)]

    # Terminal census, over rule bodies and the two lists that live outside them.
    census: set[str] = set()
    for body in rules.values():
        alias(body, census)
    for entry in g.get("extras") or []:
        alias(entry, census)
    for entry in g.get("externals") or []:
        alias(entry, census)

    blind = frozenset(declared(g, literals))
    extras: set[str] = set()
    for entry in g.get("extras") or []:
        if isinstance(entry, dict) and entry.get("type") == "SYMBOL":
            extras.add(entry["name"])
        else:
            extras.update(names(entry) if isinstance(entry, dict) else ())

    # A repeat's FIRST, per host rule, for the `X_repeatN` bridge. Computed off
    # the same `walk`, so the minted symbols it needs land in `prods` too.
    lists: dict[str, set[str]] = {}
    for rule, body in rules.items():
        got: set[str] = set()
        repeats(body, got, rules, prods, mint)
        if got:
            lists[rule] = got

    terminals = frozenset(
        s for s in (census | blind | {s for alt in prods.values() for a in alt for s in a})
        if s not in prods)
    start = next(iter(rules))

    pairs: list[tuple[str, ...]] = []
    for body in rules.values():
        sibling(body, pairs)
    # A rule whose whole body is one atom **is a terminal to the press**, and the
    # press names it after the rule: sql's `keyword_select` is a table cell, while
    # here it is a nonterminal producing `(?:[sS][eE][lL][eE][cC][tT])`. Nothing
    # in the two names hints they are the same thing, so the bridge missed 26 of
    # the 27 terminals sql's start state admits and the grammar's control read 6%.
    # Joining them is what a rule of that shape means.
    for rule, alts in prods.items():
        if not rule.startswith("@") and len(alts) == 1 and len(alts[0]) == 1 \
                and alts[0][0] not in prods:
            pairs.append((rule, alts[0][0]))
    kin: dict[str, set[str]] = {}
    for group in pairs:
        joined = set(group)
        for s in group:
            joined |= kin.get(s, set())
        for s in joined:
            kin[s] = joined

    nullable = _nullable(prods)
    first = _first(prods, nullable, terminals)
    follow = _follow(prods, nullable, first, start)
    return Grammar(
        name=name, rules=rules, start=start, prods=prods, nullable=nullable,
        first=first, follow=follow, terminals=terminals, blind=blind,
        extras=frozenset(extras),
        lists={k: frozenset(s for x in v for s in first.get(x, {x})) for k, v in lists.items()},
        kin={k: frozenset(v) for k, v in kin.items()},
    )


def _nullable(prods: dict) -> frozenset[str]:
    out: set[str] = set()
    while True:
        grew = False
        for lhs, alts in prods.items():
            if lhs in out:
                continue
            if any(all(s in out for s in alt) for alt in alts):
                out.add(lhs)
                grew = True
        if not grew:
            return frozenset(out)


def _first(prods: dict, nullable: frozenset[str], terminals: frozenset[str]) -> dict[str, frozenset[str]]:
    first: dict[str, set[str]] = {t: {t} for t in terminals}
    for lhs in prods:
        first.setdefault(lhs, set())
    while True:
        grew = False
        for lhs, alts in prods.items():
            for alt in alts:
                for s in alt:
                    before = len(first[lhs])
                    first[lhs] |= first.get(s, {s})
                    grew |= len(first[lhs]) != before
                    if s not in nullable:
                        break
        if not grew:
            return {k: frozenset(v) for k, v in first.items()}


def _follow(prods: dict, nullable: frozenset[str], first: dict, start: str) -> dict[str, frozenset[str]]:
    follow: dict[str, set[str]] = {lhs: set() for lhs in prods}
    follow[start].add(END)
    while True:
        grew = False
        for lhs, alts in prods.items():
            for alt in alts:
                for i, s in enumerate(alt):
                    if s not in follow:
                        continue
                    rest = alt[i + 1:]
                    add: set[str] = set()
                    for nxt in rest:
                        add |= first.get(nxt, {nxt})
                        if nxt not in nullable:
                            break
                    else:
                        add |= follow[lhs]
                    before = len(follow[s])
                    follow[s] |= add
                    grew |= len(follow[s]) != before
        if not grew:
            return {k: frozenset(v) for k, v in follow.items()}
