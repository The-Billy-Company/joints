#!/usr/bin/env python3
"""Is a "grammar gap" a gap? Ask the only party that reads the same file.

`research/joinery/owners/GAPS.md` says of eighteen walls that **no derivation
exists** in the vendored `grammar.json` - so no LR parser over that file accepts
the construct, and 106,798 bytes of the damage board belong to nobody in this
tree. Tree-sitter reads the same `grammar.json`. So every one of the eighteen is
a falsifiable prediction, and this is the falsification.

## Four outcomes, and the third one is why this is not a binary

  **gap**       tree-sitter refuses it too. The verdict stands.
  **ours**      tree-sitter parses it **with its external scanner stubbed out**,
                so `grammar.json` alone derives the construct and the closure
                that said otherwise is wrong.
  **external**  tree-sitter parses it only with the scanner running. Not a gap
                and not a conflict: an external we have not seated, which is the
                specimen lane's currency.
  **both**      both sides return a tree and both trees are wrong.

The stub arm is what makes `ours` and `external` different verdicts rather than
a guess off the `externals` array. A token can be declared external and have
nothing to do with why a construct parses; twenty-two of twenty-eight grammars
here compile 486,301 bytes of scanner C, and reading a name out of a list is not
evidence about any of it. So the scanner is *replaced* - every
`tree_sitter_<lang>_external_scanner_scan` becomes one line returning `false` -
and the same witness is parsed again. What survives that, `grammar.json` derives.

## What a witness is, and why nothing here is shrunk automatically

Each row carries a hand-authored file holding the construct found at that wall's
byte offset, and **no shrinker touched any of them**. A lane's automatic
shrinker was green while destructive: it deleted a token while the failure still
held, turning `$signed(a) < $signed(b)` into `$signed < $signed(b)` - a
different defect that happened to share a state number - and every witness it
produced named its parent's wall. Minimising against "the failure still
reproduces" minimises toward *a* failure, not *the* failure.

Ablation is out for the same reason and a stronger one: blanking a construct
that partly parses removes its contribution too, so the measurement cannot tell
a grammar gap from a productive construct. Four lanes used it before that was
understood.

## The controls

Every grammar carries an **innocent** witness: the same shape with the suspect
construct removed. If an innocent comes back walled, the witness is measuring my
ability to write valid PHP rather than anything about the grammar, and that
grammar's verdict does not ship. `prove` is the other half - it hands the
harness a construct that genuinely is not in the language and requires the
answer `gap`, because a harness that cannot say `gap` has not cleared any of
these rows, it has only failed to.

    JOINTS_BIN=$(python3 tool/pin.py path adjudicate) \
      python3 research/joinery/adjudicate/adjudicate.py run
    ... adjudicate.py probe kotlin-supertypes    # both trees, side by side
    ... adjudicate.py prove                      # can it still say no

Exit 0 measured, 1 a clean negative (a control walled, or `prove` could not say
no), 2 could not run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))

import differential as d  # noqa: E402
from order import BIN, GRAMMARS, folio_for  # noqa: E402
from stamp import ask, take  # noqa: E402

HERE = Path(__file__).resolve().parent
WITNESS = HERE / "witness"
WORK = ROOT / ".local" / "adjudicate"
PATIENCE = 120


class Row(NamedTuple):
    """One `GAPS.md` row, and the file that settles it."""

    id: str
    grammar: str
    wall: str  # as GAPS.md spells it - a label, never a key
    cost: int  # the peel's byte price
    witness: str
    construct: str
    focus: str  # the literal bytes of the construct inside the witness
    control: str = ""  # an innocent from the same grammar

    @property
    def file(self) -> Path:
        return WITNESS / self.witness

    def span(self) -> tuple[tuple[int, int], tuple[int, int]]:
        """Where the construct sits, as tree-sitter spells a position.

        **A whole-file verdict is the wrong instrument and the first table this
        harness printed proved it.** Blinding a scanner takes out every external
        the grammar has, so kotlin's `_automatic_semicolon` goes with it and the
        file breaks at a line ending three statements away from anything under
        adjudication - and the row reads `external` on evidence about a
        semicolon. What a row is entitled to ask is whether an `ERROR` lands on
        *these bytes*, so that is what it asks."""
        text = self.file.read_bytes()
        at = text.find(self.focus.encode())
        if at < 0:
            raise ValueError(f"{self.id}: focus not in {self.witness}")
        return _at(text, at), _at(text, at + len(self.focus.encode()))


def _at(text: bytes, off: int) -> tuple[int, int]:
    """Byte offset to tree-sitter's `[row, column]`, counted in bytes."""
    row = text.count(b"\n", 0, off)
    return row, off - (text.rfind(b"\n", 0, off) + 1)


