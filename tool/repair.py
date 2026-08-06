#!/usr/bin/env python3
"""What does the standing tree save, and what does one broken byte cost?

`amend.py` asks what one keystroke costs at seven cut positions of one grammar.
This asks the two questions a *report* needs and that one cannot answer:

  reuse     over a stream of small edits scattered anywhere in the file, how
            many fewer tokens does the incremental path read than a cold parse
            of the same bytes? That share is the whole claim of an incremental
            parser, and it is the number to publish per grammar.
  cascade   drop one stray brace at every byte offset in turn. At how many of
            them does the parse stop being accepted, and when it does, how many
            leaves does the repair re-derive?

They exist together because one explains the other. A grammar can read almost
no tokens on the median edit and still be the worst row on the board, if the
minority of edits that *break* it re-mint most of the file. json is exactly
that shape and a mean over three grammars hides it, which is why `reuse` prints
per grammar and never a mean.

## The generator is one distribution, and that is load-bearing

The temptation, once a grammar comes back an outlier, is to say the edits were
unfair to it. So the generator is fixed before any grammar is named and is
**not conditioned on the grammar** in any way:

  a delete of 1-12 bytes, or an insert of 1-8 bytes drawn from a random slice
  of the file's own bytes, at a uniform offset, undone on the next beat

Same seed, same distribution, same magnitudes for every grammar. Nothing here
reads a file extension. The one asymmetry left is seed length, and it runs
*against* the finding rather than for it: a fixed-magnitude edit is a larger
share of a short file, so the shortest seed should look best, and if the
shortest seed comes back worst then the generator is exonerated by the
direction of the effect rather than by anyone's inspection of it.

Undoing each edit on the next beat is what makes the beats comparable: every
measured edit lands on the same bytes, so their median is a measurement rather
than a drift through a file that is slowly filling with garbage.

## `cascade` reads the depth, not the count

A break is cheap or ruinous depending on how much of the file the repair drags
in behind it, and `minted` - leaves the spine re-derived - is that quantity. A
grammar that breaks at half its offsets and re-mints three leaves each time is
healthier than one that breaks at a third and re-mints two hundred, and only
the second is a defect worth a report row.

  python3 tool/repair.py reuse                     the per-grammar reuse table
  python3 tool/repair.py reuse --grammar rust,java,json --beats 60
  python3 tool/repair.py cascade                   break rate and repair depth
  python3 tool/repair.py cascade --stray '}'       any single stray byte
  python3 tool/repair.py --json                    machine output, with a stamp

Exit 0 ran, 2 an error. It gates nothing: it is an instrument, and the numbers
it prints are arguments rather than thresholds.
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
from pathlib import Path
from typing import NamedTuple

import amend
import stamp

ROOT = amend.ROOT
WORK = ROOT / ".local" / "repair"

# One ledger program per language, which is the corpus's own unit. Named here
# rather than derived because `amend.SEEDS` is the cut-position instrument's
# roster and holds only the grammar it can scale; these three are the grammars
# the report carries on the incremental axis.
SEEDS = {"rust": "ledger.rs", "java": "Ledger.java", "json": "ledger.json"}

# Magnitudes, fixed before any grammar was measured. Small on purpose: a
# keystroke and a short paste are what an editing session is made of, and a
# 4 KB splice would be measuring a different feature.
CUT = 12  # longest delete
PUT = 8  # longest insert
SEED = 20260805  # so a re-run is the same stream of edits


class Reuse(NamedTuple):
    grammar: str
    bytes: int
    beats: int
    cold_read: int
    read: int  # median tokens read per edit
    mean_read: float  # and the mean, which is a different claim
    minted: int  # median leaves re-derived per edit
    us: int
    broke: int  # beats whose verdict was not `accepted`

    @property
    def share(self) -> float:
        """Tokens read as a share of the cold parse's. Below 1.0 is the reuse."""
        return self.read / max(self.cold_read, 1)

    @property
    def mean_share(self) -> float:
        """The same ratio over the mean.

        Carried beside the median because the two answer different questions and
        the gap between them *is* the finding on a grammar whose breaks are
        expensive. The median is what a typical keystroke costs; the mean is
        what a session of them costs, and a grammar that re-mints a quarter of
        the file on half its edits has a mean near a cold parse and a median
        nowhere near it. Publishing either one alone picks a side of that.
        """
        return self.mean_read / max(self.cold_read, 1)

    def as_dict(self) -> dict:
        return {**self._asdict(), "share": round(self.share, 4),
                "saved": round(1.0 - self.share, 4),
                "mean_share": round(self.mean_share, 4),
                "mean_saved": round(1.0 - self.mean_share, 4)}


