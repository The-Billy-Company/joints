#!/usr/bin/env python3
"""Were these two numbers taken against the same world?

Five instruments in this tree have now produced a comparison whose two arms were
not comparable. Every one of them came back **clean**, twice, and every one of
them erred toward agreement:

1. `order.miss` keyed a folio cache on a path plus an mtime, so a before-arm read
   its after-arm's table.
2. `specimen` defaulted its stop line, so a run against a stale binary scored as
   if attributed.
3. `fetch_scanners` rewrote every scanner with its own bytes and unlinked the
   generated `parser.c` beside it, giving one grammar two identities.
4. `oracle_build` overwrote a shared `grammar.json` while holding no lock; raced,
   it produced one torn tree and three silent readings of another arm's grammar.
5. A lane pinned its baseline, worked for eight minutes, pinned its arm, and read
   `latex -1,185`. The lex lane had landed a latex fix inside those eight minutes.

The first four share a mechanism — *the setup writes to the thing being
compared* — and it is tempting to gate that, because it is concrete and it is
what four of five did. **It is the wrong target.** The fifth wrote nothing. The
tree moved in the gap *between* two runs, so there is no window either run could
have opened that contains the event, and the discipline everyone was taught (a
work directory per arm, folio shas checked) is precisely the check that cannot
see it. A gate aimed at writes is aimed at the accident.

What all five share is the failure, not the mechanism:

> **two arms taken against different worlds**, each internally consistent,
> reported as one comparison.

So this file holds two detectors, deliberately not merged, because they answer
different questions and a merged verdict would hide which one spoke.

**`witness`** — *what world was this arm taken against?* A record per arm: the
binary's bytes, a **per-file manifest** of the tree it was built from, the oracle
identity of every grammar read, the digest of every artifact read, and the three
`OUTLINER_*` variables that say whether the arm owned its own workspace. Two
witnesses are compared field by field and the comparison refuses when they differ
anywhere outside the variable it declared it was varying. This catches all five,
and it catches the fifth on the subject manifest alone — *your two arms were
built from trees differing in three files, and you only claim one of them.*

**`seal`** — *did this run write into its own evidence?* Within one arm, the
write primitives are interposed and `stamp.fed` is hooked, so a read of an
artifact this run mutated raises **at the instant of the read** — which is
strictly before any verdict derived from it, without a caller having to remember
to check. This catches 3 and 4 at their mechanism with the call site attached,
and needs no second arm to exist.

Neither subsumes the other. The witness cannot fire until there are two arms; the
seal cannot see a between-run fact. `still.py verify` restores all five in a
scratch tree and prints which detector bit each, including the two the seal
misses.

**What is deliberately not here: a list of known-bad functions.** Nothing below
names an instrument or a call site. The seal's population is whatever the process
writes; the witness's population is whatever the arm reads. Both grow by
themselves when a thirty-first grammar or a sixteenth instrument arrives.
"""

from __future__ import annotations

import argparse
import builtins
import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import textwrap
import time
import traceback
from pathlib import Path
from types import SimpleNamespace
from typing import Iterator, NamedTuple

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))

import stamp  # noqa: E402

HOME = ROOT / ".local" / "still"
WITNESS = HOME / "witness"
# The sidecar `pin.py build` writes beside its own record. A digest says two pins
# differ; only a manifest says *in which files*, and "in which files" is the
# entire content of the fifth case - the lane's own change was one file and the
# tree had moved in three.
WORLD = "world.json"


# ---------------------------------------------------------------- the manifest


def manifest(root: Path) -> dict[str, str]:
    """Every source file under `root`, by content. The witness's subject field.

    `stamp.survey` already walks exactly this set and folds it into one digest.
    One digest answers *did the tree move* and cannot answer *what moved*, and
    on a tree ten lanes write to the first question has the same answer all day.
    """
    out: dict[str, str] = {}
    for name in stamp.SOURCES:
        base = root / name
        leaves = ([base] if base.is_file() else
                  sorted(p for p in base.rglob("*") if p.is_file()) if base.is_dir() else [])
        for p in leaves:
            try:
                out[str(p.relative_to(root))] = stamp.digest(p)
            except OSError:
                # A file a sibling is mid-write on is a fact about this tree
                # state. Recording it as unreadable keeps it in the comparison
                # instead of silently agreeing with the other arm about it.
                out[str(p.relative_to(root))] = "unreadable"
    return out


def fold(mani: dict[str, str]) -> str:
    h = hashlib.sha256()
    for rel in sorted(mani):
        h.update(rel.encode() + b"\0" + mani[rel].encode() + b"\0")
    return h.hexdigest()


def mark(where: Path, root: Path | None = None) -> int:
    """Write the subject manifest beside a pin's own record, at pin time.

    Called by `pin.py build`, and it has to be: a pin is a *frozen* build, so the
    tree it was built from is only knowable while it is still the live tree. A
    witness taken later can read the live repo all it likes and it will be
    reading somebody else's afternoon.
    """
    mani = manifest(root or ROOT.resolve())
    (where / WORLD).write_text(json.dumps(mani, indent=0, sort_keys=True) + "\n")
    return len(mani)


def subject_of(binary: Path) -> tuple[dict[str, str], str]:
    """The per-file manifest of the tree a binary was built from, and where it
    came from: `pin` (recorded at build time), `live` (this binary is the tree's
    own, so the tree is its subject), or `unrecorded`.

    `unrecorded` is not an error and must not be silently treated as empty. A pin
    built before this file existed genuinely cannot say what it was built from,
    and a comparison involving one has to report that it is comparing on fewer
    fields rather than report agreement it did not check.
    """
    try:
        side = binary.resolve().parents[1] / WORLD
        return json.loads(side.read_text()), "pin"
    except (OSError, ValueError):
        pass
    if binary.resolve() == stamp.usual().resolve():
        return manifest(ROOT.resolve()), "live"
    return {}, "unrecorded"


# ------------------------------------------------------------------ the record


class Witness(NamedTuple):
    """What world one arm was taken against.

    Every field is here because one of the five moved it while the verdict stayed
    clean. `work` and `lane` are the odd ones out - they are not measurements,
    they are the arm's claim to have owned its own workspace, and case one is two
    arms that made the same claim with the same string.
    """

    arm: str
    when: float
    binary: str  # sha256 of the bytes that ran - usually the declared variable
    built: float
    where: str
    origin: str  # pin · live · unrecorded
    subject: dict[str, str]  # per-file manifest of the tree it was built from
    tree: str  # fold of that manifest
    live: str  # the repo's own sources, right now
    work: str  # OUTLINER_WORK - the folio cache this arm presses into
    lane: str  # OUTLINER_LANE - the oracle seat this arm sits in
    oracles: dict[str, str]  # grammar -> attest identity, as read
    artifacts: dict[str, str]  # path -> digest, as read
    # --- the other parser. Defaults, so a witness written before these fields
    # existed still revives; absent reads as "did not say", which is what a
    # board saved this morning honestly did.
    cli: str = ""  # the CLI that lowered them; one string, not thirty
    court: str = ""  # attest's fold of the above - what gets printed
    rule: str = ""  # the version of the identity RULE those digests obey
    asked: bool = False  # did this run put a question to them, or only cite them
    lowered: dict[str, str] = {}  # grammar -> generated digest, when asked
    # Live verdicts on THIS arm, over held. `oracles` above is a property of the
    # REPO - which tree-sitter would answer, if asked - and reads thirty on an
    # arm whose seat is empty, so a citation built on it alone says a figure was
    # judged when its `square` reads 0 for want of a verdict. This pair is what
    # separates those.
    #
    # `None` is "did not look" and is the only honest reading of a witness
    # written before this field, or of an arm that declared no seat. `(0, 0)` is
    # "looked, and this arm holds nothing" - a measurement, and the one the
    # citation has to be loudest about. Folding those two into one value is how
    # the absence got quiet in the first place.
    verdicts: tuple[int, int] | None = None

    def as_dict(self) -> dict:
        return {**self._asdict(), "subject_files": len(self.subject)}

    def line(self) -> str:
        how = "consulted" if self.asked else "attributed"
        seat = ("" if self.verdicts is None
                else f", {self.verdicts[0]} of {self.verdicts[1]} live here")
        oracle = (f"{len(self.oracles)} oracle(s) {self.court[:9]} {how}{seat}"
                  if self.oracles else "no oracle")
        return (f"witness {self.arm}: binary {self.binary[:9]} · subject {self.tree[:9]}"
                f" ({len(self.subject)} file(s), {self.origin}) · live {self.live[:9]}"
                f" · {oracle} · {len(self.artifacts)} artifact(s)"
                f" · work {self.work or '(default)'} · lane {self.lane or '(pid)'}")

    def cite(self) -> str:
        """The same world, in one line a page can carry.

        `line()` is for a lane reading its own terminal and says everything.
        This is for the *next* page, and says the three things that make a
        figure re-findable: which binary pressed it, which tree that binary was
        built from, and whether an oracle was in the room. Markdown, because
        the destination is markdown, and short, because an attribution longer
        than the sentence it attributes does not get pasted.

        It is not a proof that the figure beside it came from here. Nothing
        short of the board emitting the figure itself could be, and a lane that
        pastes this next to a number it copied off a stale board has told a
        lie this string cannot catch. What it removes is the excuse: the honest
        form now costs one command and one paste.
        """
        how = "consulted" if self.asked else "attributed"
        alive, held = self.verdicts or (0, 0)
        if not self.oracles:
            oracle = "**no oracle** — outliner's own words"
        elif self.verdicts is not None and not alive:
            # The state that had no spelling, and the reason this is three
            # branches and not two. `oracles` says thirty parsers would answer;
            # this arm has asked none of them and holds no live verdict either,
            # so every `square` and `crooked` off it reads 0 - the same 0 that
            # thirty agreeing grammars print. Citing the court alone here hands
            # the next page the stronger of the two available lies.
            oracle = (f"oracle `{self.court[:9]}` seated but **no verdict live"
                      f" on this arm**{f' (0 of {held} held)' if held else ''}"
                      f" — `square` and `crooked` off it are unmeasured zeroes")
        else:
            oracle = (f"oracle `{self.court[:9]}`"
                      f" ({f'{alive} of {held} live, ' if self.verdicts else ''}"
                      f"{len(self.oracles)} {how})")
        return (f"outliner `{self.binary[:9]}` · tree `{self.tree[:9]}`"
                f" ({self.origin}) · {oracle}")