# The eighteen, keyed on the source text at the wall rather than on a state
# number: two binaries differing by one line renumbered the whole LR(0)
# collection here (9,763 -> 9,276 states), so a row keyed on `state 68` need not
# name the same state on the build you are holding. `locate.py` derives the
# offsets; the construct column is what a witness is authored from.
#
# GAPS.md renders verilog's backtick terminal as an apostrophe - a backtick
# wrapped in backticks inside a markdown table cell. Rows 9 and 10 are
# `ifdef/`endif, not string quoting.
ROWS: tuple[Row, ...] = (
    Row("php-encapsed", "php", "/ in state 68", 40_996,
        "php-encapsed-regex.php",
        'preg_replace("/(.*)\\s.*/", \'$1\', $trimmed) - the / is inside a '
        "double-quoted string",
        '"/(.*)\\s.*/"', "php-control-single-quoted.php"),
    Row("kotlin-supertypes", "kotlin", ", in state 110", 35_369,
        "kotlin-two-supertypes.kt",
        "object EmptyMap : Map<Any?, Nothing>, Serializable - the comma between "
        "two delegation specifiers",
        "Map<Any?, Nothing>, Serializable", "kotlin-control-one-supertype.kt"),
    Row("elixir-pipe-alias", "elixir", "alias in state 100", 25_556,
        "elixir-pipe-alias.ex",
        "routes |> Enum.map(&elem(&1, 1).path) - a capitalised alias after |>, "
        "all 14 hits",
        "|> Enum.map(&elem(&1, 1).path)", "elixir-control-nested-call.ex"),
    Row("julia-macro-juxt", "julia", "_word_identifier in state 674", 3_420,
        "julia-macro-juxtaposed.jl",
        "@assert (expr) arg - a macro call with a juxtaposed second argument, "
        "then the next statement",
        "@assert (res isa AbstractDict && A isa AbstractDict) msg\n"
        "    count == 0 && return res", "julia-control-plain.jl"),
    Row("cpp-string-concat", "cpp", '" in state 907', 638,
        "cpp-string-plus-call.cpp",
        'push("seed" + std::to_string(i), s[i])',
        'push("seed" + std::to_string(i), s[i]);', "cpp-control-plain-call.cpp"),
    Row("bash-regex-test", "bash", "] in state 35", 495,
        "bash-regex-test.sh",
        "if [[ ! $value =~ ^-?[0-9]+$ ]]; then",
        "[[ ! $value =~ ^-?[0-9]+$ ]]", "bash-control-plain-test.sh"),
    Row("elixir-pipe-call", "elixir",
        "(?u:[_\\p{Ll}\\p{Lm}\\p{Lo}\\p{Nl}\\x{1885}\\x{1886}\\x{2118}\\x{212E}"
        "\\x{309B}\\x{309C}][\\p{ID_Continue}]*[?!]?) in state 100", 148,
        "elixir-pipe-call.ex",
        "|> then(fn {a, b} -> ... end) - a lowercase call after |>",
        "|> then(fn {match_routes_exprs, rest} -> {rest, match_routes_exprs} end)",
        "elixir-control-nested-call.ex"),
    Row("zig-char-array", "zig", "{ in state 715", 58,
        "zig-array-of-char.zig",
        "pub const whitespace = [_]u8{ ' ', '\\t', ... };",
        "[_]u8{ ' ', '\\t', '\\n', '\\r' }", "zig-control-plain-const.zig"),
    Row("verilog-endif", "verilog", "` in state 534", 36,
        "verilog-ifdef-ports.v",
        "`endif inside a module port list",
        "`endif", "verilog-control-plain-ports.v"),
    Row("verilog-ifdef", "verilog", "` in state 3438", 21,
        "verilog-ifdef-ports.v",
        "`ifdef RISCV_FORMAL inside a module port list",
        "`ifdef RISCV_FORMAL", "verilog-control-plain-ports.v"),
    Row("cpp-stream-chain", "cpp", "; in state 184", 14,
        "cpp-stream-chain.cpp",
        'std::cout << kBanner << "total=" << led.total() << "\\n";',
        'std::cout << kBanner << "total=" << led.total() << "\\n";',
        "cpp-control-plain-call.cpp"),
    Row("latex-verbatim", "latex", "< in state 1739", 10,
        "latex-verbatim-angle.tex",
        "\\usepackage{latexsym,<packages>} inside \\begin{verbatim} - and the "
        "body's FIRST token whatever it is; `plain words only` walls too",
        "\\usepackage{latexsym,<packages>}", "latex-control-plain.tex"),
    Row("scala-string-arg", "scala", '" in state 610', 9,
        "scala-string-arg.scala",
        'throw new NoSuchElementException("None.get")',
        'new NoSuchElementException("None.get")',
        "scala-control-no-string.scala"),
    Row("c-fputs-comma", "c", ", in state 822", 8,
        "c-fputs-comma.c", "fputs(BANNER, stdout);",
        "fputs(BANNER, stdout);", "c-control-no-string.c"),
    Row("c-open-quote", "c", '" in state 401', 7,
        "c-printf-format.c", 'printf("total=%ld\\n", total); - the opening quote',
        'printf("total=%ld\\n", total);', "c-control-no-string.c"),
    Row("swift-labelled", "swift", "(?:[^\\r\\n]*) in state 66", 7,
        "swift-labelled-args.swift",
        "endOfChunk(startingAt: base.startIndex, offset: 0)",
        "endOfChunk(startingAt: base.startIndex, offset: 0)",
        "swift-control-one-arg.swift"),
    Row("c-format-percent", "c", "% in state 171", 3,
        "c-printf-format.c",
        'the % inside "total=%ld\\n" - downstream of the opening quote, which '
        'walls first in every C source where a % can appear at all', '"total=%ld\\n"', "c-control-no-string.c"),
    Row("verilog-sized", "verilog", "2 in state 1328", 3,
        "verilog-sized-literal-concat.v",
        "{..., 2'b00} - a sized literal in a concatenation",
        "{mem_rdata_latched[12:11], mem_rdata_latched[5], 2'b00}",
        "verilog-control-plain-ports.v"),
)