class Cascade(NamedTuple):
    grammar: str
    bytes: int
    offsets: int
    broke: int
    depth_p50: int
    depth_p90: int
    depth_max: int
    leaves: int  # the whole file's leaf count, so a depth has a ceiling
    aborted: int  # offsets where the session died and nothing could be measured
    first_abort: int  # and the first of them, so it can be reproduced by hand
    runs: int  # maximal runs of consecutive breaking offsets

    @property
    def rate(self) -> float:
        return self.broke / max(self.offsets, 1)

    @property
    def reach(self) -> float:
        """The worst repair as a share of the file's leaves."""
        return self.depth_max / max(self.leaves, 1)

    def as_dict(self) -> dict:
        return {**self._asdict(), "rate": round(self.rate, 4),
                "reach": round(self.reach, 4)}


def scratch(name: str, seed: bytes) -> Path:
    """A copy of the seed to edit, so the corpus file itself is never written.

    Ten lanes share this tree; an instrument that edits a tracked corpus file
    in place is one interrupted run away from committing a stray brace.
    """
    WORK.mkdir(parents=True, exist_ok=True)
    path = WORK / SEEDS[name]
    path.write_bytes(seed)
    return path


def safe(chunk: bytes) -> str | None:
    """A file slice spelled so the verb reproduces it byte for byte, or nothing.

    Two hazards, and the second one cost this instrument its first reading of
    the json row. Edits go to the verb as arguments, so a slice has to decode
    and hold no NUL - that is the easy half. The hard half is that `amend`
    unescapes the replacement text, where `\\X` consumes two bytes and emits
    one, so any slice carrying a backslash arrives **shorter than it left**. The
    undo, sized on the slice, then cut a byte too few and left one behind; a
    hundred beats later the buffer was scrap. json was the only grammar to
    notice because `ledger.json` is the only seed here holding string escapes,
    which read as json specifically degrading under an edit stream.

    Doubling the backslashes makes the round trip exact and keeps the bytes the
    *file's own* rather than substituting a sanitised stand-in, which would
    quietly make the inserted text a different distribution than the advertised
    one.
    """
    if not chunk or b"\x00" in chunk:
        return None
    try:
        return chunk.decode().replace("\\", "\\\\")
    except UnicodeDecodeError:
        return None


def script(text: bytes, beats: int, rng: random.Random) -> list[str]:
    """`beats` edits, each followed by its own undo.

    Every pair returns the file to `text`, so the edit in beat 40 is applied to
    the same bytes as the edit in beat 1.
    """
    wide = len(text)
    out: list[str] = []
    made = 0
    while made < beats:
        at = rng.randrange(wide)
        if rng.random() < 0.5:  # a delete, and its undo puts the bytes back
            end = min(wide, at + rng.randint(1, CUT))
            back = safe(text[at:end])
            if back is None:
                continue
            out += [f"{at}..{end}=", f"{at}..{at}={back}"]
        else:  # an insert of the file's own bytes, and its undo cuts them out
            grab = rng.randrange(wide)
            chunk = text[grab:grab + rng.randint(1, PUT)]
            put = safe(chunk)
            if put is None:
                continue
            # The undo is a byte range over what the verb *wrote*, which is the
            # slice's own length - not the length of the spelling that carried
            # it, and not a character count.
            out += [f"{at}..{at}={put}", f"{at}..{at + len(chunk)}="]
        made += 1
    return out


def paired(name: str, got: list, sent: int) -> list:
    """The edit beats, having checked that every edit reported one.

    `drive` skips a line it cannot parse, so a dropped row shifts the parity of
    everything after it and turns inserts into deletes half the time. That
    happened here - a refusal naming a comma - and it read as a parser that
    stopped recovering rather than as an instrument that stopped counting. So
    the count is asserted rather than assumed: one open plus one row per edit.
    """
    if len(got) != sent + 1:
        amend.die(f"{name}: sent {sent} edits, got {len(got) - 1} rows back;"
                  " a dropped cost line would pair an insert against a delete")
    return got[1::2]


