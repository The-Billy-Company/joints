#!/usr/bin/env python3
"""Which of a grammar's declared externals does anything in this tree exercise?

Nobody could answer that until now, and the cost of not being able to was named
twice in one day by two lanes that never spoke. A lane seating Kotlin's and
Swift's string interiors found that `Maps.kt` and `Chunked.swift` between them
contain no interpolation, no triple quote and no raw string - so a **stateless**
hand, one that keeps no memory across a string body and is therefore wrong the
moment a string interpolates, would have measured byte-perfect on every
measurement this repository takes. A second lane proved Kotlin's whole
19,705-byte orphan problem is the string wall and then *declined to seat the
fix*, because the board could not tell a correct hand from a wrong one.

The corpus is honest about typical code and silent about everything else, and
the silence is load-bearing. This instrument is the two things that silence
needs: a **coverage gate** joining what a grammar declares to what this tree can
lex and actually reaches, and a **specimen tier** of small files carrying the
awkward constructs the corpus never reaches - interpolation nested inside
interpolation, a triple quote with an embedded quote, a raw delimiter appearing
in its own body, an unterminated opener at end of file.

## Four populations, and which of them I trust

  **declared** - the named entries of `externals[]` in `grammar.json`. Exact;
  it is a field in a file.

  **blind** - the terminals joints says it has no stand-in for. Exact, but it
  has to be *pried out*: every reporting path caps the list at eight names and
  appends `+N more`, so a grammar over the cap can never state its own blind set
  in one breath. `enumerate_blind` rotates `externals[]` by eight and unions the
  windows, which is sound because `provision` resolves a troupe by name and
  never by position - and the blind **total** is compared across every rotation,
  so a grammar where order does matter is refused rather than averaged.

  **seated** = declared - blind. *"This tree can make that token."*

  **exercised** - a seated external some file here actually reaches. This is the
  number this lane exists to produce and therefore the one it trusts least, so
  its direction of error is printed on every run: a hidden terminal - the
  `_`-prefixed ones - never becomes a node, so it can be reached and not
  counted. `exercised` is a **floor** and is never rendered as a clearance.

## Why the verdict is a tree and never a byte count

The corpus asks how much of a file got structure. A specimen asks whether the
hand got it *right*, and those want different reports: folding a specimen into a
byte percentage tells you nothing about whether interpolation nested twice came
back correctly shaped. So a specimen carries assertions over the forest, and
`spans` is the one that does the work - a first-match reader closing a triple
quote at an embedded quote produces a node of the *right name* at the *wrong
extent*, and only an assertion pinning the extent can tell those apart. Presence
is not shape.

## What this deliberately does not touch

Specimens live under `research/joinery/specimen/` and are enumerated from there.
They are never written to `upstream/sources/` or `research/joinery/corpus/`,
which is where `breadth.py` and the board read from, so no board number taken
today moves because this tier exists. `verify` asserts that separation rather
than trusting it, and also proves both predicates can still say **no**.

Exit 0 clean, 1 a gate or specimen failed, 2 could not measure.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import plumb  # noqa: E402 - the path has to be set first
import stamp  # noqa: E402
from breadth import DEST, SOURCES  # noqa: E402
from order import BIN, GRAMMARS, ROOT  # noqa: E402
from rung1 import CORPUS, pairs  # noqa: E402

SPECIMENS = ROOT / "research" / "joinery" / "specimen"
WORK = ROOT / ".local" / "specimen"

# `blind to 5 terminal(s): _immediate_paren ...` from `lex` - the blind list,
# capped at eight names. The cap is why the rotation exists; the `+N more` tail
# is read as a count so a caller can tell a truncated window from a whole one.
#
# Deliberately NOT `grammar`'s `cannot be lexed here:` note, which names every
# declared external rather than the blind ones - see `press`.
BLIND = re.compile(r"blind to \d+ terminal\(s\): (.*)")
MORE = re.compile(r"\+(\d+) more")
# `  node_name [12, 20)` from `parse --ranges --all`, and `  value: node_name
# [12, 20)` when the production gives the child a field name. The optional
# `field: ` prefix is not decoration and leaving it out of this pattern was
# this instrument's first lie: Swift prints most of a property declaration
# field-labelled, so the first draft read a tree containing
# `value: line_string_literal [18, 32)` and reported the literal absent. It
# was caught by reading a forest rather than trusting the count, which is the
# same discipline this tier exists to impose on everyone else.
#
# Anonymous tokens print quoted and are deliberately still not matched: an
# external is always a *named* terminal, so reading a quoted row as one would
# inflate `exercised` with punctuation.
ROW = re.compile(
    r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*: )?([A-Za-z_][A-Za-z0-9_]*) \[(\d+), (\d+)\)")
ROOTS = re.compile(r"(\d+) roots?")
MENDED = re.compile(r"mended (\d+)")
WINDOW = 8  # how many blind names any reporting path prints before eliding


class Node(NamedTuple):
    name: str
    start: int
    end: int


class Reach(NamedTuple):
    """One grammar's four populations, joined."""

    grammar: str
    declared: list[str]
    blind: list[str]
    exercised: list[str]
    rounds: int  # how many windows were unioned to pry the blind list out
    steady: bool  # was the blind total invariant across every rotation
    read: list[str]  # what was parsed to answer `exercised`
    aliased: dict[str, str]  # external -> the name the grammar makes it wear

    @property
    def seated(self) -> list[str]:
        gone = set(self.blind)
        return [n for n in self.declared if n not in gone]

    @property
    def unexercised(self) -> list[str]:
        got = set(self.exercised)
        return [n for n in self.seated if n not in got]

    @property
    def unseeable(self) -> list[str]:
        """Seated externals `exercised` structurally cannot count.

        A tree-sitter terminal whose name begins `_` is hidden: it is consumed
        by a production and never becomes a node, so observing the forest can
        never witness it however hard the file leans on it. Julia is the whole
        argument - eleven of its sixteen externals are seated and every one of
        them is hidden, so `exercised` reports zero for a grammar whose command
        literals demonstrably fire (unseat `_end_cmd` and a green specimen goes
        red). Reporting that zero without this column would read as a finding
        when it is a blind spot in the instrument, which is the failure this
        lane exists to prevent - so it is named on every row that has one.

        **The leading `_` is not the only way, and believing it was made this
        gate's denominator too big.** A grammar may `alias` an external to some
        other name, and then a perfectly correct parse yields a node that is
        never called what the external is called: rust's `string_close` arrives
        as an anonymous `"`, its `raw_string_literal_content` as a *named*
        `string_content`, and six of php's ten visible externals all arrive as
        `string_content` together. Ten externals over three grammars, and every
        one of them was sitting in the denominator as an unmet target nobody
        could ever meet. Found by authoring `rust/string-close.rs`, watching
        tree-sitter itself build the construct correctly, and the claim still
        failing - which is the whole argument for the specimen tier stated
        against the gate that motivated it."""
        return [n for n in self.seated
                if n.startswith("_") or n in self.aliased]

    @property
    def scorable(self) -> bool:
        """Whether a ratio means anything here.

        A grammar declaring no externals has nothing to cover, and a gate that
        prints `0/0 = clean` for the seven grammars in that position has found
        nothing and said everything is fine - the exact shape of the failure
        this instrument exists to prevent. Those are reported `n/a` and are
        excluded from every total."""
        return len(self.declared) > 0