def take(arm: str, binary: Path | None = None, work: Path | None = None) -> Witness:
    """Record the world at one arm. Reads `stamp.FED`, so an instrument that
    already feeds its artifacts gets the artifact field for nothing.

    `work` is the seat to count live verdicts in, and it is a parameter rather
    than a default because the default belongs to the caller: `standing`,
    `plumb` and `collate` each spell `OUTLINER_WORK or ROOT/.local/standing`,
    and a fourth copy here is how a witness would come to disagree with the
    board it witnesses about which seat was read. Unset and unpassed means the
    liveness question was never put, which `Witness.verdicts` spells `None`.
    """
    binary = binary or Path(os.environ.get("OUTLINER_BIN", stamp.usual()))
    mani, origin = subject_of(binary)
    try:
        build, built = stamp.digest(binary), binary.stat().st_mtime
    except OSError:
        build, built = "missing", 0.0
    # An empty court is no court. A `digest` over zero rows is a hash of the CLI
    # string and would put a plausible-looking number in a field standing for
    # thirty parsers nobody asked, which is the shape of the hole this replaced.
    seen = seen_oracles()
    rows = seen.rows if seen else ()
    return Witness(
        arm=arm, when=time.time(), binary=build, built=built, where=str(binary),
        origin=origin, subject=mani, tree=fold(mani),
        live=stamp.survey(ROOT.resolve()).digest,
        work=os.environ.get("OUTLINER_WORK", ""),
        lane=os.environ.get("OUTLINER_LANE", ""),
        oracles={r.name: r.tree for r in rows if r.tree},
        artifacts={p: s[0].mark for p, s in stamp.FED.items()},
        cli=seen.cli if rows else "",
        court=seen.digest if rows else "",
        rule=oracle_rule(),
        asked=any(r.asked for r in rows),
        lowered={r.name: r.lower for r in rows if r.asked and r.lower},
        # `None`, not `(0, 0)`: an arm nobody named a seat for has not been
        # looked at, and saying "looked, holds nothing" of it would be the same
        # conflation this field exists to undo, one level up.
        verdicts=live_verdicts(Path(seat), binary)
        if (seat := work or os.environ.get("OUTLINER_WORK")) else None,
    )


def live_verdicts(work: Path, binary: Path) -> tuple[int, int]:
    """How many of an arm's cached verdicts a board on it would actually accept.

    `Held.matches` minus `source`, which is a property of the repo and not of
    the arm: the folio digest, the binary digest, and a non-empty oracle. All
    three have been the difference between a four-minute sweep and nothing -
    two caches on this disk carry thirty verdicts apiece under `folio: missing`,
    minted by lanes that ran `--audit` in a work dir cold enough that the folio
    they were about had not been pressed yet.

    Cheap on purpose (~18 ms over thirty): `pin.py arm` is a line of shell a
    lane evaluates constantly, and a check that opened thirty folios would be a
    check somebody turns off.

    It lives here rather than in `pin.py` because the *witness* is what needs
    it, and an arm is not always a pin - `(work, binary)` is the pair every arm
    has. `pin.oracled` is now a caller. Two copies of this would be two
    instruments disagreeing about whether an arm can see, which is the same
    class of split the identity rule is kept in `attest` to avoid.
    """
    try:
        got = json.loads((work / "audit.json").read_text())
    except (OSError, ValueError):
        return 0, 0
    mine = stamp.digest(binary)[:16] if binary.is_file() else ""
    live = 0
    for name, v in got.items():
        folio = work / f"{name}.folio"
        if (isinstance(v, dict) and v.get("oracle") and v.get("binary") == mine
                and folio.is_file() and v.get("folio") == stamp.digest(folio)[:16]):
            live += 1
    return live, len(got)


def oracle_rule() -> str:
    """The version of `attest`'s identity rule, or "" when `attest` is not here.

    Recorded rather than assumed, because the rule has already changed once and
    the change was indistinguishable from the oracle itself moving: three pins
    taken this morning disagree with two taken this afternoon on all thirty
    grammars, over bytes that never moved. A witness that carries the rule turns
    that into one refusal that says *these two numbers were minted by different
    rulers*, instead of thirty that say the parser changed.
    """
    try:
        import attest
    except ImportError:
        return ""
    return attest.rule()


def seen_oracles():
    """The court this run's numbers rest on, or `None` if there is none.

    Reads `attest.SEATED` rather than re-deriving, because the identity rule is
    `attest`'s to own and a second copy of it here is how two instruments come
    to disagree about what a parser is. `SEATED` is set by the two calls that
    actually stand an oracle up - `attest.consult` before a reading, and
    `attest.attribute` when a board names the judge its cached rows were already
    measured against.

    The fallback below is the part that matters, and it is why this reads `0` no
    longer. It used to take *the stem of every `.json` the run was fed* and ask
    `oracle_home` about it, so a run that fed `lang/latex/src/grammar.json`
    looked up a grammar called **`grammar`**, found nothing, and reported no
    oracles - on every board, for as long as the field has existed. Recovering
    the grammar from the fed path instead means an instrument that consults an
    oracle without going through `attest` is still witnessed, which is the case
    a hand-written record would miss.
    """
    try:
        import attest
        import differential as d
    except ImportError:
        return None
    if attest.SEATED is not None:
        return attest.SEATED
    homes: dict[str, Path] = {}
    for raw in stamp.FED:
        p = Path(raw)
        if p.name not in ("grammar.json", "parser.c") or "src" not in p.parts:
            continue
        # The home is the directory holding `src/`, whatever depth the monorepo
        # grammars put it at - not the stem of the file, which is how thirty
        # oracles became zero.
        home = Path(*p.parts[:len(p.parts) - 1 - p.parts[::-1].index("src")])
        homes.setdefault(d.named(home), home)
    if not homes:
        return None
    # `asking=False` because a witness must not change what it witnesses: the
    # asking form feeds the oracle's sources to the generation ledger, and this
    # runs one line before the ledger is read into `artifacts`. The run really
    # did ask - it fed a `grammar.json` - so the flag is restored afterwards,
    # and `lowered` stays empty rather than paying 28 MB of scala's `parser.c`
    # inside a record that is supposed to be free.
    rows = tuple(attest.read(SimpleNamespace(lang=home), asking=False)
                 ._replace(asked=True)
                 for _, home in sorted(homes.items()))
    return attest.Court(rows, attest.oracle_cli(), time.time())


def stems() -> dict[str, str]:
    """The population rule this file used before today, kept so it can disagree.

    Same idiom as `attest.was` and `stamp.py --verdicts`, and the same reason: a
    change to a discriminator is only *demonstrated* if the thing it replaced is
    present to read differently. Without this, the end-to-end rows below would
    show the new rule filling the field, which proves the new rule is
    self-consistent - and every rule is that. With it, one run in one process
    reads `0 oracle(s)` under the retired rule and `1` under the current one,
    which is the hole itself, restored.
    """
    try:
        import differential as d
    except ImportError:
        return {}
    import attest
    out = {}
    for name in sorted({p.stem for p in map(Path, stamp.FED) if p.suffix == ".json"}):
        try:
            if got := attest.survey(d.oracle_home(name))[0]:
                out[name] = got
        except (OSError, ValueError, KeyError):
            continue
    return out


def keep(w: Witness) -> Path:
    WITNESS.mkdir(parents=True, exist_ok=True)
    at = WITNESS / f"{w.arm}.json"
    at.write_text(json.dumps(w.as_dict(), indent=2, sort_keys=True) + "\n")
    return at


def revive(got: dict) -> Witness:
    """A witness back out of whatever wrote it down.

    Kept apart from `recall` because the interesting caller is not the witness
    store: an instrument that embeds its witness in its own saved output - which
    `standing.py --json` now does - hands the pair straight to `differ` without
    either arm having to have been named at the time.
    """
    got = dict(got)
    got.pop("subject_files", None)
    # Only the fields that are there. A witness written before the oracle half
    # existed is the normal case for every file already on disk, and the fields
    # it lacks default to "did not say" - which is true of it, and which `differ`
    # reports as `unrecorded` rather than as agreement.
    return Witness(**{k: got[k] for k in Witness._fields if k in got})


def carried(where: Path) -> Witness | None:
    """The witness inside somebody's saved artifact, if it carries one.

    `None` rather than a raise, because a board saved before boards carried
    witnesses is the *normal* case for every file already on disk, and a
    comparison involving one has to degrade to fewer fields rather than refuse
    to run. Refusing there would make the gate's first act be breaking three
    lanes' existing before-files.
    """
    try:
        got = json.loads(where.read_text())
    except (OSError, ValueError):
        return None
    return revive(got["witness"]) if isinstance(got.get("witness"), dict) else None


def recall(arm: str) -> Witness:
    """A witness by arm name, or out of a saved artifact if `arm` is a path."""
    if (at := Path(arm)).suffix and at.exists() and (got := carried(at)):
        return got
    return revive(json.loads((WITNESS / f"{arm}.json").read_text()))


# -------------------------------------------------------------- the comparison