# ------------------------------------------------------------------ their side

STUB = """\
// Every external this grammar declares, answered `no`. What still parses
// against this scanner is derived by `grammar.json` alone, which is the whole
// question `ours` against `external` turns on.
#include <stdbool.h>
#include <stdlib.h>

typedef struct TSLexer TSLexer;

void *tree_sitter_%(name)s_external_scanner_create(void) { return calloc(1, 1); }
void tree_sitter_%(name)s_external_scanner_destroy(void *p) { free(p); }
unsigned tree_sitter_%(name)s_external_scanner_serialize(void *p, char *b) {
  (void)p; (void)b; return 0;
}
void tree_sitter_%(name)s_external_scanner_deserialize(void *p, const char *b,
                                                       unsigned n) {
  (void)p; (void)b; (void)n;
}
bool tree_sitter_%(name)s_external_scanner_scan(void *p, TSLexer *l,
                                                const bool *valid) {
  (void)p; (void)l; (void)valid; return false;
}
"""


def cli(args: list[str], cwd: Path, lib: Path) -> subprocess.CompletedProcess[str]:
    """Their CLI, with a library cache **this** arm owns.

    The real and the stubbed parser have the same language name, and the loader
    caches a compiled parser by that name. One shared cache and the second arm
    silently answers with the first arm's scanner - which is precisely the
    measurement being made, reported backwards."""
    lib.mkdir(parents=True, exist_ok=True)
    seat = lib.parent / f"{lib.name}-seat"
    seat.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "TREE_SITTER_LIBDIR": str(lib), "XDG_CACHE_HOME": str(seat)}
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd, env=env,
                          timeout=PATIENCE)