# ---------------------------------------------------------------- the binary


def press(path: Path) -> tuple[list[str], int] | None:
    """The blind names one press reports, and how many it elided.

    Read from **`lex`**, and the reason is the twenty-second instrument this
    repository has caught reporting a number a report then repeated.

    `joints grammar` closes with `note: external scanner tokens cannot be
    lexed here: ...`, which reads exactly like the blind set and is not it. On
    julia that note lists all sixteen declared externals; `lex` on the same
    grammar reports **five**, and names them - the `_immediate_*` family - while
    the eleven the note also named are seated and demonstrably firing, because
    unseating one of them reddens a specimen that passes whole. The note is a
    restatement of `externals[]` wearing a blindness sentence.

    An earlier draft of this gate read that note and reported `seated 0` for all
    twenty-three scorable grammars: a maximally alarming headline saying this
    tree can lex none of the 461 externals it declares, produced entirely by
    believing the wrong reporter. `lex` and `parse` agree with each other and
    with the specimens, so `lex` is what this reads.

    None when the binary refused the grammar, which is a different answer from
    "blind to nothing" and must not be flattened into one."""
    got = subprocess.run([str(BIN), "lex", str(path), str(scratch())],
                         capture_output=True, text=True, timeout=900)
    if got.returncode not in (0, 1):
        return None
    if not (m := BLIND.search(got.stdout + got.stderr)):
        return ([], 0)
    more = int(x[1]) if (x := MORE.search(m[1])) else 0
    return ([w for w in MORE.sub("", m[1]).split() if w], more)


def scratch() -> Path:
    """One byte for `lex` to chew on.

    Blindness is a property of the pressed table and not of the text, so what
    the file contains is irrelevant - but `lex` wants one, and handing it each
    grammar's own corpus file would make a grammar-level fact look like a
    file-level one."""
    WORK.mkdir(parents=True, exist_ok=True)
    p = WORK / "scratch.txt"
    if not p.exists():
        p.write_text("\n")
    return p


