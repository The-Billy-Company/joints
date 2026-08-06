#!/usr/bin/env python3
"""What does the mend budget actually protect against?

The recovery loop is capped. It was a count (`1 << 14` mends) and is now a share
of the file (3/4 of its bytes walked past), and the second is strictly better:
a count cap is a length cap in disguise, so it bound on exactly one grammar and
let every larger file run uncapped. That much is settled.

The *rationale* is not, and this exists to test it. The cap is explained as
bounding a runaway on a wrong-language walk - the case where a grammar is handed
a file in a language it has never seen, mends at every token, and "runs away
toward the whole file". Three separable claims live in that sentence:

  **separation**  right-language rows and wrong-language rows sit in different
                  ranges, so a threshold between them exists to be chosen. This
                  is the one the source comment asserts ("that is where the
                  measurement separates") and the one a cap needs to be true.
  **growth**      skip share climbs with file length. If it does not, a share
                  cap cannot be the thing standing between this parser and a
                  runaway, because there is nothing to climb.
  **runaway**     cost is worse than linear in length. A superlinear blowup is
                  the only thing a budget rescues you from; linear cost in a
                  file you asked to be parsed is just the parse.

## Measure a fuse with the fuse held wide

A budget that has already fired truncates the number that would calibrate it -
every row at the cap reads as "the cap was needed" no matter what it would have
done. So the binary under this instrument should be built with the cap lifted
past anything reachable, and `--wide` asserts that rather than trusting it: a
run whose rows are pinned to a share ceiling is refused with the reason.

  python3 tool/fuse.py share            right-language against wrong-language
  python3 tool/fuse.py length           share and cost against file length
  python3 tool/fuse.py share --json     machine output

`OUTLINER_BIN` picks the binary, as everywhere else here. Exit 0 ran, 2 refused.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

from stamp import ROOT, ask, take, usual  # noqa: E402
from walls import roster  # noqa: E402

BIN = Path(os.environ.get("OUTLINER_BIN") or usual())
WORK = ROOT / ".local" / "fuse"

# Where a run is pinned rather than measured. The byte fuse is 3/4, so a row
# landing on it is the cap talking; anything at or above this is refused as a
# measurement of the fuse rather than of the parse.
PINNED = 0.74


class Row(NamedTuple):
    grammar: str
    file: str
    lang: str  # the language the *file* is in
    bytes: int
    skipped: int
    roots: int
    secs: float
    verdict: str

    @property
    def right(self) -> bool:
        return self.grammar == self.lang

    @property
    def share(self) -> float:
        return self.skipped / max(self.bytes, 1)

    def as_dict(self) -> dict:
        return {**self._asdict(), "right": self.right, "share": round(self.share, 4)}


def timed(grammar: Path, src: Path) -> tuple[object, float]:
    start = time.perf_counter()
    end = ask(BIN, grammar, src, tree=False, patience=600.0)
    return end, time.perf_counter() - start


def row(grammar: str, where: Path, src: Path, lang: str) -> Row:
    end, secs = timed(where, src)
    return Row(grammar=grammar, file=src.name, lang=lang, bytes=src.stat().st_size,
               skipped=end.skipped, roots=end.roots, secs=round(secs, 4),
               verdict=end.verdict)


def grown(src: Path, copies: int) -> Path:
    """`copies` of a file, concatenated. Deliberately not made valid in any
    language: the wrong-language walk is the case under test, and wrapping the
    text to keep it parseable would change which case that is."""
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / f"{src.stem}.{copies}x{src.suffix}"
    if not out.is_file() or out.stat().st_size != src.stat().st_size * copies:
        out.write_bytes(src.read_bytes() * copies)
    return out


def owners() -> dict[str, Path]:
    """Each grammar's own source file, from the roster the rest of the tools read."""
    return dict(roster())