def language(name: str) -> str:
    """The name the scanner's symbols are spelled with."""
    return json.loads((GRAMMARS / f"{name}.json").read_text())["name"]


def blinded(name: str) -> Path | None:
    """A clone of one grammar's oracle home whose scanner always says no.

    Returns None for a grammar that declares no externals, because there is
    nothing to blind and the two arms would be the same measurement wearing two
    hats. Six of the eighteen rows are in that position and it is the cleanest
    fact on the board: zig, verilog and c ship no scanner at all, so those rows
    cannot be `external` however they come out."""
    if not json.loads((GRAMMARS / f"{name}.json").read_text()).get("externals"):
        return None
    live, mine = d.oracle_root(name), WORK / "blind" / name
    if not live.exists():
        return None
    if mine.exists():
        shutil.rmtree(mine)
    shutil.copytree(live, mine)
    stub = STUB % {"name": language(name)}
    for leaf in list(mine.rglob("scanner.c")) + list(mine.rglob("scanner.cc")):
        leaf.write_text(stub)
    for leaf in mine.rglob("scanner.h"):  # php/ocaml/typescript shims include one
        leaf.write_text("/* blinded */\n")
    # The stub redefines what the header used to; leave the shim's include
    # resolving to an empty file rather than deleting a path parser.c may want.
    return mine / d.oracle_home(name).relative_to(live)


ERRORS = re.compile(r"\((ERROR|MISSING)[^\[]*\[(\d+), (\d+)\] - \[(\d+), (\d+)\]")


def hurt(tree: str, lo: tuple[int, int], hi: tuple[int, int]) -> str:
    """The first `ERROR`/`MISSING` whose extent touches `[lo, hi)`, or "".

    A whole-file verdict answers a question no row asked. Blinding a scanner
    removes every external at once, so kotlin loses `_automatic_semicolon` and
    the file breaks at a line ending nowhere near the two supertypes under
    adjudication - and a whole-file reading files that as `external` on evidence
    about a semicolon. It did, on the first table this printed, for 35,369 B.
    """
    for m in ERRORS.finditer(tree):
        a, b = (int(m[2]), int(m[3])), (int(m[4]), int(m[5]))
        if a < hi and lo < b or a == b == lo:  # overlap, or a zero-width MISSING
            return f"{m[1]} [{a[0]},{a[1]}]-[{b[0]},{b[1]}]"
    return ""


class Theirs(NamedTuple):
    ok: bool  # a tree came back at all
    tree: str
    why: str
    hit: str = ""  # what landed on the construct's own bytes, if anything

    @property
    def clean(self) -> bool:
        """Clean **over the construct**, which is the only span a row is
        entitled to a verdict about."""
        return self.ok and not self.hit

    @property
    def invented(self) -> bool:
        """Did they answer with a token the source does not contain?

        `ERROR` is tree-sitter declining these bytes - the honest shape of a
        real gap. `MISSING` is tree-sitter *asserting a terminal it never read*
        and building structure on top of it, so the tree it returns says
        something about the file that is false. That is the fourth outcome in
        the brief, and it is the difference between "nobody can parse this" and
        "both of us parse it wrong"."""
        return self.hit.startswith("MISSING")

    @property
    def word(self) -> str:
        if self.clean:
            return "clean"
        if not self.ok:
            return "no tree"
        return "invents" if self.invented else "refuses"