def enumerate_blind(name: str) -> tuple[list[str], int, bool]:
    """Pry a grammar's whole blind set out of a reporter that elides past eight.

    The rotation is sound because `provision` in `outside.zig` resolves a troupe
    by looking each part up **by name**, never by position, so rotating
    `externals[]` cannot change which troupes seat. That is an argument from
    reading the source, and an argument is not a measurement, so the invariance
    is also *checked*: every rotation's blind total is compared and a grammar
    whose total moves comes back `steady=False`, which the gate refuses.

    Renaming a single external, by contrast, is **not** sound and must never be
    used here. A one-character case change to one blind Kotlin external took its
    blind count from 8 to 10, because `seated` requires a cast's full membership
    and losing one part unseats the whole troupe - so a rename ablation reports
    every member of a seated troupe as load-bearing whether it is or not."""
    src = GRAMMARS / f"{name}.json"
    doc = json.loads(src.read_text())
    ext = doc.get("externals", [])
    if (first := press(src)) is None:
        return ([], 0, False)
    names, more = first
    if more == 0:
        return (sorted(names), 1, True)

    seen, totals, rounds = set(names), {len(names) + more}, 1
    WORK.mkdir(parents=True, exist_ok=True)
    for k in range(WINDOW, len(ext), WINDOW):
        spun = dict(doc)
        spun["externals"] = ext[k:] + ext[:k]
        p = WORK / f"{name}.rot{k}.json"
        p.write_text(json.dumps(spun))
        if (got := press(p)) is None:
            continue
        seen |= set(got[0])
        totals.add(len(got[0]) + got[1])
        rounds += 1
    return (sorted(seen), rounds, len(totals) == 1)


def forest(grammar: Path, src: Path) -> list[Node]:
    """Every named node in one parse, with its extent.

    `--all` keeps the anonymous tokens so a specimen can assert over
    punctuation, and `--ranges` is what makes `spans` possible at all: a
    first-match reader and a greedy one produce the same node *name*, and only
    the extent tells them apart."""
    got = subprocess.run([str(BIN), "parse", str(grammar), str(src),
                          "--ranges", "--all"],
                         capture_output=True, text=True, timeout=900)
    return [Node(m[1], int(m[2]), int(m[3]))
            for line in got.stdout.splitlines() if (m := ROW.match(line))]


def stop(grammar: Path, src: Path) -> tuple[int, int, str]:
    """Roots and mends, read off the binary's own stop line - or the refusal.

    The third field is why this returns three. This read used to default a
    missing stop line to `1` roots and `0` mends, which is the exact shape of
    a perfect parse, so a binary that never parsed at all scored `roots 1` and
    `mends 0` as claims HELD. `joints parse upstream/grammars/yaml.json` exits
    2 with `yaml has no lexable terminal at all` - the grammar is 41 externals
    and zero literals, so there is nothing for the lexer to be built out of -
    and yaml/comment.yml read 2 of 4 against a binary that had not read a byte
    of it. Two of those two were the structural claims, the ones a specimen
    author is least likely to re-derive by hand.

    A refusal is now its own answer and every claim in the specimen fails
    against it, named. Silence is not agreement here either."""
    got = subprocess.run([str(BIN), "parse", str(grammar), str(src), "--quiet"],
                         capture_output=True, text=True, timeout=900)
    roots, mends = ROOTS.search(got.stderr), MENDED.search(got.stderr)
    if roots is not None:  # a mended, truncated, many-rooted parse is a parse
        return int(roots[1]), int(mends[1]) if mends else 0, ""
    why = next((l.strip() for l in got.stderr.splitlines()
                if "blind to" not in l), "") or f"exit {got.returncode}"
    return 0, 0, why.removeprefix("joints: ")


# ---------------------------------------------------------------- population


def declared(name: str) -> list[str]:
    doc = json.loads((GRAMMARS / f"{name}.json").read_text())
    return [e["name"] for e in doc.get("externals", []) if e.get("name")]


def worn(node, seen: dict[str, int], as_: dict[str, set[str]]) -> None:
    """Count where a symbol is referred to, and where it is referred to AS
    something else.

    Both, because only the ratio settles anything. An `ALIAS` over a `SYMBOL`
    is the grammar author saying *emit this under a different name*, and a
    symbol aliased at **every** use site can never reach a tree under its own
    name however correctly it parses. Aliased at *some* of them, it still can -
    bash aliases `test_operator` to `word` in one production and admits it
    plainly in another, and a rule that fired on the first alias it found
    reported bash `exercised 5 of 4 visible`, a ratio above one, which is what
    an over-tight rule looks like when it has nothing to check it."""
    if isinstance(node, dict):
        if node.get("type") == "SYMBOL":
            seen[node["name"]] = seen.get(node["name"], 0) + 1
            return
        if node.get("type") == "ALIAS" and node.get("content", {}).get("type") == "SYMBOL":
            who, val = node["content"]["name"], node.get("value", "?")
            as_.setdefault(who, set()).add(val if node.get("named") else f'"{val}"')
            # And do NOT descend into the content. Counting the aliased symbol
            # as a plain reference too is how the every-use-site rule read all
            # ten renamed externals as plainly referenced and corrected nothing.
            return
        for key, val in node.items():
            if key != "type":
                worn(val, seen, as_)
    elif isinstance(node, list):
        for v in node:
            worn(v, seen, as_)


