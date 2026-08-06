#!/usr/bin/env python3
"""Which oracle answered.

`stamp.py` records fourteen fields about a run and **all fourteen are about
outliner**: the binary's digest, the tree it was built from, whether that tree
has moved, which artifacts it was fed. Every one of those exists because a
number was once published about a tree that no longer existed.

The oracle is the other half of every one of those numbers. `plumb`, `rack`,
`absent` and `differential` all say "tree-sitter builds X and we build Y", and
until now not one of them recorded *which* tree-sitter, generated from which
grammar bytes, compiled with which scanner, by which CLI. A row that says
`scala 8,644 racked` is a claim about two parsers and names one.

That is not a theoretical gap. Three facts, measured on this machine:

  - 29 grammars have a compiled oracle, and 28 of them exist as several
    different files at once - one per lane's seat, because `TREE_SITTER_LIBDIR`
    is per-lane by design.
  - Two of scala's four differ in **52 bytes out of 4,083,976**: the Mach-O
    UUID and a build id. Same parser. So digesting the *library* reports a
    split on every seat forever and never once about a parser that changed -
    the artifact easiest to digest is the one that cannot answer the question.
  - **25 of the 29 have at least one library older than the sources sitting
    beside it**, which is the CLI's own rebuild trigger. Those seats will
    answer the next question with a parser that does not exist yet, and nothing
    will say so.

So the identity of an oracle is the **bytes it is lowered from** - everything
under its `src/`: the grammar json, the generated `parser.c`, the external
scanner, the headers - plus the CLI version that lowered them. That is the same
choice `stamp.survey` makes for outliner, for the same reason, and it is
reproducible where a library digest is not.

Two things follow, and this file is both:

  **stamp** - `read` returns that identity and, on the way past, hands every
  source file to `stamp.fed`. The generation ledger already re-reads everything
  a run was fed and names any row whose artifact moved underneath it; the
  oracle was simply never in it. One call, and `SPLIT` covers the oracle too.

  **pin** - `freeze` takes a copy nothing else writes to, and `under` points a
  slate at it. A before/after pair is only a comparison if both sides saw the
  same oracle, and on a tree four lanes are rebuilding that is not something to
  hope for.

usage:
  attest.py show [--json]        the oracle each grammar would answer with now
  attest.py freeze <tag>         copy today's oracle into a pin nothing writes
  attest.py list                 the pins on this machine
  attest.py rule [--json]        what the identity rule reads, and what it cannot
  attest.py verify               the gate: prove an unpinned oracle moves
"""

from __future__ import annotations

import ast
import hashlib
import inspect
import json
import os
import re
import shutil
import sys
import tempfile
import textwrap
import time
from pathlib import Path, PurePath, PurePosixPath
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import differential as d  # noqa: E402 - the path has to be set first
import stamp  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PINS = ROOT / ".local" / "attest"


LOWERED = frozenset({"parser.c", "node-types.json"})
LOWERED_DIR = "tree_sitter"
# What `tree-sitter generate` writes, given `src/grammar.json`. Stated here as
# the *oracle's* output contract rather than discovered per file, because only
# `parser.c` carries an `@generated` banner and the three runtime headers carry
# nothing at all - so a content sniff would catch one of four and quietly let
# the rest back into the identity.
#
# It is a declared set and therefore the kind of thing that rots, so it is not
# trusted: `verify` deletes exactly these in a scratch copy, re-runs `generate`,
# and fails if what reappears is not what is named here. A CLI that starts
# emitting a fifth artifact turns the gate red instead of silently re-entering
# the digest. And the default is fail-closed - a file this predicate does not
# recognise is treated as **authored** - so the failure direction is an identity
# that moves too often and is visible, never one that misses a real edit.


def lowered(rel: PurePosixPath) -> bool:
    """Is this file an output of `tree-sitter generate`, or an input to it?

    The CLI only ever writes inside the `src/` it is handed, so anything
    outside one - a monorepo's shared `common/scanner.h`, say - is authored by
    construction and needs no name to be recognised.
    """
    parts = rel.parts
    if "src" not in parts:
        return False
    tail = parts[parts.index("src") + 1:]
    return bool(tail) and (tail[0] == LOWERED_DIR
                           or (len(tail) == 1 and tail[0] in LOWERED))


def sources(home: Path) -> list[tuple[Path, PurePosixPath]]:
    """Every file this oracle is made of, keyed by its place in the grammar.

    `home` plus the closure of the relative `#include`s that climb out of it.
    That second half is not decoration: ocaml's, php's and typescript's whole
    external scanner is one `#include "../../common/scanner.h"` and a page of
    stubs, so a survey that stopped at `home` would leave the three grammars
    where the scanner is the interesting part with no authored C in their
    identity at all. `differential.sandboxed` is what guarantees the climb
    lands inside `lang/<name>/`, so the closure is bounded by a checked
    invariant rather than by hope, and `INCLUDE` is imported from there rather
    than respelled here.

    Keyed relative to the **grammar root** - the unit the CLI is handed and the
    unit `sandboxed` polices - so php's `php/src/scanner.c` and its
    `common/scanner.h` are one namespace and every copy of that grammar on the
    machine spells its files the same way.

    The walk starts at `home/src` and not at `home`, which cost a measurement to
    learn: widening it to the whole home directory swept `bench.py`'s compiled
    `lang/<name>/<name>.dylib` into the authored digest and split eleven
    grammars that had been whole - a *library* in the identity, which is the
    precise error the module docstring above argues against, reintroduced from
    the other side. `src/` is what the CLI is handed; the closure is what the
    compiler then opens; a build product beside them is neither.
    """
    seen: set[Path] = set()
    todo = sorted(q.resolve() for q in (home / "src").rglob("*") if q.is_file())
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        if p.suffix not in (".c", ".h", ".cc", ".cpp", ".hpp"):
            continue
        try:
            blob = p.read_bytes()
        except OSError:
            continue
        for hit in d.INCLUDE.findall(blob):
            want = hit.decode()
            if want.startswith("tree_sitter/"):
                continue  # the runtime's own headers; `generate` wrote them
            if (target := (p.parent / want).resolve()).is_file():
                todo.append(target)
    # The root is where the climbs land, not where the path happens to say
    # `lang/`. Deriving it from the files themselves is what makes a scratch
    # copy of a grammar spell its files the same way the live tree does - php's
    # `php/src/scanner.c` and `common/scanner.h` either way - so a digest taken
    # in a tmpdir is comparable to one taken on the shared tree. Keying off
    # `split` alone silently dropped the climbed header in any copy that had no
    # `lang/` above it, which is every copy anyone makes to test with.
    root = Path(os.path.commonpath([split(home)[0].resolve(), *seen]))
    return sorted(((p, PurePosixPath(p.relative_to(root))) for p in seen),
                  key=lambda kv: kv[1])