class Divergence(NamedTuple):
    """One field two arms disagree on, and whether that sinks the comparison."""

    field: str
    verdict: str  # refuse · warn · declared
    said: str
    detail: tuple[str, ...] = ()

    def line(self) -> str:
        # `.get` rather than `[]`: a verdict this table has not heard of is a
        # reason to print it loudly, not to crash the report that carries it.
        # `vacuous` was missing here, so the sixth case - the one the gate was
        # built for - raised KeyError on its way to being told.
        head = {"refuse": "REFUSE", "warn": "warn", "declared": "ok"}.get(
            self.verdict, self.verdict.upper())
        out = [f"still: {head} - {self.field}: {self.said}"]
        out += [f"    {d}" for d in self.detail[:12]]
        if len(self.detail) > 12:
            out.append(f"    (+{len(self.detail) - 12} more)")
        return "\n".join(out)


def claimed(rel: str, mine: tuple[str, ...]) -> bool:
    """Does this lane say this file is its own change?

    Three spellings, because the one-path spelling is the loose direction
    arriving by the back door. A real lane's change is `src/press/` and not one
    file, and a gate that makes you enumerate fourteen paths to run one
    comparison is a gate whose `--mine` list stays empty - after which
    everything is unclaimed, everything refuses, and the flag comes off.

    - an exact path
    - a directory, with or without its slash, claiming everything under it
    - a glob, for the cases neither of those spells (`src/**/latex*.zig`)
    """
    import fnmatch
    for want in mine:
        want = want.strip()
        if not want:
            continue
        if rel == want or rel.startswith(want.rstrip("/") + "/"):
            return True
        if any(c in want for c in "*?[") and fnmatch.fnmatch(rel, want):
            return True
    return False


def kind(path: str) -> str:
    """What sort of evidence one artifact is.

    A folio is a **pressed table**; a `grammar.json` is what it was pressed from;
    a binary is the runtime. They are different objects and a change moves some
    and cannot move others, which is why they are counted apart rather than
    summed into one reassuring total.
    """
    suffix = Path(path).suffix
    return {".folio": "folio", ".json": "grammar"}.get(suffix, "artifact")


def vacuous(a: Witness, b: Witness, varying: tuple[str, ...],
            inert: bool) -> list[Divergence]:
    """Evidence that could not have observed the change it is being used to clear.

    The sixth case, and the subtlest: a lane offered *all 30 folios byte-identical
    across both arms* as proof that its scanner seating broke nothing. Every folio
    carried its minter's digest, the tickets were real, the arms were taken
    against the same world, nothing wrote to anything. **The check is sound and it
    is about the wrong object** - a folio is a pressed table and a seating cannot
    move one, so 30 of 30 agreeing is true, verifiable, and says nothing at all
    about collateral damage.

    A machine cannot generally know which artifact a change *should* move. It can
    know something narrower and sufficient:

        an instrument that did not respond to the treatment cannot clear it.

    If the two arms' binaries differ and **every** item of an evidence class is
    byte-identical, that class did not observe the change. Either it is the wrong
    instrument for this change, or the change did nothing - and in both readings a
    negative result from it is not evidence of absence. So it is reported as
    `vacuous` rather than passed over in silence, because silence is what the lane
    filled in with "no collateral" both times this happened.

    This is the mirror of the binary rule above, reached from the other side: that
    one refuses arms that are equal by construction, this one refuses *evidence*
    that is. Declining it is `--inert`, which is the honest claim a refactor makes
    - *I assert this moves nothing, and identity is my result rather than my
    clearance.*
    """
    if inert or "binary" not in varying or a.binary == b.binary:
        return []
    out = []
    pools: dict[str, list[tuple[str, str, str]]] = {}
    for path in sorted(set(a.artifacts) & set(b.artifacts)):
        pools.setdefault(kind(path), []).append(
            (path, a.artifacts[path], b.artifacts[path]))
    # Oracles are deliberately **not** pooled here. An oracle is a controlled
    # variable - case 3 refuses precisely because two arms' oracles differed - so
    # asking it to move would inverse the rule that holds it still. Vacuity is a
    # question about *outcomes*, and only the artifacts a run produced are that.
    for what, rows in sorted(pools.items()):
        if not rows or any(x != y for _, x, y in rows):
            continue
        out.append(Divergence(
            what, "vacuous",
            f"all {len(rows)} {what}(s) are byte-identical across two arms whose"
            f" binaries differ, so this evidence never observed your change."
            f" An instrument that did not respond to the treatment cannot clear"
            f" it — pass --inert if identity IS your result rather than your"
            f" proof of no collateral",
            tuple(f"{stamp.here(Path(p))}  {x[:9]}  unmoved" for p, x, _ in rows)))
    return out


def judged(a: Witness, b: Witness, varying: tuple[str, ...] = ()) -> list[Divergence]:
    """Whether the two arms were judged by the same other parser.

    `square` is the only number on this board that is a claim about *agreement
    with a second parser*, so the second parser is a controlled variable and two
    arms that had different ones did not run a comparison. The tree half of this
    gate already refuses on the source tree; this is the same refusal about the
    judge, and it needs the same care about which differences are fatal, because
    a rule that fires on every honest before/after gets passed with a flag.

    Fatal, in the order they are checked:

    * **the rule** the two identities were computed under, before anything else -
      because when it differs, every row below disagrees for a reason that has
      nothing to do with any parser, and reporting thirty drifts would bury the
      one fact that explains them;
    * **the CLI**, once rather than thirty times - `tree-sitter generate` is what
      lowered every one of these, and a run under a different one is a different
      judge across the board;
    * **the authored identity** of any grammar *both* arms consulted;
    * **the generated parser** under an identity that holds - a torn tree, where
      the `parser.c` answering questions was not produced from the `grammar.json`
      beside it. `oracle_build` regenerates only when the grammar digests differ,
      so this state is reachable and is invisible to the identity by design.

    Not fatal:

    * a grammar one arm consulted and the other did not - the shared set is still
      a comparison, and saying so on fewer rows is better than refusing;
    * one arm having asked an oracle and the other only citing one, or not
      recording the field at all - fewer fields, like `unrecorded` above.

    Silent, and this is the row that makes the gate livable: the seat, the
    library path, the library's bytes, and which pin tag the copy came from. None
    of them can change a verdict, and `pin.py arm` hands every arm its own seat
    **by design** - so a gate that read them would refuse every honest
    before/after taken on this machine. They are not compared because the witness
    does not record them, which is a stronger guarantee than remembering not to.
    """
    out: list[Divergence] = []
    named = "oracle" in varying
    if not a.oracles and not b.oracles:
        return out
    if not a.oracles or not b.oracles or a.asked != b.asked:
        return [Divergence(
            "oracle", "warn",
            f"one arm rests on an oracle and the other does not say it does"
            f" ({len(a.oracles)} {'consulted' if a.asked else 'attributed'}"
            f" vs {len(b.oracles)} {'consulted' if b.asked else 'attributed'}),"
            " so the judge is outside this comparison")]

    if a.rule and b.rule and a.rule != b.rule:
        # The one that was actually costing measurements. Three pins taken this
        # morning and two this afternoon disagree on all thirty grammars over
        # bytes that never moved, because `survey` stopped folding generated
        # files into the identity in between. Checked first and returned on,
        # because every row below would otherwise fire for that reason and the
        # thirty would read as drift.
        return [Divergence(
            "oracle", "refuse",
            f"the two arms' oracle identities were computed under different"
            f" RULES ({a.rule[:9]} vs {b.rule[:9]}), so their digests are not"
            f" comparable and the rows below would read as {len(set(a.oracles) & set(b.oracles))}"
            f" drifts that never happened; re-take the older arm, or re-freeze"
            f" its pin with `attest.py freeze`")]

    if a.cli != b.cli:
        out.append(Divergence(
            "oracle", "declared" if named else "refuse",
            f"the two arms were judged by different tree-sitter CLIs"
            f" ({a.cli or '(unrecorded)'} vs {b.cli or '(unrecorded)'}), which"
            f" lowered every one of these {len(a.oracles)} grammar(s)"))

    both = sorted(set(a.oracles) & set(b.oracles))
    if moved := [n for n in both if a.oracles[n] != b.oracles[n]]:
        out.append(Divergence(
            "oracle", "declared" if named else "refuse",
            f"{len(moved)} grammar(s) both arms consulted were judged by"
            f" different parsers",
            tuple(f"{n}  {a.oracles[n][:9]} vs {b.oracles[n][:9]}" for n in moved)))

    if torn := [n for n in both if a.oracles[n] == b.oracles[n]
                and a.lowered.get(n, "") and b.lowered.get(n, "")
                and a.lowered[n] != b.lowered[n]]:
        out.append(Divergence(
            "oracle", "refuse",
            f"{len(torn)} grammar(s) have one identity and two generated parsers,"
            f" so at least one arm was answered by a `parser.c` that was not"
            f" produced from the `grammar.json` beside it",
            tuple(f"{n}  {a.lowered[n][:9]} vs {b.lowered[n][:9]}" for n in torn)))

    if only := sorted(set(a.oracles) ^ set(b.oracles)):
        out.append(Divergence(
            "oracle", "warn",
            f"{len(only)} grammar(s) were consulted by one arm only, so the"
            f" comparison holds over the {len(both)} they share",
            tuple(f"{n}  {'a' if n in a.oracles else 'b'} only" for n in only)))

    if named and not moved and a.cli == b.cli:
        out.append(Divergence(
            "oracle", "refuse",
            f"both arms were judged by the same oracle ({a.court[:9]}) while"
            " claiming to vary it, so whatever this measured, it was not a"
            " change of judge"))
    return out