def theirs(home: Path, src: Path, lib: Path,
           span: tuple[tuple[int, int], tuple[int, int]] | None = None) -> Theirs:
    got = cli([str(d.TS), "parse", "-p", str(home), str(src.resolve())],
              d.WORK, lib)
    if not got.stdout.strip():
        return Theirs(False, "", d.gripe(got.stderr))
    hit = hurt(got.stdout, *span) if span else (
        m[0] if (m := ERRORS.search(got.stdout)) else "")
    return Theirs(True, got.stdout, "", hit)


# -------------------------------------------------------------------- our side

REFUSED = re.compile(r"unexpected (.+?) at \d+ in state")


class Mine(NamedTuple):
    whole: bool
    kind: str
    verdict: str
    tree: str

    @property
    def wall(self) -> str:
        """The terminal this parse refused, or "" if it refused nothing."""
        return m[1] if (m := REFUSED.search(self.verdict)) else ""


def mine(name: str, src: Path) -> Mine | None:
    folio = folio_for(name, WORK)
    if folio is None:
        return None
    out = ask(BIN, folio, src, tree=True, patience=PATIENCE)
    return Mine(out.kind == "whole", out.kind, out.verdict, out.tree)


# ----------------------------------------------------------------- the verdict

class Verdict(NamedTuple):
    row: Row
    us: Mine | None
    them: Theirs
    blind: Theirs | None  # None when the grammar declares no externals
    innocent: Mine | None

    @property
    def word(self) -> str:
        if self.us is None or not self.them.ok:
            return "unrun"
        if not self.them.clean:
            return "both wrong" if self.them.invented else "gap"
        if self.us.whole:
            return "void"  # both accept it; the row's wall has no construct
        # They derive it and we refuse it. Did grammar.json alone suffice?
        if self.blind is None:
            return "ours"  # nothing to blind - no scanner exists here
        return "ours" if self.blind.clean else "external"

    @property
    def sound(self) -> bool:
        """Did the innocent from this grammar parse? A grammar whose innocent
        walls is measuring the witness author, not the grammar."""
        return self.innocent is not None and self.innocent.whole

    @property
    def faithful(self) -> str:
        """Does the witness reproduce the wall `GAPS.md` named?

        The whole adjudication rests on the witness being about the row, and
        nothing else here checks that. A witness joints accepts cannot be
        carrying the row's defect at all (that is what `void` says out loud);
        one that walls on a *different* terminal is a second defect wearing the
        row's price, which is exactly the failure that made a lane's shrinker
        green while destructive."""
        want = self.row.wall.split(" in state")[0]
        got = self.us.wall if self.us else ""
        if not got:
            return "accepts"
        return "same" if got == want else f"{got}!={want}"


def judge(row: Row, homes: dict[str, Path | None]) -> Verdict:
    span = row.span()
    them = theirs(d.oracle_home(row.grammar), row.file, WORK / "lib" / "live", span)
    blind = None
    if (stub := homes.get(row.grammar)) is not None:
        blind = theirs(stub, row.file, WORK / "lib" / "blind", span)
    us = mine(row.grammar, row.file)
    innocent = mine(row.grammar, WITNESS / row.control) if row.control else None
    return Verdict(row, us, them, blind, innocent)


def prepare(names: set[str]) -> dict[str, Path | None]:
    out: dict[str, Path | None] = {}
    for name in sorted(names):
        home = d.oracle_home(name)
        try:
            d.oracle_build(home, GRAMMARS / f"{name}.json")
        except ValueError as bad:
            print(f"adjudicate: {name}: {bad}", file=sys.stderr)
        out[name] = blinded(name)
    return out