def survey(home: Path) -> tuple[str, int, float, str]:
    """Digest what this oracle was lowered FROM; time what it was lowered TO.

    The digest used to cover the whole of `src/`, generated files included, on
    the reasoning that the largest artifact in the tree belongs in its own
    identity. Measured, that was backwards. `parser.c`, `node-types.json` and
    `tree_sitter/*.h` are outputs of `tree-sitter generate` over inputs the
    digest already holds, so they carry no identity the grammar and the CLI
    version do not - and they subtract stability, because their *presence* is a
    cache state that any measurement creates and that any scanner refresh used
    to destroy. Two grammars on this machine, css and toml, existed as two
    parsers for exactly that reason and for no other: one copy had a `parser.c`
    and the other did not. It cost two lanes an investigation and a
    sealed-holdout scare, and no parser was ever involved.

    So the identity is the authored bytes. The mtime keeps **everything**,
    because *"is the compiled library older than what it was built from"* is a
    different question, a regenerated `parser.c` is a real answer to it, and
    that half was never the unstable one.
    """
    h, when, where, count = hashlib.sha256(), 0.0, "", 0
    for p, rel in sources(home):
        try:
            touched = p.stat().st_mtime
            if touched > when:
                when, where = touched, str(rel)
            if lowered(rel):
                continue
            h.update(str(rel).encode() + b"\0")
            with p.open("rb") as fh:
                for block in iter(lambda: fh.read(1 << 20), b""):
                    h.update(block)
        except OSError:
            # A file a sibling lane is mid-write on is itself a fact about this
            # oracle; record it rather than failing the measurement it was only
            # supposed to describe.
            h.update(b"?\0")
            continue
        count += 1
    return (h.hexdigest() if count else ""), count, when, where


def built(home: Path) -> tuple[str, int]:
    """The other half - a digest of what `generate` produced, and how much.

    Deliberately **not** part of the identity, and deliberately still available.
    The hazard `holdout.prove` watches for is a `parser.c` generated from
    something other than the `grammar.json` beside it: `oracle_build`
    regenerates only when the two grammar digests differ, so a stale generated
    parser under a correct grammar is used as-is. Folding that into the identity
    was one way to notice it and a bad one, because the identity then cannot
    tell a torn tree from a rebuild - the two look identical and only one is a
    fault. Two digests answer both questions and neither answers the other's.
    """
    h, count = hashlib.sha256(), 0
    for p, rel in sources(home):
        if not lowered(rel):
            continue
        h.update(str(rel).encode() + b"\0")
        try:
            h.update(p.read_bytes())
        except OSError:
            h.update(b"?\0")
        count += 1
    return (h.hexdigest() if count else ""), count


_RULE: str | None = None

# The functions the identity is made of. Everything the rule folds in is
# reached FROM these; naming a fourth here is how the rule grows, and nothing
# else in this file needs editing when it does.
SEEDS = ("survey", "sources", "lowered")