def differ(a: Witness, b: Witness, mine: tuple[str, ...] = (),
           varying: tuple[str, ...] = ("binary",), inert: bool = False) -> list[Divergence]:
    """Every way two arms' worlds are not the same one.

    `varying` is what the comparison says it is changing - a before/after varies
    `binary` and nothing else. `mine` is the far more interesting knob: the source
    files the lane claims as its own change. Anything else that moved between the
    two subjects is a file the lane did not touch and did not know about, which is
    the fifth case in one line.

    A refusal is not "these differ" - two arms of a before/after are *supposed* to
    differ. It is "these differ in a way you did not declare".
    """
    out: list[Divergence] = []

    # Both directions, and the second one is case two. A comparison that declares
    # it is varying the binary and then runs the same bytes twice is not a
    # before/after; `specimen` scored a run against a stale binary as if it were
    # attributed, and this is that in general form. Inverted for a null arm, where
    # two arms running one binary is the requirement rather than the defect.
    if "binary" in varying and a.binary == b.binary:
        out.append(Divergence(
            "binary", "refuse",
            f"both arms ran the same bytes ({a.binary[:9]}) while claiming to vary"
            " the binary, so whatever this measured, it was not your change"))
    if "binary" not in varying and a.binary != b.binary:
        out.append(Divergence("binary", "refuse",
                              f"{a.binary[:9]} vs {b.binary[:9]}, and nothing declared it"))

    # The fifth case lives here. Both arms are pins, both are internally honest,
    # and the only thing that can tell them apart is which FILES their two source
    # trees differ in - because the lane knows which one it changed.
    if "unrecorded" in (a.origin, b.origin):
        out.append(Divergence(
            "subject", "warn",
            f"one arm cannot say what it was built from ({a.origin} vs {b.origin}),"
            " so this comparison is on fewer fields than it looks"))
    else:
        moved = sorted(set(a.subject) | set(b.subject))
        moved = [r for r in moved if a.subject.get(r) != b.subject.get(r)]
        yours = {r: claimed(r, mine) for r in moved}
        # The crux, and it is not decidable from *who* wrote a file - nothing on
        # disk records that. Two facts that ARE on disk decide it: whether the
        # lane claimed the file, and whether the file can move a product binary
        # at all. `stamp.builds` already draws the second line, for this exact
        # reason: with ten lanes editing tests continuously, a gate that fired on
        # a sibling's `*_test.zig` would fire most of the time, and a gate that
        # fires most of the time is one people learn to pass with `--mine '*'`.
        #
        # So an unclaimed test edit is a note about how the trees differ, and an
        # unclaimed *build-bearing* edit is the latex case verbatim and sinks the
        # comparison. Erring loose here would clear nothing; erring strict here
        # would make the tool unusable on the tree it was written for.
        heavy = [r for r in moved if not yours[r] and stamp.builds(r)]
        light = [r for r in moved if not yours[r] and not stamp.builds(r)]
        rows = tuple(f"{r}  {'yours' if yours[r] else 'NOT YOURS'}"
                     f"{'' if stamp.builds(r) else '  (test only)'}" for r in moved)
        if heavy:
            out.append(Divergence(
                "subject", "refuse",
                f"the two arms were built from trees differing in {len(moved)} file(s),"
                f" {len(heavy)} of which you have not claimed and could move the binary",
                rows))
        elif light:
            out.append(Divergence(
                "subject", "warn",
                f"{len(moved)} file(s) differ; {len(light)} unclaimed, all of them test"
                " files, which no product binary is built from", rows))
        elif moved:
            out.append(Divergence("subject", "declared",
                                  f"{len(moved)} file(s) differ and you claim all of them",
                                  tuple(moved)))

    # Case one's precondition, checkable directly and before anything is pressed:
    # two arms that pressed into one cache are one cache with two names on it.
    #
    # Asked only of two arms running *different bytes*. A derived artifact is a
    # function of the binary that derived it, so one cache holding one binary's
    # folios cannot mix two arms up - there is only one arm in it. Without this
    # guard the rule fires on the honest repeat: `--twice` runs one pin N times
    # in one environment, which is a stability question and not a comparison,
    # and refusing it would make the reproducibility check unrunnable.
    for field, what in (("work", "folio cache"), ("lane", "oracle seat")):
        x, y = getattr(a, field), getattr(b, field)
        if x == y and a.binary != b.binary:
            out.append(Divergence(
                field, "refuse",
                f"both arms share one {what} ({x or 'the default'}); a derived"
                f" artifact in it cannot say which arm made it"))

    out += judged(a, b, varying)

    for path in sorted(set(a.artifacts) & set(b.artifacts)):
        if a.artifacts[path] != b.artifacts[path] and Path(path).suffix != ".folio":
            out.append(Divergence(
                "artifact", "refuse",
                f"{stamp.here(Path(path))}: read as two different things"
                f" ({a.artifacts[path][:9]} vs {b.artifacts[path][:9]})"))

    if a.live != b.live:
        out.append(Divergence(
            "live", "warn",
            f"the repo moved between the two arms ({a.live[:9]} -> {b.live[:9]});"
            " harmless for two pins, fatal for two unpinned runs"))
    return out + vacuous(a, b, varying, inert)


def sank(rows: list[Divergence]) -> bool:
    """`vacuous` sinks a comparison as surely as `refuse` does, and that is the
    whole of the sixth case. The two are kept apart in the output because they
    need different sentences: `refuse` means *these arms are not comparable*,
    `vacuous` means *they are perfectly comparable and you compared the wrong
    thing*."""
    return any(r.verdict in ("refuse", "vacuous") for r in rows)


# ------------------------------------------------------------------- the seal


class Wrote(NamedTuple):
    path: str
    op: str
    site: str
    when: float


class Tainted(Exception):
    """A run read, as evidence, something it had written itself."""


_WROTE: dict[str, Wrote] = {}
_MINE: tuple[Path, ...] = ()
_ON = False
_PATCHED: list[tuple[object, str, object]] = []
_FAULTS: list[Wrote] = []


def _site() -> str:
    for fr in reversed(traceback.extract_stack()):
        if Path(fr.filename).name not in ("still.py", "pathlib.py", "shutil.py"):
            return f"{Path(fr.filename).name}:{fr.lineno} in {fr.name}"
    return "?"


def private(path: Path) -> bool:
    """Is this somewhere only this arm writes?

    Derived from the environment `pin.py arm` sets rather than from a list: a run
    that armed itself has said where its private space is, and a run that did not
    has an empty one, so an unarmed run's every shared write is a fault. Failing
    closed on the unarmed case is the point - that run has no claim to comparability
    in the first place.
    """
    try:
        real = path.resolve()
    except OSError:
        real = path
    return any(real == m or m in real.parents for m in _MINE)


def held(path: Path) -> bool:
    """Is a lock held, by this process, over the unit this path belongs to?

    A write into shared state under a lock the writer owns is a mint, not a
    defect - that is exactly the repair `oracle_build` received, and a gate that
    fired on it would be a gate nobody leaves on. Asked of `differential`'s own
    re-entrant register rather than re-derived, because two answers to "who holds
    this" is the same defect one layer up.
    """
    try:
        import differential as d
        parts = path.resolve().parts
        return "lang" in parts and parts[parts.index("lang") + 1] in d._HELD
    except (ImportError, IndexError, ValueError, OSError):
        return False


def _note(op: str, path) -> None:
    if not _ON or path is None:
        return
    try:
        p = Path(os.fspath(path))
    except TypeError:
        return  # a file descriptor, not a path; the fd's opener was already noted
    if private(p) or held(p):
        return
    _WROTE[str(p.resolve() if p.exists() else p.absolute())] = Wrote(
        str(p), op, _site(), time.time())


def _wrap(mod, name: str, argno: int = 0, op: str = "") -> None:
    real = getattr(mod, name)

    def shim(*args, **kw):
        _note(op or name, args[argno] if len(args) > argno else None)
        return real(*args, **kw)

    _PATCHED.append((mod, name, real))
    setattr(mod, name, shim)


def _wrap_open(mod) -> None:
    real = getattr(mod, "open")

    def shim(file, mode="r", *a, **kw):
        if any(c in str(mode) for c in "wax+"):
            _note(f"open({mode})", file)
        return real(file, mode, *a, **kw)

    _PATCHED.append((mod, "open", real))
    setattr(mod, "open", shim)


def _wrap_run() -> None:
    """Bracket a child with a digest of the directory it was handed.

    The seal's in-process half cannot see `tree-sitter generate`, and that is the
    half defect four needed. The cwd subtree is the right scope because it is
    where a child is *pointed* rather than a guess about what it might touch, and
    it is derived from the call rather than configured. A child that writes
    outside its own cwd is a hole in this, stated rather than defended against.
    """
    real = subprocess.run

    def shim(*args, **kw):
        cwd = Path(kw.get("cwd") or ".")
        was = _snap(cwd) if _ON else None
        got = real(*args, **kw)
        if _ON and was is None:
            _BLIND.append(str(cwd))
        elif _ON:
            now = _snap(cwd) or {}
            for rel, mark in now.items():
                if was.get(rel) != mark:
                    _note("child wrote", cwd / rel)
            for rel in was:
                if rel not in now:
                    _note("child deleted", cwd / rel)
        return got

    _PATCHED.append((subprocess, "run", real))
    subprocess.run = shim


# A generated `parser.c` runs to 28 MB on scala, so a bracket that digests
# without a ceiling turns a seconds-long compile into a minutes-long one. Past
# the ceiling the bracket falls back to size+mtime, which is strictly weaker and
# says so in the finding rather than quietly reporting agreement.
CEILING = 64 << 20
# How many files a bracket will watch before it declines. The number is not a
# performance knob, it is a soundness one, and it was set by watching this
# detector lie: `collate.timed` runs its children with `cwd=ROOT`, so the first
# bracket over a real instrument snapshotted the whole repository and attributed
# eleven *sibling lanes'* concurrent writes to collate's child. On a tree ten
# agents write to, a wide bracket does not observe a child, it observes the hour.
#
# So a bracket it cannot make sound declines and says so, rather than producing
# findings with the right shape and the wrong owner. `_BLIND` is that admission,
# and it is printed whether or not anything else fired: a detector that goes
# quiet when it stops working is the shape this whole file is about.
WATCHABLE = 400
_BLIND: list[str] = []