def renames(name: str) -> dict[str, str]:
    """Every declared external the grammar renames at every one of its use sites."""
    doc = json.loads((GRAMMARS / f"{name}.json").read_text())
    plain: dict[str, int] = {}
    as_: dict[str, set[str]] = {}
    worn(doc.get("rules", {}), plain, as_)
    ext = set(declared(name))
    return {k: " or ".join(sorted(v)) for k, v in as_.items()
            if k in ext and not plain.get(k)}


def grammars() -> list[str]:
    return sorted(p.stem for p in GRAMMARS.glob("*.json"))


def corpus_for(name: str) -> list[Path]:
    """Every file in this tree parsed with this grammar.

    Both populations, deliberately: the real-world corpus **and** the ledger
    programs, because `exercised` is a claim about the whole tree and scoping it
    to one of the two would understate reach and overstate the finding. Both
    mappings are read from the instruments that own them rather than restated,
    so this cannot fall out of step by one file."""
    out = []
    if name in SOURCES:
        out.append(DEST / SOURCES[name][1])
    out += [CORPUS / leaf for g, leaf in pairs() if g == name]
    return [p for p in out if p.exists()]


def reach(name: str, *, with_specimens: bool = True) -> Reach:
    grammar = GRAMMARS / f"{name}.json"
    dec = declared(name)
    blind, rounds, steady = enumerate_blind(name)
    gone, seen, read = set(blind), set(), []
    want = {n for n in dec if n not in gone}
    files = corpus_for(name) + (specimens_for(name) if with_specimens else [])
    for src in files:
        read.append(src.name)
        for node in forest(grammar, src):
            if node.name in want:
                seen.add(node.name)
    return Reach(name, dec, blind, sorted(seen), rounds, steady, read, renames(name))


# ---------------------------------------------------------------- specimens


class Claim(NamedTuple):
    verb: str
    args: list[str]
    line: int


class Trial(NamedTuple):
    grammar: str
    src: Path
    passed: list[str]
    failed: list[str]
    refused: str = ""  # the binary never parsed this at all, and said why

    @property
    def ok(self) -> bool:
        return not self.failed and not self.refused


def specimens_for(name: str) -> list[Path]:
    d = SPECIMENS / name
    if not d.is_dir():
        return []
    return sorted(p for p in d.iterdir()
                  if p.is_file() and p.suffix not in (".expect", ".md"))


def claims(src: Path) -> list[Claim]:
    """A specimen's assertions, read from the `.expect` beside it.

    Five verbs, and the fifth is the point:

      `roots N`               the forest is exactly N trees
      `mends N`               the parse repaired exactly N times
      `holds NAME`            a node by that name exists
      `lacks NAME`            no node by that name exists
      `spans NAME START END`  a node by that name covers exactly those bytes

    `lacks` catches a *confidently wrong* shape - Kotlin's `${n + 1}` currently
    comes back as a `lambda_literal`, which is the failure mode the troupe
    contract calls worse than an unanswered token. `spans` catches a right name
    at a wrong extent, which is the only way to state greediness."""
    p = src.with_suffix(src.suffix + ".expect")
    if not p.exists():
        return []
    out = []
    for i, line in enumerate(p.read_text().splitlines(), 1):
        if not (line := line.split("#")[0].strip()):
            continue
        word = line.split()
        out.append(Claim(word[0], word[1:], i))
    return out


def judge(name: str, src: Path) -> Trial:
    grammar = GRAMMARS / f"{name}.json"
    trees = forest(grammar, src)
    roots, mends, refused = stop(grammar, src)
    by = {n.name for n in trees}
    passed, failed = [], []
    if refused:
        return Trial(name, src, [],
                     [f"{c.verb} {' '.join(c.args)} - REFUSED: {refused}"
                      for c in claims(src)], refused)
    for c in claims(src):
        said = f"{c.verb} {' '.join(c.args)}"
        if c.verb == "roots":
            ok, got = roots == int(c.args[0]), f"{roots} roots"
        elif c.verb == "mends":
            ok, got = mends == int(c.args[0]), f"{mends} mends"
        elif c.verb == "holds":
            ok, got = c.args[0] in by, "absent"
        elif c.verb == "lacks":
            ok, got = c.args[0] not in by, "present"
        elif c.verb == "spans":
            want = (c.args[0], int(c.args[1]), int(c.args[2]))
            hit = [n for n in trees if n.name == c.args[0]]
            ok = any(n == Node(*want) for n in hit)
            got = ", ".join(f"[{n.start}, {n.end})" for n in hit) or "absent"
        else:
            ok, got = False, "unknown verb"
        (passed if ok else failed).append(said if ok else f"{said} - got {got}")
    return Trial(name, src, passed, failed)


# ---------------------------------------------------------------- the verbs


