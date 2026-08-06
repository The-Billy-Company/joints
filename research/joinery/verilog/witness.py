#!/usr/bin/env python3
"""The 49,446 bytes, one smallest failing module at a time.

Ablation is finished here and the reason is now a house rule: blanking a
construct that *partly* parses takes away the bytes it was contributing, so
every arm of a statement-form sweep moves `built` down and none of them can be
read. Four lanes used it today; on this file it cannot separate a grammar gap
from a productive construct, and the whole 49,446 is exactly that case.

What is left is the opposite direction - **build the smallest module that
fails, from nothing** - and it has the property ablation lacks: a synthesised
module's `built` has a known ceiling, so `built == size` is a pass and anything
under it is a named failure with nothing else in the file to confuse it.

This runs that at corpus scale instead of by hand. It lifts every top-level
statement out of `picorv32`'s procedural blocks, seats each one alone in the
smallest legal module that can hold it, and parses that. A statement that fails
alone is a witness. Statements are then clustered by the wall they name, which
turns several hundred failures into the handful of *distinct* grammar defects
underneath, and the shortest member of each cluster is shrunk by deleting
sub-expressions while the wall holds - so the reported witness is minimal, not
merely small.

Two controls, because a synthesiser that fabricates its own failures is worse
than no instrument:

  frame     the empty harness, `module m; always @* begin x = 0; end endmodule`,
            must stand at 100%. If the frame itself fails, every row below is
            the frame's failure wearing a statement's name.
  accepted  the count of statements that pass. A sweep where everything fails
            is a sweep measuring its own extraction, and the pass column is the
            only thing that can say otherwise.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import standing  # noqa: E402
from order import folio_for  # noqa: E402
from stamp import outcome  # noqa: E402

SRC = ROOT / "upstream" / "sources" / "picorv32.v"
BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))

# The harness. `%s` is one statement; everything else is known to stand.
FRAME = "module m;\nreg [31:0] x, y, c, mem [0:3];\ninteger i;\nalways @* begin\n%s\nend\nendmodule\n"
FRAME_CONTROL = "x = 0;"

HEAD = re.compile(r"^[ \t]*(always|initial)\b", re.M)


def parse(text: str, folio: str) -> tuple[bool, str]:
    """(did the whole module stand, the verdict) for one synthesised module.

    A synthesised module is small enough that `accepted` is a *total* answer -
    either every byte is under the one root, or the verdict says where it
    stopped - so this reads `kind` rather than re-deriving a span union. That
    is not a shortcut taken for speed: this grammar's forest is an
    s-expression carrying no offsets, so a `built` column computed off it would
    have been a column of zeros wearing a number's name."""
    # Per-process, because a fixed scratch path is a race and this one bit:
    # two runs overlapping by milliseconds had the second read the first's
    # 3,328-byte statement as its own 90-byte control frame, and the control
    # duly reported that the frame was broken. A shared tree makes that a
    # certainty rather than a risk.
    tmp = ROOT / ".local" / "witness" / f"w-{os.getpid()}.v"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(text)
    g = subprocess.run([str(BIN), "parse", folio, str(tmp), "--quiet"],
                       capture_output=True, text=True, timeout=120)
    out = outcome(g.stderr, tmp, len(text.encode()))
    return out.kind == "whole", out.verdict


def blocks(text: str) -> list[str]:
    """Every `always`/`initial` block body in the file, outermost only."""
    out = []
    for m in HEAD.finditer(text):
        i = text.find("begin", m.start())
        if i < 0 or i > text.find("\n", m.start()) + 400:
            continue
        depth, j = 0, i
        while j < len(text):
            if text.startswith("begin", j) and not text[j - 1: j].isalnum():
                depth += 1
                j += 5
            elif text.startswith("end", j) and not text[j - 1: j].isalnum() \
                    and not text.startswith("endcase", j) and not text.startswith("endmodule", j):
                depth -= 1
                j += 3
                if depth == 0:
                    out.append(text[i + 5: j - 3])
                    break
            else:
                j += 1
        else:
            break
    return out