def grid() -> list[Row]:
    """Every grammar against its own file, and a wrong-language block beside it.

    The wrong-language block is drawn from the small corpus rather than the
    held-out sources so the cross product stays affordable, and it is a *block*
    rather than one hand-picked pairing because the claim under test is about
    two populations. One row cannot overlap anything.
    """
    own = owners()
    rows = [row(g, ROOT / "upstream" / "grammars" / f"{g}.json", src, g)
            for g, src in sorted(own.items()) if src.is_file()]
    corpus = {g: src for g, src in own.items()
              if src.is_file() and src.parent.name == "corpus"}
    for g in sorted(corpus):
        where = ROOT / "upstream" / "grammars" / f"{g}.json"
        if not where.is_file():
            continue
        for lang, src in sorted(corpus.items()):
            if lang != g:
                rows.append(row(g, where, src, lang))
    return rows


def sweep(grammar: str, src: Path, lang: str, scales: tuple[int, ...]) -> list[Row]:
    where = ROOT / "upstream" / "grammars" / f"{grammar}.json"
    return [row(grammar, where, grown(src, n), lang) for n in scales]


def pinned(rows: list[Row]) -> list[Row]:
    return [r for r in rows if r.share >= PINNED]


def spill(what: str, rows: list[Row], **more) -> int:
    print(json.dumps({"what": what, "stamp": take(BIN).as_dict(),
                      "rows": [r.as_dict() for r in rows], **more}, indent=2))
    return 0


def banner() -> None:
    print(take(BIN).line(), file=sys.stderr)


def refuse(why: str) -> int:
    print(f"fuse.py: {why}", file=sys.stderr)
    return 2


def check(rows: list[Row], wide: bool) -> int | None:
    if not wide:
        return None
    if bad := pinned(rows):
        worst = max(bad, key=lambda r: r.share)
        return refuse(
            f"{len(bad)} row(s) sit at or above a {PINNED:.0%} share - "
            f"{worst.grammar} on {worst.file} at {worst.share:.1%}. That is the cap "
            "talking, not the parse. Rebuild with the fuse lifted and re-run.")
    return None


def do_share(argv: list[str]) -> int:
    rows = grid()
    if (bad := check(rows, "--wide" in argv)) is not None:
        return bad
    right = sorted((r for r in rows if r.right), key=lambda r: -r.share)
    wrong = sorted((r for r in rows if not r.right), key=lambda r: -r.share)
    if "--json" in argv:
        return spill("fuse-share", rows,
                     overlap=overlap(right, wrong))
    banner()
    print("\nfuse: bytes recovery walked past, as a share of the file\n")
    print(f"  {'grammar':<12}{'file':<22}{'bytes':>9}{'skipped':>9}{'share':>8}"
          f"{'roots':>7}{'secs':>8}")
    for tag, block in (("right language - its own file", right),
                       ("wrong language - a file it has never seen", wrong)):
        print(f"\n  -- {tag} --")
        for r in block:
            print(f"  {r.grammar:<12}{r.file:<22}{r.bytes:>9}{r.skipped:>9}"
                  f"{r.share:>7.1%}{r.roots:>7}{r.secs:>8.3f}")
    say(right, wrong)
    return 0


def overlap(right: list[Row], wrong: list[Row]) -> dict:
    """The one number the separation claim lives or dies on.

    A threshold separating the populations exists precisely when the lowest
    wrong-language row sits above the highest right-language row. So the
    interesting quantity is not a mean or a spread, it is the count of rows on
    the wrong side of every candidate line - and the pair that crosses.
    """
    tops = [r for r in right if r.skipped > 0]
    if not tops or not wrong:
        return {"separates": None}
    high = max(tops, key=lambda r: r.share)
    low = min(wrong, key=lambda r: r.share)
    return {
        "separates": low.share > high.share,
        "highest_right": {"grammar": high.grammar, "file": high.file,
                          "share": round(high.share, 4)},
        "lowest_wrong": {"grammar": low.grammar, "file": low.file,
                         "share": round(low.share, 4)},
        "wrong_below_highest_right": sum(1 for r in wrong if r.share < high.share),
        "right_above_lowest_wrong": sum(1 for r in tops if r.share > low.share),
    }


def say(right: list[Row], wrong: list[Row]) -> None:
    o = overlap(right, wrong)
    if o.get("separates") is None:
        print("\n  no mending rows on one side; nothing to separate")
        return
    hi, lo = o["highest_right"], o["lowest_wrong"]
    print(f"\n  highest right-language row  {hi['grammar']} on {hi['file']} "
          f"{hi['share']:.1%}")
    print(f"  lowest wrong-language row   {lo['grammar']} on {lo['file']} "
          f"{lo['share']:.1%}")
    if o["separates"]:
        print("  the populations SEPARATE - a threshold between them exists")
    else:
        print(f"  the populations OVERLAP - {o['wrong_below_highest_right']} wrong-language"
              f" row(s) sit below the highest right-language row,")
        print(f"  and {o['right_above_lowest_wrong']} right-language row(s) sit above the"
              " lowest wrong-language one. No threshold separates them.")


