"""Is the forest a TREE - over the whole corpus, and without asking an oracle.

Every byte column on `standing.py`'s board is a union over spans, and a union
has nothing to say about parentage. `built` is the union of the ROOT spans, so
on any file one root covers whole it is the file size, `standing` is 100% and
`damage` is 0 - no matter what the tree beneath that root looks like. A child
outside its parent contributes its bytes to `built` exactly as a well-placed
one does, and so does a child out of order, and so does a torn node. The two
headline metrics measure REACH. They are structurally incapable of measuring
SHAPE, and that is not a fact about one grammar.

`Quire.survey` is the instrument that can see it: one walk, one bit per node,
no oracle, no tree-sitter, no corpus of expected output. It has been running on
every parse this whole time and printing `UNSOUND: ...` into a verdict line
that nothing read as a failure. toml carried `1 loose` on a row scoring
`100% standing, 0 damage` for as long as anyone has looked.

So this is that check with a caller. It is the corpus, not a fixture: the
roster decides which grammars are asked, so a grammar added tomorrow is asked
tomorrow without anybody remembering to add it here.

    python3 tool/sound.py            # the gate: non-zero if any tree is unsound
    python3 tool/sound.py --list     # every row and what it said
    python3 tool/sound.py --json     # the same, machine-readable

## Three answers, not two

A row this checkout cannot ask - no pinned grammar, no source, a press that
fails, a parse that times out - is a SKIP and is reported as one. A gate that
turns "I could not look" into "I looked and it was fine" is the same silence
this file exists to end, one level up.

The first draft of this gate had that bug one level *down*, and it was the
worst copy of it in the tree. Its whole evidence for `sound` was the ABSENCE of
an `UNSOUND:` clause - and an absence is also what a binary that stopped
calling `Quire.survey` prints, and what a reworded clause prints, and what a
`parse.zig` whose survey call was dropped in a refactor prints. Thirty rows
would have gone on reading `sound` off a check nobody ran, with
`survey_test.zig` green the whole time, because those arenas test the walk and
nothing tested the wiring.

So `parse.zig` now prints `surveyed N of M nodes` on **every** parse, sound or
not, and this gate demands it. A row that answers without it is UNASKED and
fails - loudly, on every row at once, which is what a wiring failure should
look like. `M` is the arena and `N` is what the walk reached, so the claim has
a size in it: a survey that covered part of the forest cannot pass as one that
covered all of it either.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))

import stamp  # noqa: E402
from order import Refused, folio_for  # noqa: E402
from walls import roster  # noqa: E402

BIN = Path(os.environ.get("OUTLINER_BIN", ROOT / "zig-out" / "bin" / "outliner"))
WORK = Path(os.environ.get("OUTLINER_WORK", ROOT / ".local" / "sound"))
PATIENCE = 240


class Says(NamedTuple):
    """One row's answer, with the evidence that it IS an answer.

    `unsound` alone is two facts wearing one empty string, which is exactly the
    shape this file exists to abolish. `walked`/`held` is the positive half:
    -1 means the parse never claimed to have surveyed anything.
    """

    name: str
    unsound: str
    walked: int
    held: int

    @property
    def looked(self) -> bool:
        return self.walked >= 0

    @property
    def word(self) -> str:
        if not self.looked:
            return "UNASKED"
        return (f"{self.unsound} — over " if self.unsound else "sound over ") + (
            f"{self.walked} of {self.held} node(s)")


def look() -> tuple[list[Says], list[tuple[str, str]]]:
    """Every roster row asked once: the ones that answered, and the ones that could not.

    Through `stamp.ask`, which is the only place an instrument runs outliner
    and reads its answer back - so this gate and the board are reading the same
    sentence out of the same stderr rather than two regexes that agree today.
    """
    said: list[Says] = []
    past: list[tuple[str, str]] = []
    WORK.mkdir(parents=True, exist_ok=True)
    for name, src in roster():
        if not src.exists():
            past.append((name, f"no source at {src}"))
            continue
        try:
            folio = folio_for(name, WORK)
        except Refused as e:
            past.append((name, str(e)[:120]))
            continue
        if folio is None:
            past.append((name, "no folio - not pinned in this checkout"))
            continue
        got = stamp.ask(BIN, folio, src, tree=True, patience=PATIENCE)
        if got.kind == "timeout":
            past.append((name, f"timed out after {PATIENCE}s"))
            continue
        # Exit 2 is the binary saying nothing could be read or pressed, so no
        # forest exists to survey and no clause could have been printed. That
        # is a SKIP and not a wiring failure - yaml has no lexable terminal at
        # all and reaches this every run. Told apart by the exit code rather
        # than by the missing clause, because those are the two cases the
        # clause was invented to separate and folding them back together here
        # would undo the whole point one line before it lands.
        if got.code == 2:
            past.append((name, f"no parse — the binary refused: {got.verdict[:70]}"))
            continue
        said.append(Says(name, got.unsound, got.surveyed, got.arena))
    return said, past


def main(argv: list[str]) -> int:
    said, past = look()
    # Three populations, and the middle one is new. `bad` is a tree that
    # contradicts itself; `mute` is a parse that never said it looked, which is
    # not a parser defect at all - it is this gate discovering it has no
    # evidence. Both are non-zero, and they print different sentences, because
    # the fix for one is in `Gather.reduce` and the fix for the other is in
    # `parse.zig`.
    bad = [s for s in said if s.looked and s.unsound]
    mute = [s for s in said if not s.looked]
    part = [s for s in said if s.looked and not s.unsound and s.walked < s.held]

    if "--json" in argv:
        print(json.dumps({"asked": len(said), "skipped": len(past),
                          "walked": sum(s.walked for s in said if s.looked),
                          "held": sum(s.held for s in said if s.looked),
                          "unsound": [{"name": s.name, "said": s.unsound} for s in bad],
                          "unasked": [s.name for s in mute],
                          "partial": [{"name": s.name, "walked": s.walked,
                                       "held": s.held} for s in part],
                          "skip": [{"name": n, "why": w} for n, w in past]}, indent=2))
        return 1 if bad or mute else 0

    if "--list" in argv:
        for s in said:
            print(f"  {s.name:<20}{s.word}")
        for n, w in past:
            print(f"  {n:<20}SKIP - {w}")

    for n, w in past:
        print(f"sound: {n}: not asked - {w}", file=sys.stderr)

    if not said:
        # Nothing answered, so there is nothing to clear. Loud, and non-zero:
        # a corpus-shaped gate over an empty corpus is the vacuous pass every
        # other gate in this repository has a clause against.
        print("sound: no grammar could be asked - run `python3 tool/grammars.py fetch`",
              file=sys.stderr)
        return 2

    if mute:
        # Before the unsound report, because it subsumes it: a binary that does
        # not say it surveyed has not cleared the rows that ALSO said nothing.
        print(f"sound: {len(mute)} of {len(said)} asked grammars answered without saying"
              f" they surveyed anything:\n  {', '.join(s.name for s in mute)}",
              file=sys.stderr)
        print("\nThat is not a parse defect. `parse.zig` prints `surveyed N of M nodes` on"
              "\nevery parse so this gate can tell a SOUND tree from one nobody LOOKED at,"
              "\nand these rows carry no such clause — so either the binary predates the"
              "\ncontract, or the `Quire.survey` call has been dropped and every row here"
              "\nis clearing itself on an absence. Rebuild, and if the clause is still"
              "\nmissing, look at `verdict` in `src/surface/face/outliner/parse.zig`.",
              file=sys.stderr)
        return 1

    if not bad:
        walked = sum(s.walked for s in said)
        held = sum(s.held for s in said)
        print(f"sound: {len(said)} of {len(said)} asked grammars hand back a TREE"
              f" - every node reached once, children in source order and disjoint,"
              f" each child inside its parent"
              + (f" ({len(past)} skipped)" if past else ""))
        # The size of the claim, printed with it. `30 of 30 sound` is a count of
        # rows; this is the count of nodes those rows actually put under the
        # walk, and it is what makes the clearance non-vacuous.
        print(f"       {walked} node(s) walked across {len(said)} forest(s), out of"
              f" {held} the arenas held"
              + (f" — {len(part)} row(s) carry arena slack a root does not reach,"
                 f" widest {max(part, key=lambda s: s.held - s.walked).name}"
                 f" {max(s.held - s.walked for s in part)}" if part else
                 " — every node in every arena was reached"))
        # Said plainly, because the shortfall LOOKS like a coverage gap and is
        # not one. `held` is the arena the gatherer allocated, `walked` is the
        # forest the roots actually hold, and a reduction that lost a race
        # leaves a node behind that no tree contains. `survey` deliberately
        # does not call that a fault; it is reported so the clearance above
        # carries the size of what it cleared instead of only a row count.
        print("       the shortfall is arena the roots abandoned, not forest that went"
              " unchecked: every\n       node any root reaches was walked, which is what"
              " `sound` claims.")
        return 0

    print(f"sound: {len(bad)} of {len(said)} asked grammars hand back a forest that is"
          f" NOT a tree:", file=sys.stderr)
    for s in bad:
        print(f"  {s.name}: {s.unsound}", file=sys.stderr)
    print("\nThis is `Quire.survey`, and it is not an oracle comparison - it is the tree"
          "\ncontradicting itself. `standing` and `damage` cannot see any of it: both are"
          "\nunions over spans and a union is silent about parentage, so a row here can"
          "\nand does read 100%/0. Fix the construction, never this gate.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