def render(r: Reach, *, verbose: bool) -> None:
    if not r.scorable:
        print(f"  {r.grammar:20} n/a   declares no externals")
        return
    mark = "" if r.steady else "  UNSTEADY"
    hid = len(r.unseeable)
    seen = len(r.seated) - hid
    gone = [n for n in r.seated if n in r.aliased and not n.startswith("_")]
    print(f"  {r.grammar:20} declared {len(r.declared):3}  "
          f"seated {len(r.seated):3}  exercised {len(r.exercised):3}"
          f" of {seen:3} visible  ({hid} hidden){mark}")
    if verbose and r.blind:
        print(f"      blind       {' '.join(r.blind)}")
    if gone:
        print(f"      renamed     " + " ".join(f"{n}->{r.aliased[n]}" for n in gone)
              + "  ← the grammar aliases these; no parse can ever name them")
    if verbose and (miss := [n for n in r.unexercised if n not in r.unseeable]):
        print(f"      unexercised {' '.join(miss)}")


def coverage(args) -> int:
    names = [args.grammar] if args.grammar else grammars()
    rows = []
    for i, n in enumerate(names, 1):
        # On stderr, so `--json` stays a clean pipe. A gate that presses a
        # grammar per rotation is minutes of silence otherwise, and silence is
        # indistinguishable from a hang.
        print(f"\r  {i}/{len(names)} {n:20}", end="", file=sys.stderr, flush=True)
        rows.append(reach(n, with_specimens=not args.corpus_only))
    print("\r" + " " * 40 + "\r", end="", file=sys.stderr, flush=True)
    if args.json:
        print(json.dumps([{"grammar": r.grammar, "declared": r.declared,
                           "blind": r.blind, "seated": r.seated,
                           "exercised": r.exercised,
                           "unexercised": r.unexercised, "steady": r.steady,
                           "read": r.read} for r in rows], indent=2))
        return 0

    scope = "corpus only" if args.corpus_only else "corpus and specimens"
    print(f"external coverage - {scope}\n")
    for r in sorted(rows, key=lambda r: (r.scorable, -len(r.declared))):
        render(r, verbose=args.verbose)

    live = [r for r in rows if r.scorable]
    dec = sum(len(r.declared) for r in live)
    sea = sum(len(r.seated) for r in live)
    hid = sum(len(r.unseeable) for r in live)
    ren = sum(1 for r in live for n in r.seated
              if n in r.aliased and not n.startswith("_"))
    exe = sum(len(r.exercised) for r in live)
    seen = sea - hid
    print(f"\n  {len(live)} scorable grammar(s), {len(rows) - len(live)} n/a")
    print(f"  declared {dec}  seated {sea} ({sea / dec:.0%} of declared)")
    print(f"  of those seated, {hid} cannot be witnessed at all - {hid - ren} hidden by"
          f" a leading `_`\n  and {ren} aliased to another name by the grammar itself;"
          f"\n  of the {seen} that can be, {exe} are exercised"
          + (f" ({exe / seen:.0%})" if seen else ""))
    print("\n  exercised is a FLOOR twice over: a hidden terminal never becomes"
          "\n  a node, and a seated one can be reached without being reported."
          "\n  Never read it as a clearance. A construct can also parse whole"
          "\n  with its external blind, because the press keeps an ordinary"
          "\n  token for any spelling it can lex - so `seated` is a floor on"
          "\n  capability too, and only a specimen settles a given construct.")
    print("\n  And 456 of the 461 declared externals have no body in grammar.json,"
          "\n  so their spelling lives in a C scanner and nothing here reads it."
          "\n  `tool/absent.py` owns the other 5,284 spellings a grammar does"
          "\n  write down, and neither instrument covers the other's half.")
    if any(not r.steady for r in rows):
        print("\n  UNSTEADY grammars changed their blind total under rotation;"
              "\n  their blind set is not trustworthy and was not scored.")
        return 1
    return 0


def run(args) -> int:
    names = [args.grammar] if args.grammar else \
        sorted(p.name for p in SPECIMENS.iterdir() if p.is_dir())
    trials = [judge(n, s) for n in names for s in specimens_for(n)]
    if not trials:
        print("specimen: no specimens found - a suite that measures nothing "
              "cannot pass", file=sys.stderr)
        return 2

    for t in trials:
        head = "REFUSED" if t.refused else ("ok  " if t.ok else "FAIL")
        print(f"{head} {t.grammar}/{t.src.name}  "
              f"{len(t.passed)}/{len(t.passed) + len(t.failed)}")
        for f in t.failed:
            print(f"       {f}")
    bad = [t for t in trials if not t.ok]
    empty = [t for t in trials if not t.passed and not t.failed]
    print(f"\n  {len(trials) - len(bad)}/{len(trials)} specimen(s) sound")
    if empty:
        print(f"  {len(empty)} specimen(s) assert NOTHING - that is a vacuous "
              "pass and is failed here", file=sys.stderr)
        return 1
    return 1 if bad else 0


