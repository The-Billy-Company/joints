#!/usr/bin/env python3
"""Are verilog's three quoted damage figures the same bytes?

The record quotes three numbers about `picorv32.v` side by side as if they
partitioned one thing:

  63,937   `damage` - `size - built`, whole file
  49,446   "the module's damage", a census of one extent (`picorv32`)
   8,175   "the two constructs that pay", a **counterfactual** delta

63,937 - 49,446 - 8,175 = 6,316, and that 6,316 was then read as a residue and
matched against a **fourth** number from a different instrument entirely (the
peel's 6,591 `behind` bytes, since re-priced to 6,477 as `macro_text`).

Two things make that subtraction inadmissible and this script measures both.

**Units.** 8,175 is a delta in *honest built* - `built` minus `stretch`, bytes
with a token actually standing on them - while 63,937 and 49,446 are computed
from raw `built`. The dimensionally matching figure for the same ablation is
+11,529. Whichever you pick, the third term is a **counterfactual about a file
that does not exist**, and no counterfactual can be a part of a partition of a
real file's bytes.

**Extent.** Even taken as a delta, the arithmetic only works if the ablation's
gain lands *outside* `picorv32` - otherwise it is being subtracted from the same
bytes 49,446 already counted. `named.py` says wall A fires in `picorv32`,
`picorv32_axi` and `picorv32_wb`, so the answer is visibly no; this prints how
much.

The per-module clip is **in situ** - one parse of the whole file, `built`
clipped to each module's own bytes - because that is the only reading in the
same world as 63,937. `named.py`'s per-module table parses each module *alone*,
which is the right instrument for "is this module fixable" and the wrong one for
"how does the whole-file number decompose".
"""
from __future__ import annotations

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
from stamp import take  # noqa: E402

BIN = Path(os.environ["JOINTS_BIN"])
NAME = "verilog"
SRC = ROOT / "upstream" / "sources" / "picorv32.v"
HEAD = re.compile(r"(?m)^module\s+(\w+)")
TAIL = re.compile(r"(?m)^endmodule")


def blocks(text: str) -> list[tuple[str, int, int]]:
    """The eight `module` .. `endmodule` extents, by name."""
    out = []
    for m in HEAD.finditer(text):
        if end := TAIL.search(text, m.end()):
            out.append((m[1], m.start(), end.end()))
    return out


def comment_out(m: re.Match) -> str:
    return "//" + " " * (len(m.group(0)) - 2)


def unsign(m: re.Match) -> str:
    return " " * (len(m.group(0)) - 1) + "("


def unreduce(m: re.Match) -> str:
    return m.group(0).replace("|", " ", 1)


# Verbatim from `named.py`, so a byte credited here is a byte that lane credited.
def abc(s: str) -> str:
    return re.sub(r"&&\s*\|", unreduce,
                  re.sub(r"\$signed\(", unsign,
                         re.sub(r"(?m)^[ \t]*`(ifdef|ifndef|else|elsif|endif)\b.*$",
                                comment_out, s)))


ARMS: dict[str, object] = {"baseline": lambda s: s, "A+B+C": abc}


def leaves(seen: list[tuple[int, str, int, int]]) -> list[tuple[int, int]]:
    """Every childless node, at any depth - the only things that stand on a byte.

    Same containment rule `standing.tops` reads column zero with: a row's
    children are the deeper-indented rows following it.
    """
    return [(a, b) for i, (depth, _, a, b) in enumerate(seen)
            if (seen[i + 1][0] if i + 1 < len(seen) else depth) <= depth]


class Paint:
    """One parse, as two byte masks: `built` and `honest`."""

    def __init__(self, text: str) -> None:
        src = Path(tempfile.mkdtemp(prefix="v-reconcile-")) / SRC.name
        src.write_text(text)
        got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                              str(src), "--ranges", "--all"],
                             capture_output=True, text=True, timeout=900)
        seen = standing.rows(got.stdout)
        self.size = len(text)
        self.built = bytearray(self.size)
        for name, a, b, kid in standing.tops(seen):
            if kid:
                self.built[a:b] = b"\1" * (b - a)
        self.honest = bytearray(self.size)
        for a, b in leaves(seen):
            for i in range(a, b):
                if self.built[i]:
                    self.honest[i] = 1

    def over(self, mask: bytearray, lo: int = 0, hi: int | None = None) -> int:
        return sum(mask[lo:self.size if hi is None else hi])


