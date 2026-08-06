#!/usr/bin/env python3
"""Is each named wall a **gap** in the grammar or a **conflict** in the press?

Six walls on `picorv32.v` are now named to a single line of verilog each. That
says where each stops, and says nothing about whose defect it is - and the two
answers have different owners, different fixes, and wildly different costs. A
`press` that cannot resolve an ambiguity the grammar *does* express is ours. A
derivation the grammar does not contain at all is upstream's, and no amount of
work on the table will ever seat it.

Telling them apart does not need a parse, an oracle, or tree-sitter. It needs
the grammar's own reachability closure: from the nonterminal that governs the
position, can the offending symbol be derived **at all**? If it cannot, that is
an impossibility argument in the strict sense - not "we measured and it did not
work" but "no derivation exists" - and it is checkable against a JSON file in
milliseconds with nothing else installed.

The closure also has to *earn* its verdicts, so every row below is paired with a
control drawn from the same probe set: the spelling of the same construct that
**does** parse. A closure that says `yes` for the accepted spelling and `no` for
the refused one is reading the grammar. A closure that says `no` for both is
reading its own bug.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GRAMMAR = ROOT / "upstream" / "grammars" / "verilog.json"


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

    out: dict[str, set[str]] = {}
    for name, body in rules.items():
        out[name] = set()
        walk(body, out[name])
    return out


def closure(graph: dict[str, set[str]], start: str) -> set[str]:
    seen, stack = set(), [start]
    while stack:
        s = stack.pop()
        for n in graph.get(s, ()):
            if n not in seen:
                seen.add(n)
                stack.append(n)
    return seen


# (wall, the position's governing nonterminal, the symbol that must derive,
#  the one-line witness, and the spelling that parses)
CASES: tuple[tuple[str, str, str, str, str], ...] = (
    ("A  `ifdef in a port list", "list_of_port_declarations", "id_directive",
     "module m #(…) ( input a, `ifdef X output b, `endif input c );",
     "the same directive one level out, in the module body"),
    ("F  macro as a statement", "statement_item", "text_macro_usage",
     "always @* begin `debug end",
     "x = `WIDTH;  - the macro in expression position"),
    ("D  indexed lvalue, blocking", "variable_lvalue", "select1",
     "initial begin c[i] = 0; end",
     "initial begin x = 0; end"),
    ("E  select inside a concat", "concatenation", "select1",
     "x = {a[3]};",
     "x = a[3];  and  x = {b, c};"),
    ("B  $signed in an operand", "expression", "system_tf_call",
     "rd <= $signed(p) * $signed(q);",
     "rd <= $signed(p);"),
    ("G  && before |unary", "expression", "unary_operator",
     "x = (a && |b);",
     "- (this one already measured at +0 bytes)"),
)

# Where the grammar *does* put each target, for the contrast.
HOMES = ("_description", "_non_port_module_item", "class_item",
         "primary_literal", "statement_item", "expression",
         "list_of_port_declarations", "concatenation", "variable_lvalue")


def main() -> int:
    g = json.loads(GRAMMAR.read_text())
    rules = g["rules"]
    graph = edges(rules)
    missing = {c[1] for c in CASES} | {c[2] for c in CASES} | set(HOMES)
    absent = sorted(m for m in missing if m not in rules)
    if absent:
        print(f"grammar has no rule named: {', '.join(absent)}", file=sys.stderr)

    print(f"{GRAMMAR.relative_to(ROOT)}: {len(rules)} rules, "
          f"{len(g.get('conflicts', []))} declared conflicts, "
          f"extras = {[e.get('name', e.get('value')) for e in g['extras']]}\n")
    print(f"{'wall':<28}{'position':<28}{'must derive':<22}{'verdict'}")
    print("-" * 96)
    verdicts = {}
    for wall, pos, target, witness, control in CASES:
        if pos not in rules or target not in rules:
            print(f"{wall:<28}{pos:<28}{target:<22}(no such rule - skipped)")
            continue
        can = target in closure(graph, pos)
        verdicts[wall] = can
        print(f"{wall:<28}{pos:<28}{target:<22}"
              f"{'CONFLICT - the grammar can derive it' if can else 'GAP - no derivation exists'}")
        print(f"{'':<28}witness  {witness}")
        print(f"{'':<28}parses   {control}")
    print()

    print("Where each target IS reachable from, which is the control on the closure:")
    print(f"{'target':<26}" + "".join(f"{h[:13]:<15}" for h in HOMES[:5]))
    for target in ("id_directive", "text_macro_usage", "simple_text_macro_usage",
                   "system_tf_call", "select1"):
        if target not in rules:
            continue
        print(f"{target:<26}" + "".join(
            f"{('yes' if target in closure(graph, h) else '-'):<15}"
            for h in HOMES[:5]))
    print("\nA row that reads `yes` under the position where the construct parses and"
          "\n`-` under the one where it walls is the closure reading the grammar rather"
          "\nthan reading itself.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
