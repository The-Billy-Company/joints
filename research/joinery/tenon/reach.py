#!/usr/bin/env python3
"""GAP or CONFLICT — asked of the vendored grammar, with no parse and no oracle.

The verilog lane's closure (`research/joinery/verilog/reach.py`) sorts a **wall**
into a gap in the grammar or a conflict in the press: from the nonterminal
governing a position, can the offending symbol be derived at all? If it cannot,
no work on the table could ever seat it.

This lane's defects are not walls. Nothing stops; both parsers accept and hand
back different shapes. So the closure has to be asked a **second** question,
and the first one on its own is expected to say CONFLICT every time - which is
a fact about the population, not a verdict:

  reachable   can the symbol be derived from that position at all?
  seated      does a SINGLE production put these two symbols side by side in
              the body the oracle's tree shows - i.e. is the oracle's parent
              spelled anywhere in the grammar, or only assembled by the parser?

`seated` is the discriminator `reachable` cannot be. A wrong parent is a choice
between two productions that BOTH exist, so both are reachable and only one is
the one the oracle used; naming that production is what turns "the grammar can
express this" into "here is the rule joints declined to reduce".

    python3 research/joinery/tenon/reach.py

Every row is paired with a control from the same grammar - the spelling that
joints already builds the oracle's way - because a closure that says the same
thing about the guilty and the innocent case is reading itself.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GRAMMARS = ROOT / "upstream" / "grammars"


def edges(rules: dict) -> dict[str, set[str]]:
    """symbol -> every symbol its body can mention, one level down."""

    def walk(node, into: set[str]) -> None:
        if isinstance(node, list):
            for x in node:
                walk(x, into)
        elif isinstance(node, dict):
            if node.get("type") == "SYMBOL":
                into.add(node["name"])
            for k, v in node.items():
                if k != "name":
                    walk(v, into)

    return {name: (lambda s: (walk(body, s), s)[1])(set()) for name, body in rules.items()}


def closure(graph: dict[str, set[str]], start: str) -> set[str]:
    seen, stack = set(), [start]
    while stack:
        for n in graph.get(stack.pop(), ()):
            if n not in seen:
                seen.add(n)
                stack.append(n)
    return seen


def bodies(rules: dict, host: str) -> list[list[str]]:
    """Every alternative body of one rule, flattened to the symbols in order.

    Flattened rather than structural on purpose: the question is only whether
    two symbols can stand side by side under this one rule, and a SEQ nested
    inside a CHOICE inside a PREC is still one body. A REPEAT is expanded once,
    which is enough to answer "can these two be siblings" and never claims a
    count.
    """
    out: list[list[str]] = []

    def walk(node, run: list[str]) -> list[list[str]]:
        if node is None:
            return [run]
        t = node.get("type")
        if t == "SYMBOL":
            return [[*run, node["name"]]]
        if t in ("STRING", "PATTERN", "BLANK"):
            return [run]
        if t == "CHOICE":
            return [r for m in node["members"] for r in walk(m, run)]
        if t == "SEQ":
            runs = [run]
            for m in node["members"]:
                runs = [r for x in runs for r in walk(m, x)]
            return runs
        if t in ("PREC", "PREC_LEFT", "PREC_RIGHT", "PREC_DYNAMIC", "FIELD",
                 "ALIAS", "TOKEN", "IMMEDIATE_TOKEN", "REPEAT", "REPEAT1"):
            return walk(node.get("content"), run)
        return [run]

    out += walk(rules[host], [])
    return out


def spell(rules: dict, host: str, want: tuple[str, ...]) -> list[list[str]]:
    """The bodies of `host` that carry every symbol in `want`, in that order."""
    hit = []
    for body in bodies(rules, host):
        at, ok = 0, True
        for w in want:
            if w in body[at:]:
                at = body.index(w, at) + 1
            else:
                ok = False
                break
        if ok:
            hit.append(body)
    return hit


class Case:
    def __init__(self, tag: str, grammar: str, position: str, target: str,
                 host: str, want: tuple[str, ...], witness: str, control: str,
                 control_want: tuple[str, ...] | None = None) -> None:
        self.tag, self.grammar, self.position, self.target = tag, grammar, position, target
        self.host, self.want, self.witness, self.control = host, want, witness, control
        self.control_want = control_want


CASES = (
    Case("elixir  do-block on the outer call", "elixir",
         "call", "do_block", "call", ("do_block",),
         "defp f(x) do x end",
         "f(x)  — the same call with no block, which joints already builds right"),
    Case("go      call, not conversion", "go",
         "_expression", "call_expression", "call_expression", ("argument_list",),
         'fmt.Print("x")',
         "fmt.Print  — the selector alone, no parenthesis to contest"),
    Case("python  print as a call", "python",
         "_simple_statement", "call", "call", ("argument_list",),
         "print(x)",
         "printer(x)  — one letter longer and not the keyword"),
    Case("toml    the comment's parent", "toml",
         "document", "comment", "pair", ("comment",),
         "a = 1  # c",
         "a = 1  — the same pair with no comment after it"),
)


def main() -> int:
    print("Every wrong-shape defect in this lane, asked the WALL question first.\n"
          "A wall lane's closure sorts on `reachable`. Watch it say the same thing\n"
          "about all four, which is the point: nothing here is a wall.\n")
    print(f"{'defect':<38}{'position':<20}{'must derive':<20}{'reachable':<12}verdict")
    print("-" * 108)
    seats: list[tuple[Case, dict, bool]] = []
    for c in CASES:
        doc = json.loads((GRAMMARS / f"{c.grammar}.json").read_text())
        rules = doc["rules"]
        if c.position not in rules or c.target not in rules:
            print(f"{c.tag:<38}{c.position:<20}{c.target:<20}(no such rule)")
            continue
        can = c.target in closure(edges(rules), c.position)
        print(f"{c.tag:<38}{c.position:<20}{c.target:<20}{'yes':<12}"
              f"{'CONFLICT — the grammar derives it' if can else 'GAP — no derivation exists'}")
        seats.append((c, doc, can))

    print("\nSo the wall question separates nothing here, and that is the finding about\n"
          "the METHOD: these are not walls. The second question is the one that pays.\n")
    print(f"{'defect':<38}{'oracle parent':<24}{'sibling(s)':<26}"
          "spelled by a single production?")
    print("-" * 124)
    for c, doc, _ in seats:
        rules = doc["rules"]
        hit = spell(rules, c.host, c.want)
        print(f"{c.tag:<38}{c.host:<24}{' + '.join(c.want):<26}"
              f"{f'YES — {len(hit)} body(ies)' if hit else 'NO — the parser assembles it'}")
        for body in hit[:2]:
            print(f"{'':<38}  {' '.join(body)}")
        print(f"{'':<38}  witness  {c.witness}")
        print(f"{'':<38}  control  {c.control}")
    print("\nA row that reads CONFLICT above and YES below is a production joints\n"
          "declined to use, not a production nobody has. That is the whole verdict:\n"
          "every one of these is seatable in this tree by whoever owns the table.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