def _snap(root: Path) -> dict[str, str] | None:
    """Digest the subtree a child was pointed at, or None if that would be a
    guess rather than an observation."""
    if not root.is_dir():
        return {}
    try:
        if root.resolve() == ROOT.resolve():
            return None
        leaves = [p for p in sorted(root.rglob("*")) if p.is_file()]
    except OSError:
        return None
    if len(leaves) > WATCHABLE:
        return None
    out: dict[str, str] = {}
    budget = CEILING
    for p in leaves:
        try:
            it = p.stat()
            rel = str(p.relative_to(root))
            if it.st_size <= budget:
                budget -= it.st_size
                out[rel] = stamp.digest(p)
            else:
                # Past the ceiling this is size+mtime, which is strictly weaker
                # than a digest and is why the fallback is spelled in the value
                # rather than hidden: scala's generated parser is 28 MB.
                out[rel] = f"stat:{it.st_size}:{it.st_mtime_ns}"
        except OSError:
            continue
    return out


@contextlib.contextmanager
def sealed(mine: tuple[Path, ...] = (), strict: bool = True) -> Iterator[list[Wrote]]:
    """Interpose the write primitives and hook the read that turns a write into
    evidence. Raises `Tainted` **at the read**, which is before any verdict that
    read supports - not at the end of the window, where the number is already out.
    """
    global _ON, _MINE
    if _ON:  # re-entrant: an inner window is the outer one
        yield _FAULTS
        return
    # What this arm is allowed to write and then read: the folio cache `pin.py
    # arm` handed it, and the system scratch space, which is where the house rule
    # about rsyncing a tree rather than editing a sibling's sends you. Not derived
    # from a list of paths - derived from the environment the arm was armed with,
    # so an UNARMED run has an empty private set and every shared write it reads
    # back is a fault. Failing closed there is the point: that run never had a
    # claim to comparability.
    work = os.environ.get("OUTLINER_WORK")
    _MINE = tuple(Path(p).resolve() for p in (
        *mine, *((work,) if work else ()), Path(os.environ.get("TMPDIR", "/tmp"))))
    _WROTE.clear()
    _FAULTS.clear()
    _BLIND.clear()
    real_fed = stamp.fed

    def fed(artifact, row: str = "") -> None:
        key = str(Path(artifact).resolve() if Path(artifact).exists()
                  else Path(artifact).absolute())
        if (bad := _WROTE.get(key)) is not None:
            _FAULTS.append(bad)
            if strict:
                raise Tainted(
                    f"still: SEAL - this run wrote {stamp.here(Path(bad.path))} at"
                    f" {bad.site} ({bad.op}) and is now reading it as evidence."
                    " The comparison's setup is mutating the thing being compared,"
                    " so the error runs toward agreement and the falsifier below"
                    " this line cannot see it.")
        real_fed(artifact, row)

    for mod in (builtins, io):
        _wrap_open(mod)
    # `mkdir` and `rmdir` are deliberately not here. A directory is never fed as
    # evidence, so watching them can only add rows nothing can ever promote to a
    # fault - and a detector whose output is mostly rows that cannot matter is one
    # people stop reading.
    for name in ("remove", "unlink", "rename", "replace", "truncate",
                 "symlink", "link"):
        _wrap(os, name)
    for name in ("copyfile", "copy", "copy2", "move", "rmtree"):
        _wrap(shutil, name)
    _wrap_run()
    _PATCHED.append((stamp, "fed", real_fed))
    stamp.fed = fed
    _ON = True
    try:
        yield _FAULTS
    finally:
        _ON = False
        for mod, name, real in reversed(_PATCHED):
            setattr(mod, name, real)
        _PATCHED.clear()


def wrote() -> list[Wrote]:
    return sorted(_WROTE.values(), key=lambda w: w.when)


def blind() -> list[str]:
    """Children this run could not watch. Always ask; a seal that reports no
    faults while declining every bracket has reported nothing."""
    return list(dict.fromkeys(_BLIND))


# -------------------------------------------------------------------- the proof


def stub(arm: str, **over) -> Witness:
    """A witness with every field agreeing, so a trial moves exactly one.

    Constructed rather than staged. Staging case five would mean landing a source
    edit on a tree ten lanes are working in, and an instrument that has to
    vandalise the tree to test itself is not one anybody runs. Every field below
    is a plain record, so the condition can be stated instead of caused - and the
    two cases that *can* be caused honestly (the seal's) are caused, in a scratch
    tree, further down.
    """
    base = dict(
        arm=arm, when=time.time(), binary="a" * 64, built=1.0, where="/pin/a/bin/outliner",
        origin="pin", subject={"src/kernel/table/press.zig": "1" * 64},
        tree="", live="l" * 64, work=f"/pin/{arm}/work", lane=f"pin-{arm}",
        oracles={"latex": "o" * 64}, artifacts={"/w/latex.folio": "f" * 64},
        cli="tree-sitter 0.26.11", court="c" * 64, rule="r" * 64, asked=True,
        lowered={"latex": "g" * 64})
    base.update(over)
    base["tree"] = fold(base["subject"])
    return Witness(**base)


def six() -> list[tuple[str, str, str, bool]]:
    """The six, restored as the conditions they are, against both detectors.

    Each row says which detector bit and which did not, because that is the
    honest result: the seal catches two of six and cannot catch the others, and
    a merged verdict would let it take credit for the witness's work.
    """
    rows: list[tuple[str, str, str, bool]] = []

    def row(what: str, got: list[Divergence], want: str, seal: str) -> None:
        fields = sorted({f"{d.field}!" if d.verdict == "vacuous" else d.field
                         for d in got if d.verdict in ("refuse", "vacuous")})
        said = ",".join(fields) or "nothing"
        rows.append((what, said, seal, want in fields))

    # 1. Two arms pressing into one folio cache: neither derived artifact in it
    #    can say which binary made it. Checkable before a single folio is minted.
    a = stub("before", work="/shared/work", lane="pin-before")
    b = stub("after", binary="b" * 64, work="/shared/work", lane="pin-after")
    row("1 · order.miss — two arms, one folio cache", differ(a, b), "work", "blind")

    # 2. A before/after whose two arms ran the same bytes. `specimen` scored a run
    #    against a stale binary as if it were attributed; the general form is an
    #    arm that is not the binary the comparison believes it is holding.
    a = stub("before")
    b = stub("after", work="/pin/after/work", lane="pin-after")
    row("2 · specimen — declared a variable that did not move", differ(a, b),
        "binary", "blind")

    # 3. A scanner refresh that unlinked the generated parser beside a file it
    #    rewrote with identical bytes: one grammar, two identities.
    a = stub("before")
    b = stub("after", binary="b" * 64, work="/pin/after/work", lane="pin-after",
             oracles={"latex": "p" * 64})
    row("3 · fetch_scanners — the two arms' oracles differ", differ(a, b),
        "oracle", "BITES")

    # 4. An unlocked `oracle_build`: the artifact itself was read as two things.
    a = stub("before")
    b = stub("after", binary="b" * 64, work="/pin/after/work", lane="pin-after",
             artifacts={"/w/latex.folio": "g" * 64, "/lang/latex/src/grammar.json": "z" * 64})
    a = a._replace(artifacts={**a.artifacts, "/lang/latex/src/grammar.json": "y" * 64})
    row("4 · oracle_build — one grammar read as two", differ(a, b), "artifact", "BITES")

    # 5. The lex lane's latex fix, landed in the eight minutes between two pins.
    #    The lane claims one file; the trees differ in two.
    a = stub("before")
    b = stub("after", binary="b" * 64, work="/pin/after/work", lane="pin-after",
             subject={"src/kernel/table/press.zig": "2" * 64,
                      "src/kernel/lex/latex.zig": "9" * 64})
    got = differ(a, b, mine=("src/kernel/table/press.zig",))
    row("5 · latex — the tree moved between the two pins", got, "subject", "blind")

    # 6. The subtlest, and the only one where **nothing is wrong with the arms**.
    #    A `Troupe` seating: comparable arms, real digests, honest tickets, and 30
    #    folios byte-identical offered as proof of no collateral. A folio is a
    #    pressed table and a seating cannot move one, so the agreement is true and
    #    empty. No other field has anything to say - which is exactly why the lane
    #    read the silence as clearance.
    folios = {f"/w/{g}.folio": "f" * 64 for g in ("latex", "css", "toml")}
    a = stub("before", subject={"src/kernel/lex/troupe.zig": "1" * 64},
             artifacts=folios)
    b = stub("after", binary="b" * 64, work="/pin/after/work", lane="pin-after",
             subject={"src/kernel/lex/troupe.zig": "2" * 64}, artifacts=folios)
    got = differ(a, b, mine=("src/kernel/lex/troupe.zig",))
    row("6 · troupe — 30 folios agreeing about the wrong artifact", got,
        "folio!", "blind")
    return rows


