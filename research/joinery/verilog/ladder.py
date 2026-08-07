#!/usr/bin/env python3
"""Attribute picorv32.v's damage to named walls, one layer at a time.

`ablate.py` asks *which single construct is the wall*. This asks the follow-up
the board actually needs: **once that one is gone, what is standing behind it,
and what is each layer worth.** Each rung blanks everything the rungs above it
did plus one more construct, so the `d built` column is the marginal bytes that
construct alone was holding.

Three things ride every rung, none of them optional:

  `describes` and `leaves`, because `built` is bytes under a root **with a
  child** and one dishonest root stretched over a hole scores the whole hole.
  A rung that lifts `built` while `describes` falls is reading less.

  the residual wall, so the ladder names what it is climbing toward rather than
  reporting an anonymous byte count.

  a `--mend=none` reading beside the mended one, because a mended parse's
  verdict names where trouble *began* and `none` names where it stopped.

`--trap` instead prints the `--mend=keep` measurement the board warns about:
the largest describing-less trap on the corpus, aimed at this file.
"""
from __future__ import annotations

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


def comment_out(m: re.Match) -> str:
    return "//" + " " * (len(m.group(0)) - 2)


def blank(m: re.Match) -> str:
    return " " * len(m.group(0))


# Each rung is applied on top of every rung above it. Ordered by what the
# previous rung's residual wall named, not by guesswork - see RESULT-1.
RUNGS: tuple[tuple[str, object], ...] = (
    ("nothing", lambda s: s),
    ("`ifdef family", lambda s: re.sub(
        r"(?m)^[ \t]*`(ifdef|ifndef|else|elsif|endif)\b.*$", comment_out, s)),
    ("+ every ` line", lambda s: re.sub(r"(?m)^[ \t]*`\w+.*$", comment_out, s)),
    ("+ remaining ` uses", lambda s: re.sub(r"`\w+", blank, s)),
    ("+ (* attributes *)", lambda s: re.sub(r"\(\*.*?\*\)", blank, s, flags=re.S)),
)


def board(name: str, src: Path, size: int, extra: tuple[str, ...]) -> standing.Row:
    """`standing.ask`'s own arithmetic, over a parse this file chose the flags for.

    Not a second scorer. `standing.ranged` runs one fixed `--ranges --all` parse
    and takes no flags, so calling `standing.ask` with a `--mend=` policy in
    hand scores the *default* policy three times and prints three identical
    rows. It did, and the "trap" line under them read `+0 bytes` - an
    instrument reporting a comparison it had not made. Every column below is
    still computed by `standing`'s own `rows`/`tops`/`union`/`extras`, so this
    cannot disagree with the board about what a root is; only the argv differs.
    """
    got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                          str(src), "--ranges", "--all", *extra],
                         capture_output=True, text=True, timeout=900)
    end = outcome(got.stderr, src, size, got.stdout)
    seen = standing.rows(got.stdout)
    top = standing.tops(seen)
    was = standing.extras(name)
    stands = [(a, b) for _, a, b, kid in top if kid]
    built = standing.union(stands)
    under = standing.union([(a, b) for _, a, b, _ in top])
    orphan = standing.union(
        stands + [(a, b) for n, a, b, kid in top if not kid and n in was]) - built
    return standing.Row(name, "breadth", size, built, under - built, orphan, len(top),
                        sum(1 for *_, kid in top if not kid), end.verdict, len(was),
                        len(seen), end.unsound)


def score(text: str, tag: str, extra: tuple[str, ...] = ()) -> standing.Row:
    src = Path(tempfile.mkdtemp(prefix="v-ladder-")) / SRC.name
    src.write_bytes(text.encode())

    def said(*flags: str):
        got = subprocess.run([str(BIN), "parse", str(folio_for(NAME, standing.WORK)),
                              str(src), "--quiet", *flags],
                             capture_output=True, text=True, timeout=900)
        return outcome(got.stderr, src, len(text))

    row, stopped = board(NAME, src, len(text), extra), said("--mend=none")
    end = said(*extra)
    print(f"{tag:<22}{end.mends:>7}{row.built:>9}{row.spoil:>8}{row.nodes:>9}"
          f"{row.leaves:>7}{row.covered:>8.1%}{row.standing:>9.1%}  {end.verdict[:34]}")
    print(f"{'':<22}{'--mend=none':>7}{'':>9}{'':>8}{'':>9}{'':>7}{'':>8}{'':>9}  "
          f"{stopped.verdict[:34]}")
    return row


def trap() -> None:
    """The describing-less trap the board warns about, read on every column that
    can catch it. `built` alone says `keep` is a large improvement."""
    print(f"{'policy':<22}{'mends':>7}{'built':>9}{'damage':>9}{'spoil':>8}"
          f"{'describes':>10}{'leaves':>7}{'covered':>9}{'standing':>9}")
    got = {}
    for mode in ("fell", "keep", "none"):
        got[mode] = score(SRC.read_text(), mode, (f"--mend={mode}",))
    base, keep = got["fell"], got["keep"]
    db = (base.size - base.built) - (keep.size - keep.built)
    print(f"\n`--mend=keep` against `fell`: damage {db:+,} bytes, "
          f"describes {keep.nodes - base.nodes:+,} nodes, "
          f"covered {keep.covered - base.covered:+.1%}, "
          f"spoil {keep.spoil - base.spoil:+,}")
    print("  -> " + ("READING LESS: `built` rises while describes falls and "
                     "(covered falls or spoil rises)"
                     if db > 0 and keep.nodes < base.nodes
                     and (keep.covered < base.covered or keep.spoil > base.spoil)
                     else "not the trap as described - re-read this row"))


if __name__ == "__main__":
    if "--trap" in sys.argv:
        trap()
    else:
        text, applied = SRC.read_text(), []
        print(f"{SRC.name}: {len(text):,} bytes · damage is `size - built`\n")
        print(f"{'blanked, cumulative':<22}{'mends':>7}{'built':>9}{'spoil':>8}"
              f"{'describes':>9}{'leaves':>7}{'covered':>8}{'standing':>9}  residual wall")
        seen = []
        for tag, fn in RUNGS:
            applied.append(fn)
            body = text
            for f in applied:
                body = f(body)
            assert len(body) == len(text), f"{tag} changed the length"
            seen.append((tag, score(body, tag)))
        print(f"\n{'rung':<22}{'marginal built':>16}{'marginal describes':>20}")
        for (tag, row), (_, prev) in zip(seen[1:], seen):
            print(f"{tag:<22}{row.built - prev.built:>+16,}{row.nodes - prev.nodes:>+20,}")
        first, last = seen[0][1], seen[-1][1]
        print(f"\nall rungs together: built {first.built:,} -> {last.built:,} "
              f"({last.built - first.built:+,}), damage {first.size - first.built:,} -> "
              f"{last.size - last.built:,}, describes {first.nodes:,} -> {last.nodes:,}")
    print(take(BIN).line())