def restored(name: str, undos: list) -> None:
    """Every undo puts a valid file back, so every undo must accept.

    The oracle this instrument needed and did not have. Each seed parses whole
    on its own bytes, so an undo that comes back refused means the buffer is no
    longer the seed - and every beat after it is measuring scrap rather than an
    edit. It is a hard stop rather than a warning because the numbers past that
    point look like a grammar degrading under load, which is a far more
    interesting story than the truth and therefore the one that gets published.
    """
    for i, b in enumerate(undos):
        if b.verdict != "accepted":
            amend.die(f"{name}: undo {i} came back {b.verdict!r} instead of restoring;"
                      " the buffer has drifted and no beat after it is a measurement")


def reuse(name: str, grammar: Path, beats: int) -> Reuse:
    seed = amend.read(ROOT / "research" / "joinery" / "corpus" / SEEDS[name])
    path = scratch(name, seed)
    cold = amend.drive(grammar, path, [], cold=True)[0]
    edits = script(seed, beats, random.Random(SEED))
    got = amend.drive(grammar, path, edits, cold=False)
    puts = paired(name, got, len(edits))
    restored(name, got[2::2])
    return Reuse(
        grammar=name, bytes=len(seed), beats=len(puts), cold_read=cold.read,
        read=int(statistics.median(b.read for b in puts)),
        mean_read=round(statistics.fmean(b.read for b in puts), 1),
        minted=int(statistics.median(b.minted for b in puts)),
        us=int(statistics.median(b.us for b in puts)),
        broke=sum(1 for b in puts if b.verdict != "accepted"),
    )