def honest() -> list[tuple[str, str, bool]]:
    """The other direction: two arms that differ **only** in their binary, and a
    null arm that differs in nothing. A gate that refuses these is a gate that
    gets switched off inside a day, which would make it the sixth instance."""
    out = []

    def said(got: list[Divergence]) -> str:
        return ",".join(sorted({f"{d.field}!" if d.verdict == "vacuous" else d.field
                                for d in got if d.verdict in ("refuse", "vacuous")})) or "clean"

    # A press change, which is the one class of change folio identity really does
    # clear - because a press change **moves folios**, so the ones that held still
    # held still against an instrument demonstrably able to move.
    a = stub("before")
    b = stub("after", binary="b" * 64, work="/pin/after/work", lane="pin-after",
             subject={"src/kernel/table/press.zig": "2" * 64},
             artifacts={"/w/latex.folio": "g" * 64, "/w/css.folio": "c" * 64})
    a = a._replace(artifacts={**a.artifacts, "/w/css.folio": "c" * 64})
    got = differ(a, b, mine=("src/kernel/table/press.zig",))
    out.append(("a press change: latex's folio moved, css's did not — real clearance",
                said(got), not sank(got)))
    # The same shape with nothing moving is the sixth case, and `--inert` is the
    # only honest way to hold it: a claim of equivalence, not of no-collateral.
    b = b._replace(artifacts=dict(a.artifacts))
    out.append(("...the same arms with no folio moving at all: must refuse",
                said(differ(a, b, mine=("src/kernel/table/press.zig",))),
                sank(differ(a, b, mine=("src/kernel/table/press.zig",)))))
    out.append(("...and passes only once declared --inert, which claims equivalence",
                said(differ(a, b, mine=("src/kernel/table/press.zig",), inert=True)),
                not sank(differ(a, b, mine=("src/kernel/table/press.zig",), inert=True))))
    # The fifth lane's own falsifier, made a mode: the reverted tree pinned last,
    # which must be inert. `varying=()` inverts the binary rule - here two arms
    # running the same bytes is the requirement rather than the defect.
    a = stub("control-early")
    b = stub("control-late", work="/pin/late/work", lane="pin-late")
    got = differ(a, b, varying=())
    out.append(("a null arm: same subject, same bytes, pinned twice",
                ",".join(sorted({d.field for d in got if d.verdict == "refuse"})) or "clean",
                not sank(got)))
    # And the null arm must fail when the tree moved under it, which is what the
    # fifth lane actually saw. Same subject claim, different subject.
    b = b._replace(subject={"src/kernel/lex/latex.zig": "9" * 64})
    b = b._replace(tree=fold(b.subject))
    got = differ(a, b, varying=())
    out.append(("...and the same null arm over a tree that moved: must refuse",
                ",".join(sorted({d.field for d in got if d.verdict == "refuse"})) or "clean",
                sank(got)))

    # The crux, from both sides. Getting it strict makes the gate unusable on a
    # tree ten lanes write to; getting it loose makes it clear nothing. These
    # four rows are the line, and each is a claim that would be easy to break by
    # tightening or loosening one predicate.
    press = "src/kernel/table/press.zig"
    a = stub("before")
    # A moved folio, so these four rows isolate the subject predicate: with the
    # artifacts held identical the vacuity rule fires on every one of them, and
    # a proof row that can only ever say `folio!` is testing the wrong thing.
    b = stub("after", binary="b" * 64, work="/pin/after/work", lane="pin-after",
             artifacts={"/w/latex.folio": "g" * 64},
             subject={press: "2" * 64, "src/kernel/lex/scanner_test.zig": "7" * 64})
    got = differ(a, b, mine=(press,))
    out.append(("a sibling's TEST edit landed between two arms: a note, not a"
                " refusal — no product binary is built from one",
                said(got), not sank(got)))
    # ...and the same shape with a file that CAN move the binary is case five.
    b = b._replace(subject={press: "2" * 64, "src/kernel/lex/latex.zig": "9" * 64})
    got = differ(a, b, mine=(press,))
    out.append(("...the same arms where the sibling's file was a source file:"
                " must refuse", said(got), sank(got)))
    # A lane whose change is a directory. Spelling every file under it is the
    # loose direction by the back door: nobody does it, so nothing is claimed.
    b = b._replace(subject={press: "2" * 64, "src/press/fork.zig": "3" * 64})
    got = differ(a, b, mine=("src/press/", press))
    out.append(("a lane claiming a DIRECTORY as its change", said(got), not sank(got)))
    got = differ(a, b, mine=("src/**/*.zig",))
    out.append(("...and a lane claiming a glob", said(got), not sank(got)))
    # `--twice`: one pin, N processes, one environment. A stability question and
    # not a comparison, so the shared-cache rule must hold its tongue - it is
    # about two binaries' artifacts being confusable, and there is one binary.
    a = stub("run 1", work="/pin/x/work", lane="pin-x")
    b = stub("run 2", work="/pin/x/work", lane="pin-x")
    got = differ(a, b, varying=())
    out.append(("`--twice`: one binary, one cache, one seat, twice", said(got),
                not sank(got)))
    return out


def caused(tmp: Path) -> list[tuple[str, str, bool]]:
    """The seal, driven by defects three and four **actually performed** in a
    scratch tree - a write, then a read of what was written, then the raise.

    Constructed witnesses are fine for a record comparison; a detector that
    interposes the write primitives has to be shown interposing them.
    """
    import differential as d
    out: list[tuple[str, str, bool]] = []
    lang = tmp / "lang" / "latex" / "src"
    lang.mkdir(parents=True)
    (lang / "grammar.json").write_bytes(b'{"name":"latex"}')
    (lang / "parser.c").write_bytes(b"/* generated */")
    (lang / "scanner.c").write_bytes(b"// authored")
    work = tmp / "work"
    work.mkdir()
    # The defects are written to a module of their own and imported, rather than
    # closed over here. The seal's claim is not "something moved" but "YOUR LINE
    # moved it", and a proof whose writer is the detector's own file cannot show
    # that: `_site` skips its own frames, so every finding would read `?`. A
    # separate file is the only way the attribution column means anything.
    flaw = tmp / "flaw.py"
    flaw.write_text(FLAW)
    sys.path.insert(0, str(tmp))
    import importlib
    hand = importlib.import_module("flaw")
    sys.path.remove(str(tmp))

    def trial(what: str, doing, reads: str, want: bool, lock: str = "") -> None:
        """Do the thing, then read back the artifact it was supposed to leave
        alone. `reads` is named per trial rather than fixed: a scanner refresh
        and a grammar overwrite damage different files, and feeding one of them
        the other's artifact would be a gate passing itself."""
        stamp.FED.clear()
        with sealed():
            if lock:
                d._HELD[lock] = (1, True)
            try:
                doing()
                stamp.fed(lang / reads, "latex")
                got, said = False, "read back, no complaint"
            except Tainted as e:
                got, said = True, str(e).split(" at ")[1].split(" (")[0]
            finally:
                d._HELD.pop(lock, None)
        out.append((what, said, got == want))

    # Defect 3 restored: the unconditional rewrite plus the unlink beside it.
    trial("3 restored · rewrite the scanner, unlink the parser beside it",
          lambda: hand.unconditional(lang), "scanner.c", True)

    # Defect 3 repaired: `refresh` writes only when the bytes actually differ, so
    # a warm run touches nothing. This is the row that says the gate is livable.
    (lang / "parser.c").write_bytes(b"/* generated */")
    trial("3 repaired · write only a scanner that actually changed",
          lambda: hand.conditional(lang), "scanner.c", False)

    # Defect 4 restored: the shared grammar overwritten with no lock held.
    (tmp / "want.json").write_bytes(b'{"name":"latex","v":2}')
    trial("4 restored · overwrite a shared grammar.json holding no lock",
          lambda: hand.unlocked(lang, tmp / "want.json"), "grammar.json", True)

    # Defect 4 repaired: the same write, under the lock the writer now owns. A
    # mint is not a defect, and a gate that could not tell them apart would fire
    # on the repair — which would make the gate the sixth instance of the shape.
    trial("4 repaired · the same write, under the lock `oracle_build` now takes",
          lambda: hand.unlocked(lang, tmp / "want.json"), "grammar.json", False,
          lock="latex")

    # The child-process half. `tree-sitter generate` is a subprocess and the
    # in-process interposition is structurally blind to it, which is the whole
    # reason the bracket exists.
    trial("4 · a CHILD process writing it, which no interposition can see",
          lambda: hand.child(lang), "grammar.json", True)

    # And the seal must not fire on an arm writing into its own space, which is
    # every legitimate folio press. Without this row the gate could be a rule
    # against writing, which would stop every instrument in the tree.
    stamp.FED.clear()
    with sealed(mine=(work,)):
        hand.press(work)
        stamp.fed(work / "latex.folio", "latex")
        stamp.fed(lang / "scanner.c", "latex")
    out.append(("private · press a folio into this arm's own OUTLINER_WORK",
                "read back, no complaint", True))
    stamp.FED.clear()
    return out