def listing(args) -> int:
    for d in sorted(p for p in SPECIMENS.iterdir() if p.is_dir()):
        for s in specimens_for(d.name):
            n = len(claims(s))
            print(f"  {d.name:12} {s.name:34} {n} claim(s)"
                  f"{'  NO ASSERTIONS' if not n else ''}")
    return 0


def show(args) -> int:
    src = Path(args.path)
    name = src.parent.name
    print(f"--- {src} ---")
    print(src.read_text())
    print(f"--- forest ({name}) ---")
    for n in forest(GRAMMARS / f"{name}.json", src):
        print(f"  {n.name} [{n.start}, {n.end})")
    t = judge(name, src)
    print(f"--- claims: {len(t.passed)} held, {len(t.failed)} failed ---")
    for f in t.failed:
        print(f"  FAIL {f}")
    return 0 if t.ok else 1


def oracle(args) -> int:
    """Tree-sitter's own tree over a specimen, so a claim can come from the spec.

    A claim derived by running joints and writing down what it said is not a
    claim; it is a snapshot, and it passes forever including the whole time the
    hand is wrong. This is the other reader - the grammar's reference
    implementation over the same bytes - and it is what a `spans` extent should
    be copied off when the construct has one.

    It is a **reader, not an authority**. tree-sitter ERRORs on 34,687 built
    bytes of this corpus and a specimen is chosen precisely for being awkward,
    so an ERROR here is common and is printed rather than hidden: where the
    oracle stops, the claim has to come from the source text and the grammar,
    and this says which of the two you are in.
    """
    import differential as d  # noqa: PLC0415 - one call site, kept beside its reason

    # Resolved, because the tree-sitter CLI is run with its own working
    # directory and a relative path arrives there meaning somewhere else - it
    # answers `No files were found`, which reads exactly like a parse refusal.
    src = Path(args.path).resolve()
    name = args.grammar or src.parent.name
    case = next((c for c in plumb.slate() if c.name == name), None)
    if case is None:
        print(f"specimen: no grammar named {name}", file=sys.stderr)
        return 2
    blob = src.read_bytes()
    print(f"--- {src} ({len(blob)} bytes) ---")
    print(blob.decode("utf-8", "replace"))
    try:
        d.lay_out()
        with d.alone(d.named(case.lang)):
            d.oracle_build(case.lang, case.grammar)
        nodes = plumb.oracle(case._replace(source=src), blob)
    except (OSError, ValueError, RuntimeError) as bad:
        print(f"--- tree-sitter refused: {bad} ---", file=sys.stderr)
        return 1
    print(f"--- tree-sitter ({name}) ---")
    hurt = 0
    for n in nodes:
        hurt += n.name.startswith(plumb.HURT)
        print(f"  {'  ' * n.depth}{n.name} [{n.start}, {n.end})"
              f"  {blob[n.start:min(n.end, n.start + 24)]!r}")
    print(f"--- {len(nodes)} node(s), {hurt} in error ---")
    if hurt:
        print("specimen: the oracle ERRORed here, so it is not the authority on this"
              " specimen.\n  Derive the claim from the source text and the grammar,"
              " and say so in the .expect.", file=sys.stderr)
    return 0