WORDS = {"gap": "the verdict stands - nobody in this tree",
         "both wrong": "they answer with a token the file does not contain",
         "ours": "grammar.json derives it; the gap verdict is wrong",
         "external": "an external we have not seated",
         "void": "both parsers take the construct; the wall is peel context",
         "unrun": "could not be measured"}


def report(seen: list[Verdict]) -> None:
    print(f"\n{'row':<20}{'grammar':<9}{'B':>8}  {'joints':<9}{'wall':<14}"
          f"{'tree-sitter':<12}{'blinded':<12}{'verdict':<10}innocent")
    for v in seen:
        us = v.us.kind if v.us else "-"
        bl = v.blind.word if v.blind else "no scanner"
        print(f"{v.row.id:<20}{v.row.grammar:<9}{v.row.cost:>8,}  {us:<9}"
              f"{v.faithful:<14}{v.them.word:<12}{bl:<12}{v.word:<11}"
              f"{'ok' if v.sound else 'WALLED'}")
    total = sum(v.row.cost for v in seen)
    print()
    for word in ("gap", "ours", "external", "both wrong", "void", "unrun"):
        mine_ = [v for v in seen if v.word == word]
        if not mine_:
            continue
        cost = sum(v.row.cost for v in mine_)
        print(f"  {word:<11}{len(mine_):>3} row(s){cost:>10,} B  "
              f"{100.0 * cost / total:>5.1f}%  - {WORDS[word]}")
    print(f"  {'total':<11}{len(seen):>3} row(s){total:>10,} B")
    sick = sorted({v.row.grammar for v in seen if not v.sound})
    if sick:
        print(f"\n**{len(sick)} grammar(s) whose innocent control walled: "
              f"{', '.join(sick)}.** Their rows measure the witness author "
              f"rather than the grammar and do not ship.")
    print(take(BIN).line())


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("verb", nargs="?", default="run",
                    choices=("run", "probe", "prove", "list"))
    ap.add_argument("which", nargs="?", help="a row id, for `probe`")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    if args.verb == "list":
        for r in ROWS:
            print(f"{r.id:<20}{r.grammar:<9}{r.cost:>8,}  {r.construct}")
        return 0
    if not BIN.exists():
        print(f"adjudicate: no binary at {BIN}", file=sys.stderr)
        return 2
    if not d.oracle_ready():
        print("adjudicate: no tree-sitter CLI; `differential.py install`", file=sys.stderr)
        return 2
    WORK.mkdir(parents=True, exist_ok=True)

    if args.verb == "prove":
        return prove()

    rows = [r for r in ROWS if not args.which or r.id == args.which]
    if args.which and not rows:
        print(f"adjudicate: no row {args.which!r}", file=sys.stderr)
        return 2
    homes = prepare({r.grammar for r in rows})
    seen = [judge(r, homes) for r in rows]

    if args.verb == "probe":
        for v in seen:
            print(f"\n=== {v.row.id}  ({v.row.grammar}, {v.row.cost:,} B)")
            print(f"    {v.row.construct}")
            print(f"    GAPS.md says: {v.row.wall}\n")
            print(f"--- joints: {v.us.verdict if v.us else 'not run'}")
            print(v.us.tree if v.us else "")
            print(f"--- tree-sitter: {v.them.word}")
            print(v.them.tree)
            if v.blind:
                print(f"--- tree-sitter, scanner blinded: {v.blind.word}")
                print(v.blind.tree)
        return 0

    if args.json:
        print(json.dumps([{"id": v.row.id, "grammar": v.row.grammar,
                           "bytes": v.row.cost, "gaps_wall": v.row.wall,
                           "construct": v.row.construct,
                           "joints": v.us.kind if v.us else None,
                           "joints_verdict": v.us.verdict if v.us else None,
                           "theirs": v.them.word, "theirs_why": v.them.why,
                           "blinded": v.blind.word if v.blind else "no scanner",
                           "verdict": v.word, "innocent_ok": v.sound}
                          for v in seen], indent=2))
        return 0
    report(seen)
    return 0 if all(v.sound for v in seen) else 1