def filled(tmp: Path) -> list[tuple[str, str, bool]]:
    """`take` itself, driven by real runs over a real grammar tree.

    The reason this table exists is written on the previous lane's own report:
    twenty-five rows held and the `oracles` field read **0 oracle(s) on every
    board**, because every one of those rows handed `differ` a `Witness` built
    by hand. A predicate proof cannot see a filler bug - it never calls the
    filler. So these rows call it, cause one thing at a time, and read the field
    back, and the first of them is the hole restored: the same fed ledger, in
    one process, read by the rule that shipped and by the rule that replaced it.

    Hermetic on purpose. Ten lanes are in the live tree and an instrument that
    has to write into `lang/` to test itself would be the seventh instance of
    the shape it exists to catch. `attest.survey` derives a grammar's root from
    the files themselves, so a scratch copy spells its files exactly as the live
    tree does and these digests are the digests.
    """
    import attest
    import differential as d
    out: list[tuple[str, str, bool]] = []
    home = tmp / "lang" / "latex"
    (home / "src").mkdir(parents=True)
    (home / "src" / "grammar.json").write_bytes(b'{"name":"latex"}')
    (home / "src" / "scanner.c").write_bytes(b"// authored\n" + b"x" * 400)
    (home / "src" / "parser.c").write_bytes(b"/* generated */\n" + b"y" * 400)
    case = SimpleNamespace(lang=home)

    def clean() -> None:
        stamp.FED.clear()
        attest.SEATED = None

    def row(what: str, said, ok: bool) -> None:
        out.append((what, said, ok))

    # --- the hole, restored. One fed ledger, two population rules, one process.
    clean()
    stamp.fed(home / "src" / "grammar.json", "latex")
    old, new = stems(), seen_oracles()
    row("THE HOLE · the retired rule on a run that DID consult an oracle",
        f"{len(old)} oracle(s)", not old)
    row("...and the current rule on the same fed ledger, same process",
        f"{len(new.rows) if new else 0} oracle(s)", bool(new and len(new.rows) == 1))

    # A run that fed a grammar but never went through `attest`: the fallback is
    # the whole reason this is not just `return attest.SEATED`.
    w = take("fed-only")
    row("...so `take` fills the field from the fed path, with no court seated",
        f"{len(w.oracles)} · {'asked' if w.asked else 'cited'}",
        list(w.oracles) == ["latex"] and w.asked)
    # ...and it must not have fed anything itself. A record that changes what it
    # records is the defect this whole file is about.
    row("...and witnessing it fed nothing of its own into the ledger",
        f"{len(stamp.FED)} artifact(s)", len(stamp.FED) == 1)

    # --- a run that really consults, which is the path that ships.
    clean()
    attest.consult([case])
    con = take("consulted")
    row("a run that consults: identity, CLI, court, rule and generated digest",
        f"{len(con.oracles)}+{len(con.lowered)} · {con.court[:9]}",
        bool(con.oracles and con.lowered and con.court and con.cli and con.rule))

    # --- a run that only ATTRIBUTES: a board reading a cached verdict rests on
    #     an oracle it never opened a file of, and must say which one without
    #     claiming to have asked it.
    clean()
    attest.attribute([case])
    att = take("attributed")
    row("a board citing the judge its CACHED rows were measured against",
        f"{len(att.oracles)} · {'asked' if att.asked else 'cited'}",
        att.oracles == con.oracles and not att.asked and not att.lowered)
    row("...and the two are not comparable as if both had asked",
        verdicts(judged(con, att)), verdicts(judged(con, att)) == "warn")

    # --- a run that asked nobody. The honest zero, which the hole was wearing.
    clean()
    none = take("no-oracle")
    row("a run that consulted no oracle at all: still zero, and now honestly",
        f"{len(none.oracles)} oracle(s)", not none.oracles and not none.court)
    row("...and comparing it against one that did is a warn, not a clearance",
        verdicts(judged(con, none)), verdicts(judged(con, none)) == "warn")

    # --- cause 1: an authored byte moves, so the identity must move.
    clean()
    attest.flip(home / "src" / "scanner.c")
    attest.consult([case])
    moved = take("scanner-moved")
    row("CAUSE · one authored byte flipped in `scanner.c`",
        f"{con.oracles['latex'][:9]} → {moved.oracles['latex'][:9]}",
        moved.oracles["latex"] != con.oracles["latex"])
    row("...and `differ` refuses the pair", verdicts(judged(con, moved)),
        verdicts(judged(con, moved)) == "refuse")

    # --- cause 2: the GENERATED parser is replaced under an identity that holds.
    #     A torn tree: `oracle_build` regenerates only when the grammar digests
    #     differ, so a `parser.c` from another generation is used as-is, and the
    #     identity is designed not to see it. Two digests, two questions.
    clean()
    (home / "src" / "parser.c").write_bytes(b"/* generated */\n" + b"z" * 400)
    attest.consult([case])
    torn = take("parser-torn")
    row("CAUSE · the generated `parser.c` replaced, authored bytes untouched",
        f"identity {'holds' if torn.oracles == moved.oracles else 'MOVED'}"
        f", lowered {'moves' if torn.lowered != moved.lowered else 'holds'}",
        torn.oracles == moved.oracles and torn.lowered != moved.lowered)
    row("...which `differ` refuses as a torn tree, not as a different grammar",
        verdicts(judged(moved, torn)), verdicts(judged(moved, torn)) == "refuse")

    # --- cause 3: the identity RULE itself changes, over bytes that did not.
    #     This is not hypothetical: three oracle pins on this machine were minted
    #     under the rule that folded generated files in, and read as thirty
    #     drifts against two minted after it stopped.
    clean()
    was, attest._RULE = attest.LOWERED, None
    attest.LOWERED = frozenset()
    attest.consult([case])
    ruled = take("other-rule")
    attest.LOWERED, attest._RULE = was, None
    row("CAUSE · the identity RULE changed; the oracle's bytes did not",
        f"{torn.rule[:9]} → {ruled.rule[:9]}", ruled.rule != torn.rule)
    said = judged(torn, ruled)
    row("...refused as incomparable RULERS, not reported as drift",
        verdicts(said), verdicts(said) == "refuse" and len(said) == 1
        and "RULES" in said[0].said)

    # --- and the fields the tree half already owns, caused rather than stated,
    #     because the same class of filler bug would be invisible in them too.
    clean()
    os.environ["OUTLINER_WORK"], os.environ["OUTLINER_LANE"] = str(tmp / "w"), "pin-x"
    try:
        env = take("environment")
    finally:
        for k in ("OUTLINER_WORK", "OUTLINER_LANE"):
            os.environ.pop(k, None)
    row("CAUSE · the arm's own workspace and seat, read from the environment",
        f"{Path(env.work).name} · {env.lane}",
        env.work.endswith("/w") and env.lane == "pin-x")
    clean()
    stamp.fed(home / "src" / "parser.c", "latex")
    row("CAUSE · one artifact fed, one artifact witnessed",
        f"{len(take('one-artifact').artifacts)} artifact(s)",
        len(take("one-artifact").artifacts) == 1)
    clean()
    return out


def verdicts(got: list[Divergence]) -> str:
    """The worst thing a set of divergences says, as one word."""
    for want in ("refuse", "vacuous", "warn", "declared"):
        if any(g.verdict == want for g in got):
            return want
    return "clean"


# The four defects, as a module of their own. Written to the scratch tree and
# imported so that the frame the seal attributes a write to belongs to a file
# that is not this one — see `caused`.
FLAW = '''"""Four instruments' defects, restored verbatim enough to be caught."""
import shutil
import subprocess
import sys


def unconditional(lang):
    """`fetch_scanners` before its repair: lay the scanner down whatever it
    says, and unlink the generated parser beside it."""
    (lang / "scanner.c").write_bytes(b"// authored")
    (lang / "parser.c").unlink()


def conditional(lang):
    """...and after: relink only a scanner that is actually a different one."""
    blob = b"// authored"
    if (lang / "scanner.c").read_bytes() != blob:
        (lang / "scanner.c").write_bytes(blob)
        (lang / "parser.c").unlink()


def unlocked(lang, want):
    """`oracle_build` before its repair: overwrite a shared grammar, no lock."""
    shutil.copyfile(want, lang / "grammar.json")


def child(lang):
    """What `tree-sitter generate` is, as far as any interposition can tell."""
    subprocess.run([sys.executable, "-c",
                    "open('grammar.json','wb').write(b'{}')"],
                   cwd=lang, capture_output=True)


def press(work):
    """A folio pressed into this arm's own cache. Legitimate, and must pass."""
    (work / "latex.folio").write_bytes(b"pressed")
'''


WIDE = 62


def table(head: str, cols: tuple[str, ...], rows) -> int:
    print(f"\n{head:<{WIDE}} " + "".join(f"{c:<22}" for c in cols[:-1]) + cols[-1])
    print("-" * 108)
    bad = 0
    for what, *said, ok in rows:
        bad += not ok
        line = textwrap.wrap(what, WIDE) or [""]
        print(f"{line[0]:<{WIDE}} " + "".join(f"{str(s)[:21]:<22}" for s in said)
              + ("yes" if ok else "NO"))
        for more in line[1:]:
            print(f"  {more}")
    return bad


def verify() -> int:
    bad = table("the six, restored", ("refuses on", "seal", "holds"), six())
    print("\nThe `seal` column is the honest half: the within-run write detector"
          "\ncatches two of the six and structurally cannot catch the other four."
          "\nRows 1, 2, 5 and 6 involve no write at all — row 5's event happens in"
          "\nthe gap BETWEEN two runs, so no window either run could open contains"
          "\nit, and row 6 is four honest arms and a true statement."
          "\n\nA `!` marks `vacuous` rather than `refuse`: not *these arms are"
          "\nincomparable* but *they are perfectly comparable and that is the wrong"
          "\nartifact*. Row 6 carries nothing else, which is why it read as"
          "\nclearance for two lanes. It also fires unbidden on rows 1, 3 and 5 —"
          "\nrow 1 because a shared cache makes both arms read one folio, and rows 3"
          "\nand 5 because a scanner and a lex fix cannot move a pressed table."
          "\nThose three are the same theatre caught from the other side.")

    bad += table("and the arms that must PASS", ("refuses on", "holds"), honest())

    # Not under TMPDIR: the seal treats the system scratch space as private on
    # purpose, because staging a copy there and measuring the copy is the correct
    # pattern rather than the defect. A proof run inside it would be a proof that
    # the detector is switched off.
    scratch = HOME / "scratch" / str(os.getpid())
    scratch.mkdir(parents=True, exist_ok=True)
    try:
        bad += table("the seal, caused rather than constructed", ("says", "holds"),
                     caused(scratch))
        bad += table("`take` itself, on real runs — the half no row above touches",
                     ("reads", "holds"), filled(scratch / "oracle"))
        print("\nEvery row above hands `differ` a witness somebody typed. These"
              "\nhand it what a run actually recorded, which is where the field"
              "\nthat read `0 oracle(s)` on every board was hiding — visible in"
              "\nthe first two rows, one fed ledger read by both rules at once.")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print(f"\n{'ALL HELD' if not bad else f'{bad} ROW(S) WRONG'} — two detectors, and"
          " each one's blind spot is the other's population.")
    return 1 if bad else 0


