#!/usr/bin/env python3
"""How many distinct source constructs stand between picorv32.v and a whole parse?

The cold peel in `tool/walls.py` restarts each round from a clean state, and on
this file 12 of the first 12 walls it names are `in state 0` - a tail resumed
mid-expression refusing its own first token. That is an artifact of the method,
not a wall the parser meets, and no attribution should be built on it.

This is the warm form, scored on bytes instead of on names. Every round parses
the **whole file** from byte 0, so the state the table is in when it meets a
wall is the state it would really have been in; then the *line* the wall sits on
is blanked to a same-length verilog comment and the file is parsed again. Offsets
never move, so a byte means the same thing in round 1 and round 90.

Blanking a line rather than a byte is deliberate and it is the cost model: a
line is roughly what a grammar fix would have to *make parseable*, so the count
of rounds is "how many distinct constructs is this", and the `built` climb is
"what is each one holding". A file that stands after five rounds is one bounded
defect family; a file still climbing at ninety is a second project. The number
is the answer either way.

Rounds stop when the parse reads whole, when the wall stops moving (a line
whose blanking does not clear it), or at `--rounds`.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import standing  # noqa: E402
from order import folio_for  # noqa: E402
from stamp import outcome, take  # noqa: E402

BIN = Path(os.environ["JOINTS_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"

# What a blanked line *was*, so the rounds group into named constructs rather
# than into ninety anonymous byte offsets. Shape, in the order a verilog line
# is most specifically described by - the first match wins, and anything none
# of them claim is printed verbatim as residue rather than swept into a bucket.
KINDS: tuple[tuple[str, str], ...] = (
    ("conditional compilation", r"^\s*`(ifdef|ifndef|else|elsif|endif)\b"),
    ("macro directive", r"^\s*`\w+"),
    ("macro use", r"`\w+"),
    ("attribute", r"\(\*"),
    ("port declaration", r"^\s*(input|output|inout)\b"),
    ("net/var declaration", r"^\s*(reg|wire|integer|localparam|parameter|genvar|real)\b"),
    ("always/initial header", r"^\s*(always|initial)\b"),
    ("task/function header", r"^\s*(task|function|endtask|endfunction)\b"),
    ("generate", r"^\s*(generate|endgenerate|genvar)\b"),
    ("case arm", r"^\s*(case|casez|casex|endcase|default\s*:)"),
    ("blocking assignment", r"^[^=<]*[^=<!>]=[^=]"),
    ("nonblocking assignment", r"<="),
    ("block keyword", r"^\s*(begin|end|endmodule|module)\b"),
)


def classify(line: str) -> str:
    return next((k for k, pat in KINDS if re.search(pat, line)), "other")


def line_at(text: str, byte: int) -> tuple[int, int]:
    """The [start, end) of the line containing `byte`, end excluding the newline."""
    a = text.rfind("\n", 0, byte) + 1
    b = text.find("\n", byte)
    return a, len(text) if b < 0 else b


def score(src: Path, size: int) -> tuple[standing.Row, object]:
    """`standing.ask`'s arithmetic over one parse this file ran itself, so a
    round costs one parse rather than two and cannot read two generations."""
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, size, got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    was = standing.extras(NAME)
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = standing.union(stands)
    under = standing.union([(a, b) for _, a, b, _ in top])
    orphan = standing.union(
        stands + [(a, b) for n, a, b, kid in top if not kid and n in was]) - built
    return standing.Row(NAME, "breadth", size, built, under - built, orphan, len(top),
                        sum(1 for *_, kid in top if not kid), end.verdict, len(was),
                        len(seen), end.unsound), end


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rounds", type=int, default=120)
    ap.add_argument("--json", type=Path)
    ap.add_argument("--every", type=int, default=1, help="print one row in N")
    args = ap.parse_args(argv)

    text = SRC.read_text()
    body, size = list(text), len(text)
    work = Path(tempfile.mkdtemp(prefix="v-climb-")) / SRC.name
    log, blanked, stuck = [], set(), 0
    print(f"{SRC.name}: {size:,} bytes\n")
    print(f"{'round':>6}{'built':>9}{'d':>8}{'describes':>10}{'leaves':>7}"
          f"{'roots':>7}{'covered':>9}  blanked construct / residual wall")
    for turn in range(1, args.rounds + 1):
        work.write_text("".join(body))
        row, end = score(work, size)
        at = end.at
        if end.kind == "whole":
            print(f"{turn:>6}{row.built:>9,}{'':>8}{row.nodes:>10,}{row.leaves:>7}"
                  f"{row.roots:>7}{row.covered:>8.1%}  READS WHOLE")
            log.append({"round": turn, "built": row.built, "nodes": row.nodes,
                        "kind": "whole", "line": ""})
            break
        if at is None:
            print(f"{turn:>6}  no byte named: {end.verdict[:60]}")
            break
        a, b = line_at("".join(body), at)
        if (a, b) in blanked:
            stuck += 1
            if stuck > 2:
                print(f"{turn:>6}  blanking line [{a},{b}) did not move the wall; stopping")
                break
        blanked.add((a, b))
        was = "".join(body[a:b])
        kind = classify(was)
        prev = log[-1]["built"] if log else 0
        if turn % args.every == 0 or turn <= 5:
            print(f"{turn:>6}{row.built:>9,}{row.built - prev:>+8,}{row.nodes:>10,}"
                  f"{row.leaves:>7}{row.roots:>7}{row.covered:>8.1%}  {kind:<24}"
                  f"{was.strip()[:34]}")
        log.append({"round": turn, "built": row.built, "nodes": row.nodes,
                    "covered": round(row.covered, 4), "at": at, "kind": kind,
                    "line": was.strip(), "wall": end.verdict})
        body[a:b] = list("//" + " " * (b - a - 2)) if b - a >= 2 else list(" " * (b - a))

    if log:
        first, last = log[0], log[-1]
        by: dict[str, int] = {}
        for r in log:
            by[r["kind"]] = by.get(r["kind"], 0) + 1
        print(f"\n{len(log)} round(s): built {first['built']:,} -> {last['built']:,} "
              f"({last['built'] - first['built']:+,}), describes {first['nodes']:,} -> "
              f"{last['nodes']:,} ({last['nodes'] - first['nodes']:+,})")
        print(f"{len(blanked)} distinct line(s) blanked, {sum(1 for _ in blanked)} of "
              f"{len(SRC.read_text().splitlines()):,} in the file, by construct:")
        for kind, n in sorted(by.items(), key=lambda kv: -kv[1]):
            print(f"    {kind:<26}{n:>4}")
    if args.json:
        args.json.write_text(json.dumps(log, indent=1))
    print(take(BIN).line())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