def verify(args) -> int:
    """Prove this instrument can still say no.

    A gate reporting everything clean because it measured nothing is the exact
    failure this lane was created to prevent, so the instrument is required to
    demonstrate a red on demand - not argue that it would go red.

    Four assertions. Three prove a predicate can fail; the fourth proves the
    specimen tier is invisible to the board."""
    bad = 0

    # 1. The specimen population is disjoint from both corpus populations, so
    #    no board number moves because this tier exists.
    board = {p.resolve() for p in DEST.glob("*")} | \
            {p.resolve() for p in CORPUS.glob("*")}
    leaked = [s for d in SPECIMENS.iterdir() if d.is_dir()
              for s in specimens_for(d.name) if s.resolve() in board]
    print(f"{'ok  ' if not leaked else 'FAIL'} specimens are outside the corpus"
          f" ({len(board)} board file(s) checked)")
    bad += bool(leaked)

    # 2. A claim can fail. Assert something false about a real specimen and
    #    watch `judge` refuse it - the regression the brief asks to watch,
    #    performed rather than asserted.
    WORK.mkdir(parents=True, exist_ok=True)
    probe = WORK / "cannot-hold.kt"
    probe.write_text('val a = 1\n')
    probe.with_suffix(".kt.expect").write_text(
        "holds source_file\nholds a_node_no_grammar_will_ever_emit\n")
    t = judge("kotlin", probe)
    ok = len(t.passed) == 1 and len(t.failed) == 1
    print(f"{'ok  ' if ok else 'FAIL'} a claim can fail "
          f"({len(t.passed)} held, {len(t.failed)} failed - want 1 and 1)")
    bad += not ok

    # 3. `spans` can tell a right name at a wrong extent from a right one.
    #    This is the assertion the whole tier rests on: without it a
    #    first-match reader passes every greedy-close specimen.
    trees = forest(GRAMMARS / "kotlin.json", probe)
    if root := next((n for n in trees if n.name == "source_file"), None):
        wide = judge_span(trees, "source_file", root.start, root.end)
        narrow = judge_span(trees, "source_file", root.start, root.end - 1)
        ok = wide and not narrow
        print(f"{'ok  ' if ok else 'FAIL'} spans distinguishes extent "
              f"(exact {wide}, off-by-one {narrow} - want True and False)")
        bad += not ok
    else:
        print("FAIL spans check could not find a root to measure")
        bad += 1

    # 4. The coverage gate refuses to score a grammar with no externals, so it
    #    cannot report seven grammars clean by measuring nothing.
    blanks = [n for n in grammars() if not declared(n)]
    scored = [n for n in blanks if reach(n, with_specimens=False).scorable]
    ok = bool(blanks) and not scored
    print(f"{'ok  ' if ok else 'FAIL'} zero-external grammars are unscorable "
          f"({len(blanks)} found, {len(scored)} wrongly scored)")
    bad += not ok

    # 5. A hand regression turns a green specimen red - performed, not argued.
    #
    #    The lever is the one that made rename ablation useless as a coverage
    #    oracle, used here for the one thing it *is* good for: `seated` demands
    #    a cast's full membership, so renaming one member unseats the whole
    #    troupe and the hand stops answering. That is a real regression of a
    #    real hand, not a mutated source file and not a mocked verdict, and a
    #    tier that cannot notice it is decoration.
    ok, note = regressed()
    print(f"{'ok  ' if ok else 'FAIL'} a hand regression reddens a green "
          f"specimen ({note})")
    bad += not ok

    # 6. A refusal is not a clean parse. `stop` used to default a missing stop
    #    line to one root and no mends, so a grammar the binary will not even
    #    lex scored `roots 1` and `mends 0` as claims HELD - and yaml, which is
    #    41 externals and zero literals, did exactly that at 2 of 4. Assert that
    #    a refused grammar scores nothing held, over whichever grammars refuse
    #    today. If none do, say so; a refusal check with nothing to refuse is
    #    not a pass.
    ok, note = refuses()
    print(f"{'ok  ' if ok else 'FAIL'} a refusal holds no claim ({note})")
    bad += not ok

    print(f"\n  {6 - bad}/6 assertion(s) held")
    return 1 if bad else 0


def refuses() -> tuple[bool, str]:
    """Find a grammar the binary will not parse, and prove it scores zero.

    The probe asserts `roots 1` and `mends 0` deliberately: those two are what
    a defaulted read makes true for free, so they are the claims that must not
    hold. Any other pair would leave the original bug alive underneath."""
    WORK.mkdir(parents=True, exist_ok=True)
    probe = WORK / "refusal-probe.txt"
    probe.write_text("x\n")
    probe.with_suffix(".txt.expect").write_text("roots 1\nmends 0\n")
    for name in grammars():
        if not stop(GRAMMARS / f"{name}.json", probe)[2]:
            continue
        t = judge(name, probe)
        held = len(t.passed)
        return (held == 0 and bool(t.refused),
                f"{name} refused: {t.refused[:44]} - {held} claim(s) held")
    return (False, "no grammar refuses anything, so this proves nothing")


def regressed() -> tuple[bool, str]:
    """Unseat one troupe and check a specimen that was green goes red.

    Julia's `command.jl` is the subject because it passes whole today, so a red
    afterwards can only have come from the regression. `_end_cmd` is the member
    renamed: it is what closes a command literal, and without it the cast
    cannot seat."""
    src = SPECIMENS / "julia" / "command.jl"
    if not src.exists() or not judge("julia", src).ok:
        return (False, "julia/command.jl is not green, so it cannot redden")

    doc = json.loads((GRAMMARS / "julia.json").read_text())
    doc["externals"] = [dict(e, name=e["name"] + "_x")
                        if e.get("name") == "_end_cmd" else e
                        for e in doc["externals"]]
    WORK.mkdir(parents=True, exist_ok=True)
    hurt = WORK / "julia.unseated.json"
    hurt.write_text(json.dumps(doc))

    trees = forest(hurt, src)
    by = {n.name for n in trees}
    still = [c for c in claims(src)
             if c.verb == "holds" and c.args[0] in by]
    whole = len(claims(src))
    return (len(still) < whole,
            f"{whole - len(still)} of {whole} claim(s) stopped holding")


def judge_span(trees: list[Node], name: str, start: int, end: int) -> bool:
    return any(n == Node(name, start, end) for n in trees)


def status(args) -> int:
    kinds = sorted(p.name for p in SPECIMENS.iterdir() if p.is_dir()) \
        if SPECIMENS.is_dir() else []
    total = sum(len(specimens_for(k)) for k in kinds)
    said = sum(len(claims(s)) for k in kinds for s in specimens_for(k))
    print(f"  specimen tier   {len(kinds)} grammar(s), {total} file(s), "
          f"{said} claim(s)")
    print(f"  binary          {BIN}")
    print(f"  board is        {DEST} and {CORPUS} - untouched by this tier")
    return 0