def cascade(name: str, grammar: Path, stray: str, step: int, batch: int) -> Cascade:
    """One stray token at every offset, in sessions of `batch` offsets each.

    Batched rather than swept in one process for two reasons, and the second is
    the load-bearing one. An offset's cost should not depend on how many edits
    came before it, so a fresh session per batch is the design that matches the
    claim. And a long enough session on this tree dies outright - `rust` at 1,319
    beat-pairs and `json` at 379, with `error: TrailRefused` out of the effect
    algebra and every remaining edit never applied - so a single-session sweep
    silently measures a prefix of the file and calls it the file.
    """
    seed = amend.read(ROOT / "research" / "joinery" / "corpus" / SEEDS[name])
    path = scratch(name, seed)
    spots = list(range(0, len(seed) + 1, step))
    seen: dict[int, object] = {}
    lost: list[int] = []
    leaves, at = 0, 0
    while at < len(spots):
        chunk = spots[at:at + batch]
        edits: list[str] = []
        for spot in chunk:
            edits += [f"{spot}..{spot}={stray}", f"{spot}..{spot + len(stray)}="]
        got = amend.drive(grammar, path, edits, cold=False)
        leaves = leaves or got[0].leaves
        rows = got[1:]
        for k, spot in enumerate(chunk):
            if 2 * k < len(rows):
                seen[spot] = rows[2 * k]
        if len(rows) == len(edits):
            restored(name, rows[1::2])
            at += len(chunk)
            continue
        # The session stopped mid-batch. The offset it stopped on cannot be
        # measured, and is reported as such rather than skipped: an unmeasurable
        # offset is a fact about the parser, and dropping it would report the
        # rest of the file as if it were the file.
        gave = len(rows) // 2  # offsets whose pair completed
        restored(name, rows[1:2 * gave:2])
        lost.append(chunk[len(rows) // 2])
        at += len(rows) // 2 + 1
    hurt = [(spot, b.minted) for spot, b in seen.items() if b.verdict != "accepted"]
    deep = sorted(m for _, m in hurt) or [0]
    where = {spot for spot, _ in hurt}
    return Cascade(
        grammar=name, bytes=len(seed), offsets=len(spots), broke=len(hurt),
        depth_p50=int(statistics.median(deep)),
        depth_p90=deep[min(len(deep) - 1, int(len(deep) * 0.9))],
        depth_max=max(deep), leaves=leaves, aborted=len(lost), first_abort=lost[0] if lost else -1,
        runs=sum(1 for spot in where if spot - step not in where),
    )


def named(want: str) -> list[str]:
    for n in (out := want.split(",")):
        if n not in SEEDS:
            amend.die(f"no seed for {n}; have {', '.join(SEEDS)}")
    return out


def do_reuse(args: argparse.Namespace) -> int:
    rows = [reuse(n, amend.grammar_path(n), args.beats) for n in named(args.grammar)]
    if args.json:
        return spill("reuse", [r.as_dict() for r in rows])
    print("\nrepair reuse: tokens one edit reads, against a cold parse of the same bytes\n")
    print(f"  {'grammar':<8}{'bytes':>8}{'beats':>7}{'cold':>7}{'read':>7}"
          f"{'saved':>8}{'mean':>8}{'saved':>8}{'minted':>8}{'us':>7}{'broke':>7}")
    for r in rows:
        print(f"  {r.grammar:<8}{r.bytes:>8}{r.beats:>7}{r.cold_read:>7}{r.read:>7}"
              f"{(1 - r.share) * 100:>7.1f}%{r.mean_read:>8.1f}"
              f"{(1 - r.mean_share) * 100:>7.1f}%{r.minted:>8}{r.us:>7}{r.broke:>7}")
    print("\n  saved = 1 - read/cold, on the median edit and then on the mean edit"
          "\n  the two disagree exactly where a grammar's breaks are expensive"
          "\n  no mean across grammars: a pathological row and two healthy ones"
          "\n  do not have a middle")
    return done()


def do_cascade(args: argparse.Namespace) -> int:
    rows = [cascade(n, amend.grammar_path(n), args.stray, args.step, args.batch)
            for n in named(args.grammar)]
    if args.json:
        return spill("cascade", [r.as_dict() for r in rows])
    print(f"\nrepair cascade: one stray {args.stray!r} at every offset,"
          " and what the repair drags in\n")
    print(f"  {'grammar':<8}{'bytes':>8}{'offsets':>9}{'broke':>7}{'rate':>8}"
          f"{'runs':>6}{'p50':>6}{'p90':>6}{'max':>6}{'leaves':>8}{'reach':>8}{'died':>6}")
    for r in rows:
        print(f"  {r.grammar:<8}{r.bytes:>8}{r.offsets:>9}{r.broke:>7}"
              f"{r.rate * 100:>7.1f}%{r.runs:>6}{r.depth_p50:>6}{r.depth_p90:>6}"
              f"{r.depth_max:>6}{r.leaves:>8}{r.reach * 100:>7.1f}%{r.aborted:>6}")
    print("\n  depth = leaves the repair re-derived, over the breaking offsets only"
          "\n  runs = maximal runs of consecutive breaking offsets; near `broke` means"
          "\n  the breaks alternate rather than clustering · reach = max depth / leaves")
    for r in rows:
        if r.aborted:
            print(f"  {r.grammar}: {r.aborted} offset(s) unmeasurable - the session died."
                  f" First at byte {r.first_abort}:"
                  f" `amend … '{r.first_abort}..{r.first_abort}={args.stray}'"
                  f" '{r.first_abort}..{r.first_abort + len(args.stray)}='`")
    return done()


def spill(what: str, rows: list[dict]) -> int:
    print(json.dumps({"what": what, "stamp": stamp.take(amend.BIN).as_dict(),
                      "rows": rows}, indent=2))
    return 0


def done() -> int:
    print(stamp.take(amend.BIN).line(), file=sys.stderr)
    return 0


def main() -> int:
    if not amend.BIN.is_file():
        amend.die(f"no binary at {amend.BIN}; `zig build -Dcli-optimize=ReleaseFast` first")
    # `--grammar` and `--json` hang off a shared parent rather than the root, so
    # they read the same either side of the verb. An instrument whose flags only
    # work in one position gets invoked wrong once and quietly answers about the
    # default roster.
    both = argparse.ArgumentParser(add_help=False)
    both.add_argument("--json", action="store_true")
    both.add_argument("--grammar", default=",".join(SEEDS))
    ap = argparse.ArgumentParser(prog="repair.py", description=__doc__, parents=[both],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="verb", required=True)
    one = sub.add_parser("reuse", parents=[both],
                         help="tokens one edit reads against a cold parse")
    one.add_argument("--beats", type=int, default=60)
    one.set_defaults(fn=do_reuse)
    two = sub.add_parser("cascade", parents=[both],
                         help="break rate and repair depth, offset by offset")
    two.add_argument("--stray", default="}")
    two.add_argument("--step", type=int, default=1)
    two.add_argument("--batch", type=int, default=128,
                     help="offsets per session; well under where a session dies")
    two.set_defaults(fn=do_cascade)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