def spell(value) -> str:
    """A value written down the same way twice, or not written down at all.

    Returns `""` for anything whose bytes are not reproducible from the object,
    which `reads` records as an unfolded boundary rather than hashing
    `repr()` - a `repr` carrying an address would move the rule on every
    interpreter start and a rule that changes for no reason is worse than one
    that misses.

    Paths are spelled relative to the repo, because the rule must be the same
    rule on two machines; an absolute path in the digest would make every pin
    minted elsewhere read as a retired rule.
    """
    if value is None or isinstance(value, (str, bytes, bool, int, float)):
        return repr(value)
    if isinstance(value, (frozenset, set)):
        return "{" + ",".join(sorted(spell(v) for v in value)) + "}"
    if isinstance(value, (list, tuple)):
        return "[" + ",".join(spell(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(f"{spell(k)}:{spell(v)}"
                              for k, v in sorted(value.items(),
                                                 key=lambda kv: repr(kv[0]))) + "}"
    if isinstance(value, re.Pattern):
        return f"re({value.pattern!r},{value.flags})"
    if isinstance(value, PurePath):
        return f"path({stamp.here(Path(value))!r})"
    return ""


def reads(seeds: tuple[str, ...] = SEEDS) -> list[tuple[str, str, str]]:
    """Everything the identity rule actually reads, and what each part contributes.

    The rule used to be a digest of three function *bodies*. That is not the
    rule; it is three-quarters of the rule and a claim about the rest. `sources`
    calls `split`, which lives in this file and is not one of the three, and it
    matches against `differential.INCLUDE`, which does not live in this file at
    all - so the whole include-closure half of the identity could be rewritten
    from another module with the rule digest holding still, which is precisely
    the failure the rule digest exists to catch, one level up.

    So: walk the seeds' syntax, resolve every global name and every
    `module.attr` they load, fold the source of anything in this tree and the
    value of anything constant, and recurse. Rows come back as
    `(name, kind, contribution)`. Two kinds contribute nothing and are returned
    anyway, because a boundary the caller can read is the difference between a
    bound and a blind spot:

      - `module` - a module named on the way to something. `differential` is
        one; `differential.INCLUDE` is folded on its own row, so the boundary
        is the module object and not what the rule reads through it.
      - `stdlib` - `hashlib`, `Path`. Pinned by the interpreter, not by this
        repository, and folding a standard library's source into a
        repository's rule version would move every pin on a Python upgrade.
      - `opaque` - a live object whose bytes `spell` cannot reproduce. There
        are none today; the row exists so that the day one appears, it appears
        in `attest.py rule` rather than in nobody's report.
    """
    here = sys.modules[__name__]
    out: dict[str, tuple[str, str]] = {}
    todo = [(n, getattr(here, n)) for n in seeds]
    while todo:
        name, obj = todo.pop(0)
        if name in out:
            continue
        home = getattr(obj, "__module__", None)
        native = home in sys.modules and getattr(
            sys.modules[home], "__file__", "") .startswith(str(ROOT))
        if (inspect.isfunction(obj) or inspect.isclass(obj)) and native:
            try:
                out[name] = ("code", textwrap.dedent(inspect.getsource(obj)))
            except OSError:  # pragma: no cover - source-less definition
                out[name] = ("opaque", "")
                continue
            for kid, got in cited(obj):
                if kid not in out:
                    todo.append((kid, got))
        elif inspect.ismodule(obj):
            out[name] = ("module", "")
        elif inspect.isbuiltin(obj) or inspect.isfunction(obj) \
                or inspect.isclass(obj) or callable(obj):
            out[name] = ("stdlib", "")
        else:
            said = spell(obj)
            out[name] = ("data", said) if said else ("opaque", "")
    return sorted((n, k, v) for n, (k, v) in out.items())


def cited(fn) -> list[tuple[str, object]]:
    """The global names one function loads, `module.attr` included."""
    try:
        tree = ast.parse(textwrap.dedent(inspect.getsource(fn)))
    except (OSError, SyntaxError):
        return []
    scope = getattr(fn, "__globals__", vars(sys.modules[__name__]))
    out: list[tuple[str, object]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
            owner = scope.get(node.value.id)
            if inspect.ismodule(owner) and hasattr(owner, node.attr):
                out.append((f"{node.value.id}.{node.attr}",
                            getattr(owner, node.attr)))
        elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
            if node.id in scope:
                out.append((node.id, scope[node.id]))
    return out


def rule() -> str:
    """The identity rule's own version - a digest of everything that decides an
    oracle digest.

    Earned, not designed. Five oracle pins sit on this machine and the three
    older ones disagree with the two newer ones on **all thirty grammars**,
    which reads exactly like the oracle drifting under a day's work. It did not
    drift: `survey` stopped folding generated files into the identity in between
    (and it was right to), so the two sets of numbers were minted by two
    different rules over identical bytes. Nothing on disk said so, and the only
    reason it was caught is that `was` was kept around to disagree.

    A digest that changes when the rule changes turns that back into what it is
    - a comparison of two incomparable measurements - instead of thirty
    convincing drift reports.

    What that digest covers is `reads()`, not this function's opinion of it: the
    transitive closure of what the three seed functions load. The bound it
    cannot cross is the standard library, and `attest.py rule` prints both
    halves rather than leaving the bound in a dossier.
    """
    global _RULE
    if _RULE is None:
        h = hashlib.sha256()
        for name, kind, said in reads():
            h.update(f"{name}\0{kind}\0".encode() + said.encode() + b"\0")
        _RULE = h.hexdigest()
    return _RULE


def narrow() -> str:
    """The rule version this one replaced: a digest of three function bodies.

    Kept for the reason `was` and `stamp.py --verdicts` are kept - a change to
    a discriminator is only demonstrated if the thing it replaced is present to
    disagree. Without it the rows below would show the new rule moving when its
    closure moves, which proves the new rule is self-consistent, and every rule
    is that. With it, one run reads a digest that holds while the code deciding
    an oracle's identity is rewritten underneath it.
    """
    h = hashlib.sha256()
    for fn in (lowered, sources, survey):
        h.update(textwrap.dedent(inspect.getsource(fn)).encode() + b"\0")
    h.update(("\0".join(sorted(LOWERED)) + "\0" + LOWERED_DIR).encode())
    return h.hexdigest()


def restated(**swap) -> tuple[str, str]:
    """Both rules, over a module in which some names have been replaced."""
    global _RULE
    keep = {k: getattr(sys.modules[__name__], k, None) for k in swap
            if "." not in k}
    outer = {k: (sys.modules[__name__].__dict__[k.split(".")[0]], k.split(".")[1])
             for k in swap if "." in k}
    held = {k: getattr(m, a) for k, (m, a) in outer.items()}
    try:
        for k, v in swap.items():
            if k in outer:
                setattr(outer[k][0], outer[k][1], v)
            else:
                setattr(sys.modules[__name__], k, v)
        _RULE = None
        return rule(), narrow()
    finally:
        for k, v in keep.items():
            setattr(sys.modules[__name__], k, v)
        for k, v in held.items():
            setattr(outer[k][0], outer[k][1], v)
        _RULE = None


def ruled() -> list[tuple[str, str, bool]]:
    """The rule digest, held to exactly what it claims to be.

    Its own verify row used to prove the digest reads a field. That is a claim
    about a getter. These rows are about the rule: they move things the rule
    reads and things it does not, from inside this file and from outside it,
    and require the digest to move for the first kind and hold for the second.
    """
    base, thin = rule(), narrow()
    out = [("the rule digest is stable across two calls - an address in it would"
            " pass every row below", base[:12], base == restated()[0])]

    # Outside the three seeded functions, and outside this file entirely. The
    # include closure is half of what `sources` collects; rewriting the pattern
    # rewrites which bytes an oracle's identity is taken over.
    moved, still = restated(**{"d.INCLUDE": re.compile(rb'#include\s+"([^"]+)"')})
    out.append(("MOVES when `differential.INCLUDE` changes - the pattern that"
                " decides which files the scanner closure reaches, in another"
                " module", f"{base[:9]} → {moved[:9]}", moved != base))
    out.append(("...where the rule this replaced holds, having never read it -"
                " the whole include half of the identity could be rewritten"
                " under a digest that never moved", f"{thin[:9]} = {still[:9]}",
                still == thin))

    # Outside the three, inside this file: reached only through `sources`.
    moved, still = restated(split=lambda lang: (lang, Path("elsewhere")))
    out.append(("MOVES when `split` changes - the function deciding what a"
                " grammar's root IS, which `sources` calls and the old digest"
                " did not hash", f"{base[:9]} → {moved[:9]}", moved != base))
    out.append(("...where the rule this replaced holds for that too",
                f"{thin[:9]} = {still[:9]}", still == thin))

    moved, _ = restated(LOWERED=frozenset({"parser.c"}))
    out.append(("MOVES when `LOWERED` changes - the partition both rules always"
                " did read, so this is the part that was already right",
                f"{base[:9]} → {moved[:9]}", moved != base))

    # The other direction, and it is the one that makes the digest usable: a
    # rule that moved on any edit to this file would retire every pin on the
    # machine every time somebody fixed a docstring three functions away.
    moved, _ = restated(PINS=ROOT / ".local" / "somewhere-else")
    out.append(("HOLDS when something this file has that the rule does not read"
                " changes - `PINS`", f"{base[:12]}", moved == base))

    covered = reads()
    opaque = [n for n, k, _ in covered if k == "opaque"]
    folded = [n for n, k, _ in covered if k in ("code", "data")]
    out.append((f"the digest covers {len(folded)} name(s) and NOTHING it reads is"
                f" opaque - an unrenderable value would be read and not digested",
                ", ".join(opaque)[:24] or "none opaque", not opaque))
    out.append(("...and what it cannot cover is named in `attest.py rule`, not"
                " only in a dossier - the bound is in the tool's own output",
                f"{len(covered) - len(folded)} boundary row(s)",
                len(covered) > len(folded)))
    return out


class Oracle(NamedTuple):
    """One grammar's oracle, identified by what it was lowered from."""

    name: str
    tree: str  # sha256 over `src/`; "" when there is no oracle here at all
    files: int
    newest: float
    where: str  # the file under `src/` touched last
    cli: str  # what `tree-sitter --version` says
    lib: str  # the compiled library this seat would load, or ""
    made: float  # its mtime; 0.0 when it is not built yet
    seat: str  # which lane's libdir that is
    pin: str  # the frozen oracle this came out of, or "" for the shared tree
    lower: str = ""  # sha256 over what `generate` wrote; NOT part of `tree`
    # budge: 5 on every generated oracle - `LOWERED` names exactly that many, and `verify` proves nothing else reappears from a regenerate
    lowers: int = 0  # how many generated files that was; 0 = never generated
    # Whether this run was about to put a question to this oracle, or merely
    # naming it. `lowers == 0` means *never generated* only when the row was
    # asked; unasked it means *not measured*, and collapsing the two would let a
    # board that never opened a `parser.c` report one that does not exist.
    asked: bool = True

    @property
    def absent(self) -> bool:
        return not self.tree

    @property
    def stale(self) -> bool:
        """A source newer than the library - the CLI's own rebuild trigger.

        Not "the library is wrong": it is that the *next* run will silently get
        a different parser than the last one did, which is precisely the shape
        that makes two of anyone's numbers incomparable.
        """
        return bool(self.made) and self.newest > self.made

    def as_dict(self) -> dict:
        return {**self._asdict(), "tree": self.tree[:12], "lower": self.lower[:12],
                "newest": stamp.iso(self.newest) if self.newest else "",
                "made": stamp.iso(self.made) if self.made else "",
                "absent": self.absent, "stale": self.stale}


def read(case, pin: str = "", asking: bool = True) -> Oracle:
    """One case's oracle, recorded **and fed to the generation ledger**.

    The feeding is the point. `stamp.reconcile` already re-reads every artifact
    a run was handed and names the rows whose artifact moved; it has been
    running at the foot of every report this whole time with the oracle outside
    it. Passing the grammar's own name as the row is what lets it say *scala's
    oracle moved and scala's row is the one that read the old one*.

    `asking` separates the two things a caller can want, because they cost
    three orders of magnitude apart. A run **about to put a question to this
    oracle** is asking: it will open these files, so feeding them is honest and
    digesting what `generate` wrote is a read it is paying for anyway. A run
    **naming the oracle a cached verdict was already measured against** is not:
    nothing is opened, so feeding would put an artifact in the ledger this run
    never read, and `built` would digest scala's 28 MB `parser.c` at the foot of
    a board that asked nobody anything. The identity is the same either way -
    only the two side effects are conditional.
    """
    name = d.named(case.lang)
    got, files, when, where = survey(case.lang)
    made, mades = built(case.lang) if asking else ("", 0)
    # Every file, generated included. The ledger's question is *did this move
    # under the run*, which is about the whole tree, and is not the identity
    # question the digest above answers.
    lib = next((d.LIB / f"{name}{x}" for x in (".dylib", ".so")
                if (d.LIB / f"{name}{x}").exists()), None)
    if asking:
        for p, _ in sources(case.lang):
            stamp.fed(p, name)
        if lib is not None:
            stamp.fed(lib, name)
    return Oracle(name, got, files, when, where, oracle_cli(),
                  stamp.here(lib) if lib else "", lib.stat().st_mtime if lib else 0.0,
                  d.SEAT.name, pin, made, mades, asking)


_CLI: str | None = None


def oracle_cli() -> str:
    """`tree-sitter --version`, asked once. Shelling out per grammar would cost
    thirty processes to learn one fact that cannot change inside a run."""
    global _CLI
    if _CLI is None:
        _CLI = d.oracle_ready() or "(no tree-sitter CLI)"
    return _CLI


class Court(NamedTuple):
    """Every oracle a run consulted, as one identity.

    `digest` is over the (name, tree) pairs and nothing else - not the seat,
    not the library, not the pin - so two lanes on two machines that lowered
    the same grammar bytes with the same CLI print the same number, which is
    the only property that makes it worth printing.
    """

    rows: tuple[Oracle, ...]
    cli: str
    when: float

    @property
    def asked(self) -> bool:
        """Whether this run put a question to these oracles, or only named the
        one its cached verdicts were already measured against. Both are honest
        records of an identity; only the first is a record of a reading."""
        return any(r.asked for r in self.rows)

    @property
    def digest(self) -> str:
        h = hashlib.sha256(self.cli.encode() + b"\0")
        for r in sorted(self.rows):
            h.update(f"{r.name}\0{r.tree}\0".encode())
        return h.hexdigest()

    @property
    def pins(self) -> tuple[str, ...]:
        return tuple(sorted({r.pin for r in self.rows if r.pin}))

    def as_dict(self) -> dict:
        return {"oracle": self.digest[:12], "cli": self.cli,
                "grammars": len(self.rows),
                "absent": sum(r.absent for r in self.rows),
                "stale": sum(r.stale for r in self.rows),
                "pin": list(self.pins), "seat": next((r.seat for r in self.rows), ""),
                "when": stamp.iso(self.when),
                "row": [r.as_dict() for r in self.rows]}

    def line(self) -> str:
        """One line plus a warning per hazard, for the foot of a report - the
        same shape `stamp.Stamp.line` has, because it answers the other half of
        the same question and the two are read together or not at all."""
        where = f"pin {'+'.join(self.pins)}" if self.pins else f"seat {next((r.seat for r in self.rows), '?')}"
        out = [f"oracle: {self.digest[:9]} over {len(self.rows)} grammar(s)"
               f" · {self.cli} · {where}"]
        if gone := [r.name for r in self.rows if r.absent]:
            out.append(f"oracle: ABSENT - no oracle sources for {len(gone)}:"
                       f" {', '.join(gone[:6])}"
                       + (f" (+{len(gone) - 6} more)" if len(gone) > 6 else ""))
        if old := [r for r in self.rows if r.stale]:
            out.append(f"oracle: STALE - {len(old)} library(s) older than the sources"
                       f" beside them, so the CLI will rebuild them and the next run"
                       f" answers with a different parser: "
                       + ", ".join(f"{r.name} ({r.where})" for r in old[:4])
                       + (f" (+{len(old) - 4} more)" if len(old) > 4 else ""))
        if not self.pins:
            out.append("oracle: UNPINNED - this is the shared tree four lanes write"
                       " to; `attest.py freeze <tag>` before a before/after pair")
        return "\n".join(out)


def court(cases, pin: str = "", asking: bool = True) -> Court:
    return Court(tuple(read(c, pin, asking) for c in cases), oracle_cli(), time.time())


SEATED: Court | None = None


def attribute(cases, pin: str = "") -> Court:
    """Seat the court a run's numbers are *attributed* to, without asking it.

    The board is the case this exists for. It prints `crooked` out of a cache
    whose every row was already measured against an oracle, and accepts a row
    only when that oracle's identity still holds - so its numbers rest on a
    judge it never opened a file of. Recording that judge is honest; feeding its
    sources to the generation ledger, or digesting the 28 MB `parser.c` it did
    not read, would not be.

    Idempotent against `consult`: a run that later asks re-seats a court with
    `asked` set, and a fuller record replaces a thinner one rather than the
    other way round.
    """
    global SEATED
    seat = court(list(cases), pin, asking=False)
    if SEATED is None or not SEATED.asked:
        SEATED = seat
    return seat


def consult(cases, pin: str = "") -> list:
    """Record which oracle is about to answer, and hand the slate back.

    Module-level, the same way `stamp.FED` is, and for the same reason: the
    alternative is a parameter threaded through every printer, which any new
    one would forget. Feeding the oracle's sources here is also what puts them
    into the generation ledger, so a sibling rebuilding one grammar mid-sweep
    is caught without another line of machinery.

    Lives here rather than in a caller because there are two callers now -
    `rack` compares spines against the oracle and `absent` asks it which
    spellings became tokens - and an attribution each of them implements
    separately is an attribution that will drift between them.
    """
    global SEATED
    picked = under(pin, cases) if pin else list(cases)
    SEATED = court(picked, pin)
    return picked


def told() -> str:
    return SEATED.line() if SEATED else "oracle: NOT RECORDED - half of every number above"


# ------------------------------------------------------------------- the pin

def split(lang: Path) -> tuple[Path, Path]:
    """A grammar's own root, and how deep inside it the CLI is handed.

    `oracle_home` reproduces a monorepo's depth under `lang/<name>/` because
    php's and typescript's scanners climb out of their own directory - so a pin
    that copied only the home would break exactly the three grammars the depth
    exists for. The root is what gets copied; the offset is what gets restored.
    """
    parts = lang.parts
    if "lang" not in parts:
        return lang, Path()
    root = Path(*parts[:parts.index("lang") + 2])
    return root, lang.relative_to(root)


def freeze(tag: str, cases) -> dict:
    """Copy today's oracle somewhere nothing else writes, and say what it is.

    Held under each grammar's shared lock, which is enough: a *build* takes the
    exclusive side, so it cannot land in the middle of a copy, and other
    readers are harmless. Copying without it is how you get a `parser.c` that
    is 28 MB of one generation and a tail of the next.
    """
    home = PINS / tag
    if home.exists():
        raise ValueError(f"{stamp.here(home)} already exists; pick another tag"
                         " or delete it - a pin that gets rewritten is not one")
    rows = {}
    for case in cases:
        name = d.named(case.lang)
        if name in rows:
            continue
        root, at = split(case.lang)
        if not root.is_dir():
            continue
        with d.alone(name, writing=False):
            shutil.copytree(root, home / "lang" / name, dirs_exist_ok=True,
                            copy_function=shutil.copy2)
        # Digest the copy rather than the original. A manifest taken off the
        # thing that was copied FROM agrees with the source by construction and
        # is silent about a bad copy, which is the one failure a pin has.
        got, files, _, where = survey(home / "lang" / name / at)
        rows[name] = {"tree": got, "files": files, "where": where, "at": str(at),
                      "grammar": stamp.digest(case.grammar) if case.grammar.exists() else ""}
    book = {"tag": tag, "when": time.time(), "cli": oracle_cli(),
            "rule": rule(), "row": rows}
    (home / "pin.json").write_text(json.dumps(book, indent=2) + "\n", encoding="utf-8")
    return book


def under(tag: str, cases) -> list:
    """The same slate, pointed at a frozen oracle, or a refusal saying why.

    Verified rather than trusted. A pin is a claim that these bytes have not
    moved, and the cheapest way for that claim to rot is for somebody to have
    run a tool over the pin directory - so the manifest is checked against the
    disk here, and a pin that no longer digests to what it recorded is an error
    rather than a slightly-wrong measurement.
    """
    home = PINS / tag
    try:
        book = json.loads((home / "pin.json").read_text())
    except OSError as exc:
        raise ValueError(f"no oracle pin named {tag!r} under {stamp.here(PINS)}"
                         f"; `attest.py list` for what is there") from exc
    out, bad, retired = [], [], []
    for case in cases:
        name = d.named(case.lang)
        row = book["row"].get(name)
        if row is None:
            bad.append(f"{name}: not in the pin")
            continue
        lang = home / "lang" / name / row["at"]
        got, *_ = survey(lang)
        if got != row["tree"]:
            # A pin taken under the retired rule disagrees with today's rule on
            # every row at once, over bytes that never moved. Say which of the
            # two happened rather than reporting thirty drifts, because the
            # remedy is opposite: a moved pin is somebody's stray write, and a
            # retired rule is a re-freeze.
            if was(lang) == row["tree"]:
                retired.append(name)
            else:
                bad.append(f"{name}: pin moved ({row['tree'][:9]} → {got[:9]})")
            continue
        # `grammar` stays the upstream file: it is what OUTLINER reads, and
        # repointing it would quietly change the other parser's input while
        # claiming to pin this one. What the pin owes is a refusal when the two
        # have come apart, which is the check below rather than a substitution.
        if row["grammar"] and case.grammar.exists() and stamp.digest(case.grammar) != row["grammar"]:
            bad.append(f"{name}: upstream grammar moved since the pin was taken")
            continue
        out.append(case._replace(lang=lang))
    if retired:
        bad.insert(0, f"{len(retired)} row(s) were digested by a RETIRED identity"
                      f" rule ({', '.join(sorted(retired)[:6])}"
                      + (f", +{len(retired) - 6} more" if len(retired) > 6 else "")
                      + f"): the bytes under {stamp.here(home)} still match what"
                        f" was frozen, but `survey` has changed since"
                        f" {stamp.iso(book['when'])}. This pin is not comparable"
                        f" with one taken today; re-freeze it"
                        f" (rule {book['rule'][:9] if book.get('rule') else 'unrecorded'}"
                        f" → {rule()[:9]}).")
    if bad:
        raise ValueError(f"oracle pin {tag!r} does not describe this tree:\n  "
                         + "\n  ".join(bad))
    return out


def minted(book: dict, sample: int = 3) -> str:
    """Which identity rule this pin's numbers were computed under.

    Recorded since the rule digest landed; **measured** for the pins taken
    before it, because "unrecorded" is not an answer and the answer is on disk:
    re-digest a few of the pin's own rows and see which rule reproduces what it
    wrote down. Sampled rather than exhaustive because a rule change moves every
    row at once - it is a property of the code, not of a grammar - so three rows
    settle it for the price of three.
    """
    if book.get("rule") == rule():
        return "current"
    home = PINS / book["tag"]
    now = old = 0
    for name, row in sorted(book["row"].items())[:sample]:
        lang = home / "lang" / name / row["at"]
        if not lang.is_dir():
            continue
        got, *_ = survey(lang)
        now += got == row["tree"]
        old += was(lang) == row["tree"]
    if not now and not old:
        return "moved"
    return "current" if now >= old else "retired"


def pins() -> list[dict]:
    out = []
    for p in sorted(PINS.glob("*/pin.json")) if PINS.is_dir() else []:
        try:
            out.append(json.loads(p.read_text()))
        except (OSError, ValueError):
            continue
    return out


# ----------------------------------------------------------------------- verbs

def show(cases, as_json: bool) -> int:
    seen = court(cases)
    if as_json:
        print(json.dumps(seen.as_dict(), indent=2))
        return 0
    print(f"\n{'grammar':<14}{'oracle':<14}{'files':>7}{'lib':>6}{'age':>10}  newest source")
    print("-" * 84)
    for r in sorted(seen.rows, key=lambda r: (not r.stale, r.name)):
        age = "—" if not r.made else f"{(r.newest - r.made) / 60:+.0f}m"
        print(f"{r.name:<14}{(r.tree[:12] or '—'):<14}{r.files:>7}"
              f"{('yes' if r.lib else 'no'):>6}{age:>10}  {r.where[:34]}"
              f"{'  STALE' if r.stale else ''}")
    print(f"\n{seen.line()}")
    return 0


def ruling(as_json: bool) -> int:
    """What the rule digest covers, and what it does not - in the tool's output.

    The bound belongs here rather than in a dossier because the number is read
    here: `still against` refuses two arms whose rules differ, `pin list` calls
    a pin retired, and both quote nine characters of this digest. Anyone who
    wants to know what those nine characters are a claim *about* can ask the
    thing that made them.
    """
    rows = reads()
    if as_json:
        print(json.dumps({"rule": rule(), "covers": [
            {"name": n, "kind": k, "bytes": len(v)} for n, k, v in rows]}, indent=2))
        return 0
    folded = [r for r in rows if r[1] in ("code", "data")]
    outside = [r for r in rows if r[1] not in ("code", "data")]
    print(f"\nrule {rule()[:9]} - the closure of {', '.join(SEEDS)}")
    print(f"\n{'covered':<30}{'kind':<8}{'bytes':>8}")
    print("-" * 48)
    for name, kind, said in folded:
        print(f"{name:<30}{kind:<8}{len(said):>8}")
    print(f"\n{len(folded)} name(s) folded in."
          f" Edit any of them and this digest moves.")
    print(f"\n{'NOT covered':<30}{'why'}")
    print("-" * 72)
    for name, kind, _ in outside:
        print(f"{name:<30}" + {
            "module": "a module named on the way through; what the rule reads"
                      " from it is folded above",
            "stdlib": "the standard library - pinned by the interpreter, not by"
                      " this repo",
        }.get(kind, "a live object whose bytes cannot be reproduced"))
    print(f"\nThe claim this digest makes is exactly: the {len(folded)} name(s)"
          f" above have not changed.\nIt is NOT a claim that two oracle digests"
          f" are comparable - stdlib behaviour, the\ntree-sitter CLI and the"
          f" bytes on disk are the other three, and `Oracle.cli`, `tree`\nand"
          f" `lower` carry those.")
    if opaque := [r for r in outside if r[1] == "opaque"]:
        print(f"\n{len(opaque)} name(s) are OPAQUE: the rule reads them and"
              f" cannot digest them, so it\nwould hold across a change to one."
              f" That is a hole, not a bound - fix `spell`.")
        return 1
    return 0


def listing() -> int:
    got = pins()
    if not got:
        print(f"no oracle pins under {stamp.here(PINS)}")
        return 0
    print(f"\n{'tag':<16}{'taken':<22}{'grammars':>9}{'rule':>10}  cli")
    print("-" * 81)
    marks = {b["tag"]: minted(b) for b in got}
    for b in got:
        print(f"{b['tag']:<16}{stamp.iso(b['when']):<22}{len(b['row']):>9}"
              f"{marks[b['tag']]:>10}  {b['cli']}")
    if stale := [t for t, m in marks.items() if m == "retired"]:
        print(f"\nrule {rule()[:9]} is today's. {len(stale)} pin(s) were digested"
              f" under the rule it replaced and are NOT comparable with one taken"
              f" now ({', '.join(sorted(stale))}) - re-freeze before using one as"
              f" a control; their rows will read as thirty drifts otherwise.")
    if lost := [t for t, m in marks.items() if m == "moved"]:
        print(f"\n{len(lost)} pin(s) no longer digest to what they recorded under"
              f" either rule ({', '.join(sorted(lost))}) - somebody has written"
              f" into the pin.")
    return 0


def was(home: Path) -> str:
    """The digest rule this file used before generated files came out of it.

    Kept, and run beside the new one on every `verify`, for the reason
    `stamp.py --verdicts` keeps the rule it replaced: a change to a
    discriminator is only demonstrated if the old discriminator is present to
    disagree. Without this the direction rows below would prove the new rule is
    *self-consistent*, which every rule is.
    """
    src = home / "src"
    h, count = hashlib.sha256(), 0
    for p in sorted(q for q in src.rglob("*") if q.is_file()):
        h.update(str(p.relative_to(src)).encode() + b"\0")
        try:
            h.update(p.read_bytes())
        except OSError:
            h.update(b"?\0")
            continue
        count += 1
    return h.hexdigest() if count else ""


def flip(p: Path, at: float = 0.9) -> None:
    """Move one byte deep inside a file, past any banner."""
    blob = bytearray(p.read_bytes())
    i = min(int(len(blob) * at), len(blob) - 1)
    blob[i] = (blob[i] + 1) % 256
    p.write_bytes(bytes(blob))


def scratch(home: Path, tmp: Path) -> Path:
    """A private copy of one grammar's whole root, at the same depth.

    The root and not the home, because the three monorepo grammars keep their
    scanner above their home and a copy that took only the home would be
    testing a grammar with no external scanner in it - which is the case the
    reach below exists for.
    """
    root, at = split(home)
    shutil.copytree(root, tmp / root.name, copy_function=shutil.copy2)
    return tmp / root.name / at


def directions(pick: str = "") -> list[tuple[str, str, bool]]:
    """Both directions of the identity, measured in a scratch tree.

    An identity is two claims and neither implies the other: it must **move**
    when the parser really is a different one, and it must **hold** when the
    same parser has merely been rebuilt. This file has spent its life asserting
    the first and being wrong about the second, and the second is the one that
    cost two lanes an investigation - so both are measured here, on a copy, in
    the same run, and a rule that passes one and fails the other fails.
    """
    live = sorted((p.parent.parent for p in (d.WORK / "lang").rglob("src/grammar.json")
                   if p.is_file() and (p.parent / "scanner.c").is_file()),
                  key=lambda h: (d.named(h) != pick, d.named(h)))
    deep = next((h for h in live if split(h)[1] != Path()), None)
    if not live:
        return [("a grammar with an external scanner to copy", "none on disk", False)]
    home = live[0]
    out: list[tuple[str, str, bool]] = []
    with tempfile.TemporaryDirectory() as t:
        pen = scratch(home, Path(t))
        base, files, _, _ = survey(pen)
        again, *_ = survey(pen)
        out.append((f"the copy digests: {d.named(home)}, {files} authored file(s)",
                    base[:12] or "—", bool(base)))
        out.append(("...and twice, to the same number - a sensor that returned a fresh"
                    " value every call would pass every row below", "stable", base == again))

        # ---- direction one: it must still refuse a genuinely different source.
        for what, target in (("scanner.c", pen / "src" / "scanner.c"),
                             ("grammar.json", pen / "src" / "grammar.json")):
            keep = target.read_bytes()
            flip(target)
            moved, *_ = survey(pen)
            target.write_bytes(keep)
            out.append((f"REFUSES a real edit: one byte of authored {what}",
                        f"{base[:9]} → {moved[:9]}", moved != base))
        extra = pen / "src" / "zz-authored.h"
        extra.write_text("/* a file nobody declared */\n", encoding="utf-8")
        grew, *_ = survey(pen)
        extra.unlink()
        out.append(("REFUSES a file this rule has never heard of - the default is"
                    " authored, so an unknown name cannot leave the identity",
                    f"{base[:9]} → {grew[:9]}", grew != base))
        gone = pen / "src" / "scanner.c"
        keep = gone.read_bytes()
        gone.unlink()
        shrunk, *_ = survey(pen)
        gone.write_bytes(keep)
        out.append(("REFUSES a deletion - a digest that catches an edit and not a"
                    " removal is not a digest of a tree",
                    f"{base[:9]} → {shrunk[:9]}", shrunk != base))
        out.append(("...and every one of those restored, the digest comes back",
                    survey(pen)[0][:12], survey(pen)[0] == base))

        # ---- direction two: it must stop calling a rebuild a different parser.
        made, count = built(pen)
        old = was(pen)
        for p, r in sources(pen):
            if lowered(r):
                p.unlink(missing_ok=True)
        left = {r for _, r in sources(pen)}
        bare, *_ = survey(pen)
        out.append((f"HOLDS across the state a scanner refresh used to leave"
                    f" ({count} generated file(s) deleted) - the exact state css was"
                    f" in when it read as two parsers", bare[:12], bare == base))
        out.append(("...where the rule this replaced calls that same tree a different"
                    " oracle, which is the whole finding",
                    f"{old[:9]} → {was(pen)[:9]}", was(pen) != old))
        if not d.oracle_ready():
            out.append(("a real regenerate", "no tree-sitter CLI - skipped", True))
        elif (got := d.cli([str(d.TS), "generate", "src/grammar.json"], pen)).returncode:
            out.append(("a regenerate to compare against", d.gripe(got.stderr), False))
        else:
            out.append(("HOLDS across a real `tree-sitter generate` - same authored"
                        " bytes, freshly lowered", survey(pen)[0][:12],
                        survey(pen)[0] == base))
            # The declared generated set, re-derived rather than trusted. Every
            # name that came back is one `LOWERED` already claims, and the row
            # above says no authored file moved - so a CLI that began writing a
            # fifth artifact would either fail here as an unrecognised
            # reappearance or there as an authored file the CLI wrote. It cannot
            # slip into the identity between them.
            back = {r for _, r in sources(pen)} - left
            out.append((f"...and every file that reappeared is one `LOWERED` names:"
                        f" {len(back)} of {count}",
                        ", ".join(sorted(r.name for r in back))[:24] or "none",
                        bool(back) and all(lowered(r) for r in back)))
            # Measured, not assumed, and it falsified a prediction of mine: I
            # expected the regenerated parser to differ. `generate` is
            # byte-reproducible on this CLI, so the generated digest comes back
            # to the same number too. That makes the *deletion* state above the
            # only one that ever moved it - which is exactly what the css
            # investigation found, arrived at from the other end.
            out.append(("...and `generate` is byte-reproducible here, so even the"
                        " generated digest returns - the deleted state was the whole"
                        " of the divergence", built(pen)[0][:12], built(pen)[0] == made))

        # The hazard `holdout.prove` watches: a `parser.c` that does not match
        # the `grammar.json` beside it. Identity must NOT move - the language is
        # the same - and the generated digest must, which is why there are two.
        if (gen := pen / "src" / "parser.c").is_file():
            flip(gen)
            out.append(("a `parser.c` that no longer matches its grammar moves the"
                        " GENERATED digest", f"{made[:9]} → {built(pen)[0][:9]}",
                        built(pen)[0] != made))
            out.append(("...and leaves the identity alone, because a torn tree and a"
                        " rebuild are different questions and one digest cannot answer"
                        " both", survey(pen)[0][:12], survey(pen)[0] == base))

    # ---- the reach: the three grammars whose scanner lives above their home.
    if deep is None:
        out.append(("a monorepo grammar to test the reach on", "none on disk", False))
        return out
    with tempfile.TemporaryDirectory() as t:
        pen = scratch(deep, Path(t))
        shared = next((p for p, r in sources(pen) if "src" not in r.parts), None)
        if shared is None:
            out.append((f"{d.named(deep)}'s scanner includes a file above its home",
                        "no climb found", False))
            return out
        base, old = survey(pen)[0], was(pen)
        flip(shared)
        out.append((f"REACHES what the scanner includes: one byte of"
                    f" {d.named(deep)}'s {shared.name}, which lives above its home",
                    f"{base[:9]} → {survey(pen)[0][:9]}", survey(pen)[0] != base))
        out.append(("...and the rule this replaced never saw that file at all, so three"
                    " grammars had no authored C in their identity",
                    f"{old[:9]} = {was(pen)[:9]}", was(pen) == old))
    return out


def verify(pick: str = "") -> int:
    """Prove the claims this file is built on, against this machine.

    Not assertions about a design: each row is a measurement, and each one
    fails loudly if the thing it describes stops being true.

    Two blocks, and they are about different populations, which is worth saying
    because reading one as the other is how the third row below got quoted for
    a week as evidence of two parsers. The first is about the compiled
    **libraries** on this disk and is the argument for identifying an oracle by
    its sources at all. The second is about that identity itself, and holds it
    to both directions at once in a scratch tree.
    """
    W = d.WORK
    seats = [p for p in (W / "seat").iterdir() if (p / "lib").is_dir()] if (W / "seat").is_dir() else []
    seats.append(W)
    langs = sorted(p.name for p in (W / "lang").iterdir() if p.is_dir()) if (W / "lang").is_dir() else []
    many = older = 0
    apart: list[tuple[str, float]] = []
    for name in langs:
        libs = [f for s in seats for x in (".dylib", ".so")
                if (f := s / "lib" / (name + x)).is_file()]
        if not libs:
            continue
        many += len({stamp.digest(f) for f in libs}) > 1
        newest = max((p.stat().st_mtime for p in (W / "lang" / name).rglob("src/*")
                      if p.is_file()), default=0.0)
        older += any(f.stat().st_mtime < newest for f in libs)
        a, b = libs[0].read_bytes(), libs[-1].read_bytes()
        if len(libs) > 1 and len(a) == len(b) and a != b:
            apart.append((name, sum(x != y for x, y in zip(a, b)) / len(a)))
    apart.sort(key=lambda r: r[1])
    least, most = (apart[0], apart[-1]) if apart else (("—", 0.0), ("—", 0.0))
    libraries = (
        ("one grammar's compiled LIBRARY exists as several different files at once",
         f"{many} of {len(langs)} grammars", many > 0),
        (f"...and divergence is not a parser: {least[0]} differs in",
         f"{least[1] * 100:.4f}% of its bytes", bool(apart) and least[1] < 0.001),
        (f"...nor is it always cosmetic: {most[0]} differs in",
         f"{most[1] * 100:.1f}% of its bytes", bool(apart) and most[1] > 0.01),
        ("a library older than the sources beside it - the CLI's rebuild trigger",
         f"{older} of {len(langs)} grammars", older > 0),
    )
    bad, wide = 0, 70
    for head, rows in (("the compiled libraries on this disk", libraries),
                       ("the identity this file assigns, both directions", directions(pick)),
                       ("the RULE version, against what it reads and what it does not", ruled())):
        print(f"\n{head:<{wide}} {'measured':<26}holds")
        print("-" * 104)
        for what, said, ok in rows:
            bad += not ok
            line = textwrap.wrap(what, wide) or [""]
            print(f"{line[0]:<{wide}} {said[:25]:<26}{'yes' if ok else 'NO'}")
            for more in line[1:]:
                print(f"  {more}")
    print(f"\n{'ALL HELD' if not bad else f'{bad} FAILED'} — and the three blocks"
          " are about different populations.")
    print("  Above: rows two and three are why the identity is the SOURCES and not the"
          " library.\n  A library digest calls a rebuild of the same parser a change."
          " Row three is one seat\n  against `lib/`, the pre-seat directory nothing has"
          " written since 2026-08-04; planted\n  as a seat's library it is rebuilt"
          " before it can answer, so the tree is holding one\n  oracle and one file"
          " that loses an argument with the first question anyone asks it.")
    print("  Middle: an identity has to move on a real edit AND hold across a rebuild,"
          " and this\n  file asserted the first while being wrong about the second for"
          " as long as it existed.")
    print("  Below: that identity is computed by code, and the version stamped on it"
          " is only\n  worth reading if it moves when that code does. It hashed three"
          " function bodies; two\n  of the seven names deciding an oracle's identity"
          " were not among them, and one of\n  those is in another module.")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    import plumb  # noqa: PLC0415 - plumb imports nothing from here; keep it one-way

    verb = next((a for a in argv[1:] if not a.startswith("-")), "show")
    as_json = "--json" in argv
    if verb == "list":
        return listing()
    if verb == "rule":
        return ruling(as_json)
    if verb == "verify":
        return verify(next((a.split("=", 1)[1] for a in argv[1:]
                            if a.startswith("--grammar=")), ""))
    cases = plumb.slate()
    if verb == "freeze":
        tag = next((a for a in argv[1:] if not a.startswith("-") and a != verb), "")
        if not tag:
            print("attest.py freeze <tag> - name the pin", file=sys.stderr)
            return 2
        book = freeze(tag, cases)
        print(f"froze {len(book['row'])} oracle(s) into {stamp.here(PINS / tag)}"
              f" · {book['cli']}")
        return 0
    if verb == "show":
        return show(cases, as_json)
    print(__doc__.split("usage:")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