def statements(body: str) -> list[str]:
    """Top-level statements of one block body: split on `;`, never inside a
    `begin…end` / `case…endcase` run and never inside brackets.

    The bracket half is not defensive tidying. Without it a `for (i = 0; i < n;
    i = i+1)` header splits on its own two semicolons, and the three fragments
    - `for (i = 0;`, `i < n;`, `i=i+1) begin …` - each fail to parse, cluster
    separately, and arrive on the board as three distinct grammar defects that
    do not exist. They were caught only because the witnesses printed were not
    whole statements; nothing else in the sweep would have said so."""
    out, depth, bracket, start, i = [], 0, 0, 0, 0
    while i < len(body):
        if body[i] in "([{":
            bracket += 1
            i += 1
            continue
        if body[i] in ")]}":
            bracket -= 1
            i += 1
            continue
        if bracket == 0 and re.match(r"\b(begin|case|casex|casez|fork)\b", body[i:]):
            depth += 1
            i += 4
            continue
        if bracket == 0 and re.match(r"\b(end|endcase|join)\b", body[i:]):
            depth -= 1
            i += 3
            continue
        if body[i] == ";" and depth == 0 and bracket == 0:
            s = body[start: i + 1].strip()
            if s:
                out.append(s)
            start = i + 1
        i += 1
    tail = body[start:].strip()
    if tail:
        out.append(tail)
    # `if (a) x; else y;` puts a depth-0 `;` between the two arms, so a split on
    # `;` alone hands back `else y;` as if it were a statement. It is not one,
    # it fails to parse for that reason alone, and it arrived on the first board
    # as two more distinct grammar defects. An `else` is glued back to what it
    # continues - the same class of phantom as the `for` header, and the same
    # tell: a witness that is not a whole statement.
    glued: list[str] = []
    for s in out:
        s = s.strip()
        if not s or s.startswith("//"):
            continue
        if glued and re.match(r"\b(else|end\b\s*else)\b", s):
            glued[-1] = f"{glued[-1]} {s}"
        else:
            glued.append(s)
    return glued


SHRINK = (
    (re.compile(r"\s*//[^\n]*"), ""),                    # comments
    (re.compile(r"\s+"), " "),                            # whitespace
)


GARBAGE = re.compile(r"\(\s*\)|\[\s*\]|\{\s*\}|[<>=+*/&|^-]\s*;|;\s*[<>=+*/&|^]|\$\s*[<(]")


def shrink(stmt: str, folio: str, wall: str) -> str:
    """Delete from the statement while the same wall holds - and only whole
    balanced runs, never a bare identifier.

    The identifier rule is the whole difficulty. A first cut here deleted any
    token, and it "worked": every shrink still named the same LR state. It also
    turned `alu_lts <= $signed(a) < $signed(b);` into `alu_lts <= $ < $();`,
    which is not a smaller version of the defect, it is a *different* defect
    that shares a state number. Sixteen clusters came back with witnesses no
    verilog author would recognise, and each one would have sent a reader to
    the wrong rule.

    So a shrink here must keep the statement recognisable as the construct it
    came from. Two rules do that: delete only balanced `()[]{}` runs and
    trailing statements, and refuse any candidate matching `GARBAGE` - the
    empty bracket pair and the dangling operator that are the signature of
    having shrunk past the construct into a syntax accident."""
    cur = re.sub(r"\s*//[^\n]*", "", stmt)
    cur = re.sub(r"\s+", " ", cur).strip()
    changed = True
    while changed and len(cur) > 12:
        changed = False
        for a, b in sorted(_runs(cur), key=lambda r: r[1] - r[0], reverse=True):
            cand = (cur[:a] + cur[b:]).strip()
            if not cand or len(cand) >= len(cur) or GARBAGE.search(cand):
                continue
            if wall_of(parse(FRAME % cand, folio)[1]) == wall:
                cur, changed = cand, True
                break
    return cur


