#!/usr/bin/env python3
"""Read tree-sitter's tree a second way, with no indentation in the route.

`plumb.oracle` builds the oracle from `tree-sitter parse --cst`, whose nesting is
a column count that `differential.indents` has to invert - two spaces a level,
plus one further space for a clean node inside an error subtree, behind a range
prefix whose width the render never states. That inversion is the instrument the
`unjudged` lane trusted least, and verilog's **611 square bytes** hang off it.

So this builds the same tree out of two faces that carry no columns at all:

  * **`-x`** gives every *named* node with `srow/scol/erow/ecol` and unambiguous
    nesting. A whole tree, spans included, no indentation anywhere in it.
  * a **query** of every anonymous type the compiled language admits
    (`node-types.json`, `named: false`) gives every anonymous node's span.
    Anonymous nodes are tokens, so they are always leaves, and a leaf's parent is
    the narrowest named node containing it. No column, no depth guess.

`reconciled` already asserts the CST's *named* shape against the XML, so the
freedom `indents()` actually has is **where anonymous nodes attach** - and that
is exactly what the query route settles independently.

Three verbs, in the order you would run them:

    row <name>      one grammar priced by both oracles, side by side
    corpus          all thirty, node multiset and full `rack` row
    mutants         generated error-bearing cases, three readers

`mutants` exists because the population is the whole problem. The gate this
reader had - `differential.py spans` - grew five error fixtures written by the
person who already had the diagnosis, and the corpus itself puts an `ERROR` in
tree-sitter's own tree on **two of thirty rows**. So neither the fixtures nor the
corpus is evidence about a defect that only lives inside an error subtree.
`mutants` truncates each corpus file and perturbs it at offsets a seeded LCG
picks, which produces error subtrees in whatever shapes that grammar's own
recovery makes, and it reads each one with the reader at a named git revision as
well - because a differential that cannot separate the reader before the fix from
the reader after it is not a differential.

Zero-width nodes are excluded from the comparison and reported apart. A `MISSING`
token has no extent for containment to place it by, and the query names it by its
anonymous type where the CST names it `MISSING x`. Neither paints a byte
(`plumb.paint` and `plumb.hurt` both skip an empty span) so neither can move
`square`; on verilog's 67 of them the whole effect is 11 bytes shifting between
`racked`, `unframed` and `unjudged`, and `square` is identical.
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import traceback

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import differential as d  # noqa: E402
import plumb  # noqa: E402
import rack  # noqa: E402

# Their query printer puts the pattern and the capture on ONE line under
# `--captures`, where `differential.QCAPTURE` anchors `capture:` at the start of
# a line. Searched rather than matched, so both shapes read.
CAPTURE = re.compile(
    r"capture: (?:\d+ - )?(\w+), start: \((\d+), (\d+)\), end: \((\d+), (\d+)\)")
PEN = ROOT / ".local" / "rederive"
HEAD = 6000  # a mutant stays cheap, and the truncation is itself a perturbation
NOISE = (b")}]", b"@", b"end end", b'"', b"~~")
KEEP = ("built", "square", "renamed", "askew", "racked", "unframed", "engulf",
        "unjudged", "unwindowed", "their_nodes", "shared")


# ------------------------------------------------------- the column-free oracle

def anon_types(home: pathlib.Path) -> list[str]:
    """Every anonymous node type the *compiled* language admits.

    From `node-types.json` and not from `grammar.json`: the grammar declares
    strings the generator folds away, and a query naming one of those fails to
    compile at all rather than matching nothing. verilog declares 400 and the
    language admits 409.
    """
    doc = json.loads((home / "src" / "node-types.json").read_text(encoding="utf-8"))
    return sorted({n["type"] for n in doc if not n["named"]})


def escaped(text: str) -> str:
    """A token as a query string literal. Five of verilog's need this."""
    return (text.replace("\\", "\\\\").replace('"', '\\"')
                .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t"))


def anon_spans(home: pathlib.Path, source: pathlib.Path,
               at: d.Lines) -> list[tuple[int, int, str]]:
    """(start, end, type) for every anonymous node, from the oracle's query voice."""
    kinds = anon_types(home)
    scm = d.SEAT / "rederive-anon.scm"
    scm.parent.mkdir(parents=True, exist_ok=True)
    scm.write_text("".join(f'"{escaped(k)}" @a{i}\n' for i, k in enumerate(kinds)),
                   encoding="utf-8")
    got = d.cli([str(d.TS), "query", "--captures", "-p", str(home), str(scm),
                 str(source)], d.WORK)
    if got.returncode != 0:
        raise ValueError(f"the oracle refused the query: {got.stderr[-200:]}")
    return [(at.off(int(m[2]), int(m[3])), at.off(int(m[4]), int(m[5])),
             kinds[int(m[1][1:])])
            for m in map(CAPTURE.search, got.stdout.splitlines()) if m]


def spliced(root: d.Node, anon: list[tuple[int, int, str]]) -> d.Node:
    """Put each anonymous token under the narrowest named node holding it.

    Descends once per token rather than scanning the tree: a token is inside at
    most one child at each level, so the walk costs the depth and not the width.
    A tie on an equal span goes to the deeper node, which is tree-sitter's own
    reading - a token is never a parent.
    """
    for lo, hi, name in anon:
        at = root
        while (nxt := next((k for k in at.kids if k.start <= lo and k.end >= hi), None)):
            at = nxt
        # Kid lists stay in source order; `plumb.flatten` is a pre-order walk.
        seat = next((i for i, k in enumerate(at.kids) if k.start > lo), len(at.kids))
        at.kids.insert(seat, d.Node(name, False, None, lo, hi))
    return root


def theirs(home: pathlib.Path, source: pathlib.Path, blob: bytes) -> list[plumb.Node]:
    """tree-sitter's tree over these bytes, read without reading a column."""
    at = d.Lines(blob)
    with d.alone(d.named(home), writing=False):
        xml = d.xml_tree(d.oracle_run(home, source, "-x"), at)
        anon = anon_spans(home, source, at)
    return plumb.flatten(spliced(xml, anon))


def bag(nodes: list[plumb.Node]) -> collections.Counter:
    """Every node of positive width as (name, named, start, end, depth)."""
    return collections.Counter((n.name, n.named, n.start, n.end, n.depth)
                               for n in nodes if n.end > n.start)


# ---------------------------------------------------------- one row, both ways

def priced(case: plumb.Case) -> dict:
    """One grammar's `rack` row under each oracle, with the node diff beside it.

    `built`, our own forest, the windows and the renames are held fixed and only
    the oracle's node list changes, so a column that moves moved because
    tree-sitter was read differently and for no other reason.
    """
    out: dict = {"name": case.name}
    saw = plumb.read(case)
    if saw is None:
        return out | {"why": "no folio"}
    if not saw.ok:
        return out | {"why": saw.why}
    xq = theirs(case.lang, case.source, saw.blob)
    a, b = bag(saw.theirs), bag(xq)
    cst_row, xq_row = rack.survey(case.name, saw), rack.survey(
        case.name, saw._replace(theirs=xq))
    out |= {"cst_nodes": len(saw.theirs), "xq_nodes": len(xq), "wide": sum(a.values()),
            "cst_only": sum((a - b).values()), "xq_only": sum((b - a).values()),
            "zero_width": sum(n.end == n.start for n in saw.theirs),
            "errors": sum(n.name == "ERROR" for n in saw.theirs),
            "missing": sum(n.name.startswith("MISSING ") for n in saw.theirs),
            "cst": {k: getattr(cst_row, k) for k in KEEP},
            "xq": {k: getattr(xq_row, k) for k in KEEP}}
    out |= {"square_holds": cst_row.square == xq_row.square,
            "row_holds": out["cst"] == out["xq"]}
    if out["cst_only"] or out["xq_only"]:
        out["cst_only_by"] = collections.Counter(k[0] for k in (a - b).elements()).most_common(8)
        out["xq_only_by"] = collections.Counter(k[0] for k in (b - a).elements()).most_common(8)
    return out


def safely(case: plumb.Case) -> dict:
    """A sweep reports on a row it could not read; it does not stop on one."""
    try:
        return priced(case)
    except Exception as e:  # noqa: BLE001 - the failure is the finding
        return {"name": case.name, "why": f"{type(e).__name__}: {e}"[:160],
                "trace": traceback.format_exc()[-400:]}


def corpus(names: set[str], as_json: bool) -> int:
    rows = [safely(c) for c in plumb.slate() if not names or c.name in names]
    if as_json:
        print(json.dumps(rows, indent=1))
    else:
        for r in rows:
            if "why" in r:
                print(f"  {r['name']:<19}refused — {r['why']}")
                continue
            print(f"  {r['name']:<19}{r['wide']:>7} wide nodes  "
                  f"square {r['cst']['square']:>6} / {r['xq']['square']:<6}  "
                  f"diff {r['cst_only']}/{r['xq_only']}"
                  f"{'' if r['row_holds'] else '   ROW MOVED'}")
    read = [r for r in rows if "why" not in r]
    off = [r for r in read if r["cst_only"] or r["xq_only"]]
    sq = [r for r in read if not r["square_holds"]]
    lit = [r for r in read if r["errors"] or r["missing"]]
    print(f"\n{len(read)} of {len(rows)} row(s) read · {len(lit)} with an ERROR or MISSING in"
          f" the oracle's own tree\n{len(off)} node-multiset mismatch(es) ·"
          f" {len(sq)} row(s) where `square` moves ·"
          f" {sum(not r['row_holds'] for r in read)} where any column does")
    return 1 if off or sq else 0


# ------------------------------------------- generated error-bearing fixtures

def rolls(seed: int, n: int, hi: int) -> list[int]:
    """A seeded LCG. The offsets are reproducible and nobody chose them."""
    out, x = [], seed
    for _ in range(n):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out.append(x % max(hi, 1))
    return out


def brood(blob: bytes, seed: int) -> list[tuple[str, bytes]]:
    """One corpus file's mutants: a truncation, then a cut and a jam per offset."""
    base = blob[:HEAD]
    out = [("truncate", base)]
    for i, at in enumerate(rolls(seed, 6, len(base))):
        out.append((f"cut@{at}", base[:at] + base[at + 24:]))
        out.append((f"jam@{at}", base[:at] + NOISE[i % len(NOISE)] + base[at:]))
    return out


def elsewhere(rev: str) -> object:
    """`tool/differential.py` at some git revision, imported under its own name.

    A revision rather than a hardcoded "before": once the fix is committed, HEAD
    stops being the reader that fails, and a differential whose two arms are the
    same reader proves nothing. `mutants` asserts they differ and says so.
    """
    was = PEN / f"differential-{rev.replace('/', '-')}.py"
    was.parent.mkdir(parents=True, exist_ok=True)
    if not was.exists():
        was.write_bytes(subprocess.run(["git", "show", f"{rev}:tool/differential.py"],
                                       cwd=ROOT, capture_output=True, check=True).stdout)
    spec = importlib.util.spec_from_file_location(f"differential_{abs(hash(rev))}", was)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def verdicts(old: object, home: pathlib.Path, src: pathlib.Path, blob: bytes) -> dict:
    """Both CST readers against the column-free tree, over ONE pair of renders."""
    at = d.Lines(blob)
    with d.alone(d.named(home), writing=False):
        xtext, ctext = d.oracle_run(home, src, "-x"), d.oracle_run(home, src, "--cst")
        anon = anon_spans(home, src, at)
    base = bag(plumb.flatten(spliced(d.xml_tree(xtext, at), anon)))
    out: dict = {"errors": xtext.count("<ERROR"), "wide": sum(base.values())}
    for tag, mod in (("now", d), ("was", old)):
        seen = mod.Lines(blob)
        try:
            tree, _ = mod.reconciled(ctext, seen, mod.xml_tree(xtext, seen))
        except Exception as e:  # noqa: BLE001 - a reader that raises is a verdict
            out[tag] = f"raised {type(e).__name__}"
            continue
        if tree is None:
            out[tag] = "refused"
            continue
        got = bag(plumb.flatten(tree))
        out[tag] = "agrees" if got == base else \
            f"differs {sum((got - base).values())}/{sum((base - got).values())}"
    return out


def mutants(names: set[str], seed: int, rev: str, as_json: bool) -> int:
    old = elsewhere(rev)
    PEN.mkdir(parents=True, exist_ok=True)
    rows = []
    for case in plumb.slate():
        if names and case.name not in names:
            continue
        for tag, mutant in brood(case.source.read_bytes(), seed):
            src = PEN / f"{case.name}{case.source.suffix}"
            src.write_bytes(mutant)
            row = {"name": case.name, "mutant": tag, "size": len(mutant)}
            try:
                row |= verdicts(old, case.lang, src, mutant)
            except Exception as e:  # noqa: BLE001
                row |= {"why": f"{type(e).__name__}: {e}"[:140]}
            rows.append(row)
            if not as_json:
                print(f"  {case.name:<19}{tag:<14}now={row.get('now', row.get('why', '?')):<12}"
                      f"was={row.get('was', '—'):<10}errors={row.get('errors', 0)}")
    if as_json:
        print(json.dumps(rows, indent=1))
    read = [r for r in rows if "why" not in r]
    lit = [r for r in read if r["errors"]]
    bad = [r for r in read if r["now"] != "agrees"]
    moved = [r for r in read if r["was"] != r["now"]]
    print(f"\n{len(read)} of {len(rows)} mutant(s) read across"
          f" {len({r['name'] for r in rows})} grammar(s) · {len(lit)} error-bearing across"
          f" {len({r['name'] for r in lit})}\nthe shipped reader disagrees with the"
          f" column-free tree on {len(bad)} · the reader at {rev} on"
          f" {sum(r['was'] != 'agrees' for r in read)}")
    if not moved:
        print(f"  VACUOUS — the reader at {rev} answers exactly as this one does on every"
              f"\n  mutant here, so this population cannot tell them apart. Name a revision"
              f"\n  that predates the fix, or accept that this arm proves nothing today.")
    return 1 if bad or not moved else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__ and __doc__.splitlines()[0])
    ap.add_argument("verb", choices=("row", "corpus", "mutants"))
    ap.add_argument("names", nargs="*", help="grammars to read; default all")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--seed", type=int, default=20260805)
    ap.add_argument("--was", default="HEAD", help="the revision to read as the other reader")
    got = ap.parse_args(argv)
    known = {c.name for c in plumb.slate()}
    if bad := set(got.names) - known:
        print(f"rederive.py: no such grammar: {', '.join(sorted(bad))}", file=sys.stderr)
        return 2
    if got.verb == "mutants":
        return mutants(set(got.names), got.seed, got.was, got.json)
    if got.verb == "row" and not got.names:
        print("rederive.py: `row` wants a grammar name", file=sys.stderr)
        return 2
    return corpus(set(got.names), got.json or got.verb == "row")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