def main() -> int:
    if {"-h", "--help"} & set(sys.argv[1:]):
        print(__doc__)
        return 0
    text = SRC.read_text()
    size, found = len(text), blocks(text)
    seen = {tag: Paint(fn(text)) for tag, fn in ARMS.items()}
    base, cut = seen["baseline"], seen["A+B+C"]
    print(f"{SRC.name}: {size:,} bytes, {len(found)} modules\n")

    print("WHOLE FILE — the two units the record mixes\n")
    print(f"{'arm':<12}{'built':>9}{'damage':>9}{'honest':>9}"
          f"{'honest damage':>15}{'d built':>10}{'d honest':>10}")
    for tag, p in seen.items():
        b, h = p.over(p.built), p.over(p.honest)
        print(f"{tag:<12}{b:>9,}{size - b:>9,}{h:>9,}{size - h:>15,}"
              f"{b - base.over(base.built):>+10,}{h - base.over(base.honest):>+10,}")

    print(f"\nPER MODULE, IN SITU — `built` clipped to the module's own bytes\n")
    print(f"{'module':<24}{'bytes':>8}{'built':>9}{'damage':>9}"
          f"{'d built':>9}{'d honest':>10}")
    inside = {}
    for name, a, b in found:
        was, now = base.over(base.built, a, b), cut.over(cut.built, a, b)
        dh = cut.over(cut.honest, a, b) - base.over(base.honest, a, b)
        inside[name] = (b - a, was, now - was, dh)
        print(f"{name:<24}{b - a:>8,}{was:>9,}{b - a - was:>9,}"
              f"{now - was:>+9,}{dh:>+10,}")
    lo, hi = next((a, b) for n, a, b in found if n == "picorv32")
    gap = size - sum(v[0] for v in inside.values())
    gap_b = base.over(base.built) - sum(v[1] for v in inside.values())
    gap_d = cut.over(cut.built) - base.over(base.built) - sum(v[2] for v in inside.values())
    print(f"{'between the modules':<24}{gap:>8,}{gap_b:>9,}{gap - gap_b:>9,}"
          f"{gap_d:>+9,}")

    print("\nTHE ARITHMETIC THE RECORD PERFORMED\n")
    d_built = cut.over(cut.built) - base.over(base.built)
    d_honest = cut.over(cut.honest) - base.over(base.honest)
    big = inside["picorv32"]
    print(f"  damage, whole file                     {size - base.over(base.built):>9,}")
    print(f"  damage inside picorv32 [{lo}, {hi})    {big[0] - big[1]:>9,}"
          f"   <- the 49,446 census")
    print(f"  damage outside it                      "
          f"{size - base.over(base.built) - (big[0] - big[1]):>9,}")
    print(f"  ablation delta, honest built           {d_honest:>+9,}"
          f"   <- the 8,175, in honest-built units")
    print(f"  ablation delta, raw built              {d_built:>+9,}"
          f"   <- the same ablation in DAMAGE's units")
    print(f"  of that raw delta, inside picorv32     {big[2]:>+9,}"
          f"   <- NOT disjoint from the census above")
    print(f"  of that raw delta, everywhere else     "
          f"{d_built - big[2]:>+9,}")
    print(f"  the record's residue, its own way      "
          f"{size - base.over(base.built) - (big[0] - big[1]) - 8175:>9,}"
          f"   <- 14,491 - 8,175, the 6,316 exactly")
    print(f"  the same subtraction on THIS arm       "
          f"{size - base.over(base.built) - (big[0] - big[1]) - d_honest:>9,}"
          f"   <- the third term is not arm-invariant")

    print("\nTHE FOURTH NUMBER — the peel's `behind`, which is not damage at all\n")
    got = subprocess.run([sys.executable, str(ROOT / "tool" / "walls.py"), "run",
                          "--grammar", NAME, "--json"],
                         capture_output=True, text=True, timeout=1800)
    peel = next(r for r in json.loads(got.stdout) if r["name"] == NAME)
    a, b = peel["prefix"], peel["size"] - peel["unpeeled"]
    mt = [p for p in peel["priced"] if p[1].startswith("macro_text")]
    print(f"  behind, priced across {len(peel['priced'])} walls        "
          f"{peel['behind']:>9,}")
    print(f"  of which `macro_text`                  {sum(p[3] for p in mt):>9,}"
          f"   <- the 6,477 == the 6,591's own sub-figure")
    print(f"  the whole priced extent                [{a:,}, {b:,})"
          f"   {'INSIDE' if a >= lo and b <= hi else 'not inside'} picorv32")
    print(f"  of those {b - a:,} bytes, BUILT              "
          f"{base.over(base.built, a, b):>9,}   <- `behind` counts built bytes,"
          f" so it is not a slice of `damage` even in principle")
    print(f"  of those {b - a:,} bytes, damage             "
          f"{(b - a) - base.over(base.built, a, b):>9,}")
    print(f"\n  the residue's extent, by contrast       "
          f"outside picorv32 — {size - (hi - lo):,} bytes, disjoint from"
          f" [{a:,}, {b:,})")
    print(take(BIN).line())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