# -------------------------------------------------------------------- the sweep

# What counts as putting bytes somewhere. Spelled as the *primitives* rather than
# as a list of functions that misuse them, so an instrument written tomorrow is
# in the population the moment it writes, and no edit here is needed to include
# it. `mkdir` is deliberately absent: making a directory changes no artifact's
# identity, and counting it would bury the sites that do under the ones that
# cannot.
PUTS = {"write_bytes", "write_text", "unlink", "rmtree", "copyfile", "copy",
        "copy2", "move", "replace", "remove", "rename", "truncate", "touch",
        "symlink", "link"}


class Site(NamedTuple):
    file: str
    line: int
    func: str
    op: str
    target: str


def puts(path: Path) -> Iterator[Site]:
    """Every place one module puts bytes somewhere, with what it writes to.

    The static half of the sweep. It cannot tell a shared root from a private one
    - that needs the value, not the syntax - so it does not try; it produces the
    population and the dynamic half judges it. A static pass that guessed here
    would be the third instrument in this tree to encode a fact about a name as a
    fact about a thing.
    """
    import ast
    try:
        tree = ast.parse(path.read_text())
    except (OSError, SyntaxError):
        return
    scope: list[tuple[int, str]] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for sub in ast.walk(node):
                sub._in = node.name  # type: ignore[attr-defined]
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        op = ""
        if isinstance(fn, ast.Attribute) and fn.attr in PUTS:
            op, arg = fn.attr, fn.value
        elif isinstance(fn, ast.Name) and fn.id == "open":
            mode = next((a for a in node.args[1:2]), None)
            if isinstance(mode, ast.Constant) and any(c in str(mode.value) for c in "wax+"):
                op, arg = f"open({mode.value})", node.args[0]
        if not op:
            continue
        target = ast.unparse(node.args[0] if op.startswith("open") or
                             fn.attr in {"copyfile", "copy", "copy2", "move", "rmtree",
                                         "replace", "remove", "rename", "symlink", "link"}
                             else arg)
        yield Site(stamp.here(path), node.lineno,
                   getattr(node, "_in", "(module)"), op, target[:46])
    del scope


def population() -> list[Path]:
    """Every instrument in the tree, found by walking rather than by listing."""
    out = sorted((ROOT / "tool").glob("*.py"))
    out += sorted(p for p in (ROOT / "research").rglob("*.py"))
    return [p for p in out if p.name != "still.py"]


def sweep(show: int) -> int:
    """The two halves, and an honest statement of what each one covers.

    **Static:** every module, every place it puts bytes. Complete over the
    population and blind to whether the target is shared - it is the denominator,
    not the finding.

    **Dynamic:** each module's own self-check, run inside a non-strict seal. The
    seal judges by value rather than by syntax - it knows `OUTLINER_WORK` and it
    knows which locks are held - so a fault it reports is a real one. It covers
    only what a self-check exercises, and that number is printed rather than
    implied.
    """
    files = population()
    sites = [s for p in files for s in puts(p)]
    by: dict[str, list[Site]] = {}
    for s in sites:
        by.setdefault(s.file, []).append(s)
    print(f"static: {len(files)} module(s) walked, {len(sites)} write site(s) in"
          f" {len(by)} of them. This is the population, not the finding: a write"
          f"\n        is only a defect when its target is something the same run"
          f" reads as evidence, and syntax cannot say that.")
    print(f"\n{'module':<44}{'sites':<8}{'the paths it puts bytes to'}")
    print("-" * 108)
    for name, rows in sorted(by.items(), key=lambda kv: -len(kv[1]))[:show]:
        seen: list[str] = []
        for r in rows:
            if r.target not in seen:
                seen.append(r.target)
        print(f"{name:<44}{len(rows):<8}{', '.join(seen[:3])[:56]}")

    print(f"\ndynamic: each instrument's own self-check, inside an observing seal.")
    print(f"\n{'instrument':<44}{'self-check':<26}{'writes read back as evidence'}")
    print("-" * 108)
    ran = bad = 0
    for name, argv in CHECKS:
        got = under(name, argv)
        ran += got is not None
        if got is None:
            print(f"{name:<44}{'(no self-check)':<26}—")
            continue
        bad += len(got)
        print(f"{name:<44}{' '.join(argv)[:25]:<26}"
              + (", ".join(f"{stamp.here(Path(w.path))} at {w.site}" for w in got[:2])
                 if got else "none"))
    print(f"\nswept {ran} instrument(s) dynamically of {len(files)} in the tree."
          f" {bad} write(s) read back as evidence.")
    print("A clean dynamic sweep is a claim about the paths a self-check walks,"
          " and nothing more.\nThe standing guard is the seal itself, on in the"
          " instruments that compare — not this pass.")
    return 1 if bad else 0


# An instrument's own self-check, as it spells it. Discovered by reading each
# module's argparse verbs rather than by hand where it can be; listed here where
# a module's check needs an argument only its author knows. This is NOT an
# allowlist of suspects - every module in `population()` is swept statically, and
# a module missing from here is reported as unexercised rather than as clean.
CHECKS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("tool/stamp.py", ("--verdicts",)),
    ("tool/stamp.py", ("--stops",)),
    ("tool/stamp.py", ("--hazards",)),
    ("tool/attest.py", ("verify",)),
    ("tool/order.py", ("verify",)),
    ("tool/sole.py", ()),
)


def under(name: str, argv: tuple[str, ...]) -> list[Wrote] | None:
    """Run one self-check in-process, inside an observing seal.

    In-process rather than as a subprocess, because the whole value of the seal
    is that it sees the write primitives; a child would hand back an exit code
    and nothing else. Non-strict, because a sweep that stopped at the first
    finding would report one instrument per run.
    """
    path = ROOT / name
    if not path.is_file():
        return None
    import runpy
    stamp.FED.clear()
    old = sys.argv[:]
    try:
        with sealed(strict=False) as faults:
            sys.argv = [str(path), *argv]
            with contextlib.redirect_stdout(io.StringIO()), \
                 contextlib.redirect_stderr(io.StringIO()):
                try:
                    runpy.run_path(str(path), run_name="__main__")
                except SystemExit:
                    pass
                except Exception:
                    return None
            return list(faults)
    finally:
        sys.argv = old
        stamp.FED.clear()


# --------------------------------------------------------------------- the CLI


def against(a: str, b: str, mine: tuple[str, ...], null: bool,
            inert: bool = False) -> int:
    try:
        x, y = recall(a), recall(b)
    except OSError as e:
        print(f"still: no such witness ({e})", file=sys.stderr)
        return 2
    print(x.line())
    print(y.line())
    rows = differ(x, y, mine=mine, varying=() if null else ("binary",),
                  inert=inert)
    for r in rows:
        print(r.line())
    if any(r.verdict == "vacuous" for r in rows):
        print("still: these two arms are perfectly comparable and you compared"
              " the wrong thing. The evidence above never moved, so it never"
              " observed your change, and it cannot clear what it did not see.")
        return 1
    if sank(rows):
        print("still: these two arms were not taken against the same world."
              " Whatever they differ by, it is not only what you changed.")
        return 1
    print(f"still: comparable — {len(rows)} note(s), none fatal")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="verb")
    w = sub.add_parser("witness", help="record the world this arm was taken against")
    w.add_argument("arm")
    g = sub.add_parser("against", help="compare two arms' worlds")
    g.add_argument("a", help="an arm name, or a path to something that carries a"
                             " witness (a `standing.py --json` board does)")
    g.add_argument("b")
    g.add_argument("--mine", action="append", default=[],
                   help="a file, directory or glob this lane claims as its own"
                        " change; repeatable and comma-separable")
    g.add_argument("--null", action="store_true",
                   help="a null arm: the subject is byte-identical either side,"
                        " so the binary must NOT have moved")
    g.add_argument("--inert", action="store_true",
                   help="evidence that did not move is your RESULT (a claim of"
                        " equivalence), not your proof of no collateral")
    sub.add_parser("verify", help="the six, restored, against both detectors")
    s = sub.add_parser("sweep", help="every instrument, statically and under the seal")
    s.add_argument("--show", type=int, default=14)
    m = sub.add_parser("mark", help="write a pin's subject manifest beside its record")
    m.add_argument("where")
    got = ap.parse_args(argv)
    if got.verb == "witness":
        it = take(got.arm)
        print(it.line())
        print(f"still: kept at {stamp.here(keep(it))}")
        return 0
    if got.verb == "against":
        # One `--mine src/a/,src/b.zig` is the spelling `standing.py` takes and
        # the one `tool/README.md` documents for the flag of this name, so a
        # lane arrives here with it already in hand. Appended whole it became a
        # single claim naming no file, and the refusal that followed reported
        # *more* unclaimed files than the correctly-spelled run - so the
        # mis-parse read as "your isolation is worse than you thought" rather
        # than as a flag that did not parse. Split here so the two flags of one
        # name cannot disagree about their own syntax.
        mine = tuple(p for a in got.mine for p in a.split(",") if p.strip())
        return against(got.a, got.b, mine, got.null, got.inert)
    if got.verb == "mark":
        return print(f"still: {mark(Path(got.where))} file(s)") or 0
    if got.verb == "verify":
        return verify()
    if got.verb == "sweep":
        return sweep(got.show)
    ap.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