def _runs(s: str) -> list[tuple[int, int]]:
    """Deletion candidates: whole balanced `()[]{}` runs, and each trailing
    `;`-separated statement. No bare identifiers - see `shrink`."""
    out, stack = [], []
    for i, ch in enumerate(s):
        if ch in "([{":
            stack.append(i)
        elif ch in ")]}" and stack:
            out.append((stack.pop(), i + 1))
    out += [(m.start(), len(s)) for m in re.finditer(r";", s)]
    return out


WALL = re.compile(r"unexpected (.+?) at \d+ in state (\d+)")


def wall_of(verdict: str) -> str:
    m = WALL.search(verdict)
    if m:
        return f"{m[1]} in {m[2]}"
    return "stray" if verdict.startswith("stray") else ("" if "accepted" in verdict else verdict[:40])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shrink", action="store_true", help="minimise one witness per cluster")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--reuse", action="store_true",
                    help="re-read the last sweep's clusters instead of re-parsing")
    a = ap.parse_args()

    folio = str(folio_for("verilog", standing.WORK))
    text = SRC.read_text()

    ok, frame_verdict = parse(FRAME % FRAME_CONTROL, folio)
    print(f"control  frame "
          f"{'stands - rows below are the statements failing, not the frame' if ok else 'FAILS - every row below is suspect'}"
          f"  {frame_verdict[:50]}")
    if not ok:
        return 2

    stmts, seen = [], set()
    for b in blocks(text):
        for s in statements(b):
            if s not in seen:
                seen.add(s)
                stmts.append(s)
    if a.limit:
        stmts = stmts[: a.limit]
    print(f"lifted   {len(stmts)} distinct top-level statements out of "
          f"{len(blocks(text))} procedural blocks\n")

    cache = ROOT / ".local" / "witness" / "clusters.json"
    if a.reuse and cache.exists():
        blob = json.loads(cache.read_text())
        clusters, passed = defaultdict(list, blob["clusters"]), blob["passed"]
        print("(clusters reused from the last sweep; shrink only)")
    else:
        clusters, passed = defaultdict(list), 0
        for s in stmts:
            stood, verdict = parse(FRAME % s, folio)
            if stood:
                passed += 1
                continue
            clusters[wall_of(verdict)].append(s)
        cache.write_text(json.dumps({"clusters": clusters, "passed": passed}))

    lifted = sum(len(s.encode()) for s in stmts)
    refused = sum(len(s.encode()) for ms in clusters.values() for s in ms)
    print(f"accepted {passed}/{len(stmts)} statements stand alone at 100% - "
          f"the sweep is not failing everything")
    print(f"refused  {len(stmts) - passed} in {len(clusters)} distinct walls, "
          f"{refused:,} of {lifted:,}B lifted ({refused / lifted:.1%})\n")

    # Bytes, not counts. A wall that stops nine statements and a wall that stops
    # one are the same row under a count and 40x apart under a size, and this
    # file is the reason to care: on `picorv32` the most *frequent* warm wall
    # costs -167 bytes while a wall seen twice carries thousands. Sorting by
    # `stmts` here would have reproduced, inside the fix, the exact ranking
    # error the fix exists to report.
    print(f"{'wall':<26}{'stmts':>6}{'bytes':>9}{'share':>7}  smallest witness")
    print("-" * 108)
    for wall, members in sorted(clusters.items(),
                                key=lambda kv: -sum(len(s.encode()) for s in kv[1])):
        size = sum(len(s.encode()) for s in members)
        smallest = min(members, key=len)
        if a.shrink:
            smallest = shrink(smallest, folio, wall)
        one = re.sub(r"\s+", " ", smallest)[:56]
        print(f"{wall:<26}{len(members):>6}{size:>9,}{size / refused:>7.1%}  {one}")
    print("\nRanked by bytes. The same table ranked by `stmts` puts "
          f"{max(clusters, key=lambda k: len(clusters[k]))} first; "
          f"by bytes it is {max(clusters, key=lambda k: sum(len(s.encode()) for s in clusters[k]))}."
          "\nThose are different walls, and only one of them is worth a day.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