# ------------------------------------------------------------- the anti-vacuity

# Constructs that genuinely are not in the language, so `gap` is the right
# answer and a harness that cannot produce it has cleared nothing. Each is the
# same *shape* as a real row - a punctuation refusal in a statement position -
# so it exercises the same path rather than a degenerate one.
FALSE = (("c", "int main(void) { let x := 3 ?? 4; }", "gap"),
         ("zig", "pub fn main() void { x <=> y; }", "gap"),
         ("kotlin", "fun main() { val x = <<<>>>; }", "gap"))


def prove() -> int:
    """Ask every arm to say no where no is right, and watch it.

    Three checks. (1) A construct the language does not have must come back
    `gap` - otherwise every `ours` on the board is the harness being unable to
    refuse. (2) A blinded scanner must actually blind something: a grammar with
    externals whose blinded arm is byte-identical to its live arm on a witness
    that needs the scanner is a stub that never got compiled in, and the whole
    ours/external split would be a coin. (3) A verdict corrupted in memory must
    change the word, so the classifier is reading its inputs rather than a
    constant.
    """
    WORK.mkdir(parents=True, exist_ok=True)
    bad = 0
    homes = prepare({g for g, _, _ in FALSE} | {"latex"})
    for name, text, want in FALSE:
        leaf = WORK / f"false.{name}"
        leaf.write_text(text)
        got = theirs(d.oracle_home(name), leaf, WORK / "lib" / "live")
        row = Row(f"false-{name}", name, "-", 0, "", "invented", "")
        v = Verdict(row, Mine(False, "state", "", ""), got,
                    theirs(homes[name], leaf, WORK / "lib" / "blind")
                    if homes.get(name) else None, Mine(True, "whole", "", ""))
        ok = v.word == want
        bad += not ok
        print(f"  {'ok ' if ok else 'NO '} invented {name:<8} -> {v.word:<9} "
              f"(want {want})")

    # (2) the blinding is load-bearing. latex's verbatim body is an external;
    # blinded, that witness must stop being clean **over its own construct**. If
    # it does not, the stub is not in the binary being run and `external` is
    # unearned everywhere.
    row = next(r for r in ROWS if r.id == "latex-verbatim")
    span = row.span()
    live = theirs(d.oracle_home("latex"), row.file, WORK / "lib" / "live", span)
    off = theirs(homes["latex"], row.file, WORK / "lib" / "blind", span)
    moved = live.clean and not off.clean
    bad += not moved
    print(f"  {'ok ' if moved else 'NO '} blinding latex breaks the construct it "
          f"scans (live {live.word}, blinded {off.word})")

    # (3) the localiser reads a span rather than a file. An ERROR three lines
    # away must NOT be read as landing on the construct - that misreading is
    # what a whole-file verdict does, and it cost this harness 35,369 B once.
    tree = "(a [0, 0] - [9, 0] (ERROR [7, 0] - [7, 4]))"
    near = hurt(tree, (7, 1), (7, 3))
    far = hurt(tree, (2, 0), (2, 6))
    ok = bool(near) and not far
    bad += not ok
    print(f"  {'ok ' if ok else 'NO '} an ERROR is seen on its own span and not "
          f"on a distant one (on={bool(near)}, off={bool(far)})")

    # (4) the classifier reads its inputs.
    clean = Verdict(ROWS[0], Mine(False, "state", "", ""), Theirs(True, "", ""),
                    Theirs(True, "", ""), Mine(True, "whole", "", ""))
    spoilt = clean._replace(them=Theirs(True, "", "", "ERROR [0,0]-[0,1]"))
    flips = clean.word == "ours" and spoilt.word == "gap"
    bad += not flips
    print(f"  {'ok ' if flips else 'NO '} corrupting a clean tree flips ours -> gap")
    print(f"\nprove: {6 - bad} of 6 guards can say no." if bad else
          "\nprove: all 6 guards said no where no was right.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