def attributed(anyway: bool = False) -> tuple[stamp.Stamp, int]:
    """Name the binary that is about to answer, and refuse it if nobody chose it.

    This file used to read whatever `zig-out/bin/joints` happened to hold and
    print a verdict without mentioning it. Ten lanes build into that prefix. A
    lane on its final pass got **7 of 20 sound from a tree that builds 14 of
    20** - a sibling had rebuilt the shared prefix from a different state
    mid-run - and nothing in the output said so. It was caught because the
    number was implausible against work that lane had just finished, which is
    not a mechanism.

    So the rule is enforced rather than remembered, and it is drawn as narrowly
    as it can be while still closing the hole:

    - **Every** report carries `stamp.line()`. A number without a binary
      identity beside it is not a measurement anyone can retake.
    - A run is REFUSED, exit 3, when it is both **unattributed** - the default
      shared prefix, no `JOINTS_BIN` - and the binary **does not match this
      tree**, either because a source is newer than it (`stale`) or because it
      was built from different sources than the repo now holds (`drift`).

    Those two conditions together are precisely the failure that happened, and
    nothing else is refused. A deliberate pin drifts by design - measuring an
    older tree on purpose is the whole point of `pin.py` - so `told` exempts
    it; and a default prefix that genuinely matches the tree is what a
    developer who just ran `zig build` has, so it passes untouched. `--anyway`
    downgrades the refusal to a printed hazard for the case where somebody
    knows better than this paragraph.
    """
    mark = stamp.take(BIN)
    if mark.told or not (mark.stale or mark.drift):
        return mark, 0
    how = " and ".join(w for w, on in (("is older than a source in it", mark.stale),
                                       ("was built from different sources", mark.drift)) if on)
    print(f"\n{mark.line()}\n", file=sys.stderr)
    print(f"specimen: REFUSING to judge - nobody chose this binary and it {how}.\n"
          f"  {BIN}\n"
          f"  is the prefix every lane in this tree builds into, so it holds whichever\n"
          f"  sibling built last. A specimen run against it grades a tree that may not be\n"
          f"  yours: that has already produced `7 of 20 sound` from a tree building 14.\n\n"
          f"  Pin a binary you own, and the pin records which tree it is:\n"
          f"      python3 tool/pin.py build <name> && export JOINTS_BIN=$(python3"
          f" tool/pin.py path <name>)\n"
          f"  Or rebuild the shared prefix and accept the race:\n"
          f"      zig build\n"
          f"  Or run it anyway and wear the stamp:\n"
          f"      python3 tool/specimen.py <verb> --anyway", file=sys.stderr)
    return mark, 3


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    # Carried by every verb rather than the root, so it reads where a hand puts
    # it: the refusal names `<verb> --anyway`, and an escape hatch you have to
    # type in an unnatural position is one people work around instead.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--anyway", action="store_true",
                        help="run against an unattributed, out-of-date binary and wear the stamp")
    sub = ap.add_subparsers(dest="verb", required=True, parser_class=lambda **kw:
                            argparse.ArgumentParser(parents=[common], **kw))

    c = sub.add_parser("coverage", help="join declared, seated and exercised")
    c.add_argument("--grammar")
    c.add_argument("--json", action="store_true")
    c.add_argument("--verbose", "-v", action="store_true")
    c.add_argument("--corpus-only", action="store_true",
                   help="what the real corpus reaches, with specimens excluded")
    c.set_defaults(fn=coverage)

    r = sub.add_parser("run", help="judge every specimen against its claims")
    r.add_argument("--grammar")
    r.set_defaults(fn=run)

    sub.add_parser("list", help="every specimen and its claim count") \
        .set_defaults(fn=listing)
    s = sub.add_parser("show", help="one specimen, its forest and its claims")
    s.add_argument("path")
    s.set_defaults(fn=show)
    o = sub.add_parser("oracle", help="tree-sitter's tree over a specimen, to write claims from")
    o.add_argument("path")
    o.add_argument("--grammar")
    o.set_defaults(fn=oracle)
    sub.add_parser("verify", help="prove this instrument can still say no") \
        .set_defaults(fn=verify)
    sub.add_parser("status", help="what this tier is, and what it does not touch") \
        .set_defaults(fn=status)

    args = ap.parse_args()
    mark, balk = attributed(args.anyway)
    if balk and not args.anyway:
        return balk
    try:
        code = args.fn(args)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
        print(f"specimen: {e}", file=sys.stderr)
        return 2
    # After the verdict, never before it: `moved()` asks whether the tree
    # shifted while this ran, and that interval is not over until something
    # prints. Sweeps here take minutes and four lanes land inside one.
    print(mark.line())
    if balk:
        print("specimen: this ran --anyway against an unattributed binary; the verdict above"
              " grades whichever tree that prefix holds, not necessarily this one.",
              file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