SCALES = (1, 8, 64, 256, 512, 720)


def do_length(argv: list[str]) -> int:
    own = owners()
    src = own.get("rust", ROOT / "research" / "joinery" / "corpus" / "ledger.rs")
    rows = sweep("json", src, "rust", SCALES)
    if (bad := check(rows, "--wide" in argv)) is not None:
        return bad
    if "--json" in argv:
        return spill("fuse-length", rows, linearity=linear(rows))
    banner()
    print("\nfuse: the json grammar reading rust, by how much rust\n")
    print(f"  {'bytes':>9}{'skipped':>9}{'share':>8}{'roots':>8}{'secs':>9}"
          f"{'us/KB':>9}{'x prev':>8}")
    last = None
    for r in rows:
        rate = r.secs * 1e6 / max(r.bytes / 1024, 1)
        grew = f"{r.secs / last:>7.2f}" if last else "      - "
        print(f"  {r.bytes:>9}{r.skipped:>9}{r.share:>7.1%}{r.roots:>8}"
              f"{r.secs:>9.3f}{rate:>9.0f}{grew}")
        last = r.secs
    fit = linear(rows)
    print(f"\n  share across {len(rows)} lengths: {fit['share_low']:.1%} to "
          f"{fit['share_high']:.1%}, spread {fit['share_spread']:.1%}")
    print(f"  {fit['verdict']}")
    print("  the small rows are dominated by pressing the grammar, so a falling"
          " rate is amortisation rather than a saving")
    return 0


def linear(rows: list[Row]) -> dict:
    """Is cost linear in length? Read off the per-byte rate, and its *direction*.

    A rate that holds while the input grows three orders of magnitude is linear
    cost, and needs no regression to say so. But the spread alone cannot say
    which claim it supports, because the smallest row is dominated by pressing
    the grammar - fixed work that has nothing to do with length - so a healthy
    sweep shows a *falling* rate and a wide spread. Reporting the spread without
    the sign would read as a 57x runaway on a sweep that is amortising, which is
    the opposite finding. So the direction is taken from the tail, where the
    fixed cost is already paid, and a runaway is a rate that climbs there.
    """
    rates = [r.secs * 1e6 / max(r.bytes / 1024, 1) for r in rows]
    shares = [r.share for r in rows]
    big = max(rows, key=lambda r: r.bytes)
    spread = max(rates) / max(min(rates), 1e-9)
    tail = rates[len(rates) // 2:]  # past where pressing the grammar dominates
    climb = tail[-1] / max(tail[0], 1e-9)
    return {
        "share_low": min(shares), "share_high": max(shares),
        "share_spread": max(shares) - min(shares),
        "rate_low": min(rates), "rate_high": max(rates),
        "rate_spread": round(spread, 2),
        "tail_rate_first": round(tail[0], 1), "tail_rate_last": round(tail[-1], 1),
        "tail_climb": round(climb, 3),
        "runaway": climb > 1.5,
        "biggest_bytes": big.bytes, "biggest_secs": big.secs,
        "share_grows": shares[-1] > shares[0] + 0.05,
        "verdict": (
            f"{big.bytes} bytes of the wrong language cost {big.secs:.3f}s. "
            f"Per-byte rate {'CLIMBS' if climb > 1.5 else 'does not climb'} over the"
            f" tail ({tail[0]:.0f} to {tail[-1]:.0f} us/KB, {climb:.2f}x): "
            f"{'a runaway' if climb > 1.5 else 'linear cost, no runaway'}"),
    }


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if not BIN.exists():
        return refuse(f"no binary at {BIN}")
    verb, rest = argv[0], argv[1:]
    if verb == "share":
        return do_share(rest)
    if verb == "length":
        return do_length(rest)
    return refuse(f"no verb {verb!r}; have share, length")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
