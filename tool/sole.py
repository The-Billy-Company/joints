#!/usr/bin/env python3
"""Is there exactly one of each rule, still?

Six second copies were found here by hand, and five of them were live defects.
Every one had the same shape: an instrument that needed a fact, wrote its own
way of getting it, and then went on answering with the old way after the real
one was fixed. The reach rule was the expensive one - three copies, and only
`recover`'s knew that a mended parse keeps reading, so the other two reported
the files that read the most as the ones that read least, for 28 points of
byte coverage.

An audit finds those once. Nobody remembers to run the audit again, so this is
the audit as a gate.

**It holds no copy of what it polices**, which matters more than it sounds
like: a checker that restates the rules is itself the seventh copy, and the
first thing to drift. It is handed a map of who owns what - `CLAIMS`, the one
fact here - and derives every witness by reading the owner's own source. Change
`stamp.outcome`'s vocabulary and this gate changes with it, with nothing to
update.

Two shapes are caught, and they are the two that actually happened:

  a restated fact       another file matching or comparing against a string
                        the owner owns - a verdict word, a regex, a grammar
                        name it typed out instead of deriving
  a restated exchange   another file running the binary and reading its
                        verdict back, which is how a fifth reader gets written
                        even after the rule is shared

A string is only a finding where it is *tested* - a `startswith`, an `==`, an
`in`, a `re.compile`. Printing the word `mended` in a table is what a report is
for; branching on it is a second copy.

**Its corpus is `tool/*.py` and nothing else, which is a hole rather than a
scope.** It globs this one directory and reads it with Python's `ast`, so the
entire Zig product - every rule the parser itself implements - is outside what
it can see. That is not a boundary anyone chose: the shape it polices is a
property of code, not of a language, and it has already been paid for once. A
containment rule spelled twice in Zig, live in one place and dead in a test,
went straight past this gate, because there was never a pass over `src/` for it
to be caught by. Extending the corpus needs a Zig reader and is its own piece of
work; until then the gate says so on every run rather than presenting one green
line for a reach it does not have.

  python3 tool/sole.py           the audit; exit 1 if a second copy exists
  python3 tool/sole.py --list    what each owner is understood to own
  python3 tool/sole.py --probe   build the copies it claims to catch, and catch them
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path
from typing import NamedTuple

TOOL = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL))


class Claim(NamedTuple):
    """One rule, its owner, and where in the owner to read it from.

    `where` names functions rather than the whole module because a module also
    contains its own report text, and a docstring saying `mended` is not a
    second implementation of anything.
    """

    what: str
    owner: str
    where: tuple[str, ...] = ()  # functions whose tested strings are the witness
    regexes: bool = False  # module-level re.compile patterns are the witness
    roster: str = ""  # a live list nobody may type out: corpus · breadth
    argv: tuple[str, ...] = ()  # subcommands only the owner may shell
    by: str = ""  # which binary, since `parse` is a verb of both of them
    raw: bool = True  # only a file holding raw process output can re-derive it


# The one fact this file holds - who owns what, and where in the owner to read
# it. Everything the gate then matches on is derived from the owner's source.
CLAIMS: tuple[Claim, ...] = (
    Claim("the verdict vocabulary", "stamp", ("outcome", "verdict", "behind")),
    Claim("the verdict regexes", "stamp", regexes=True),
    Claim("running joints for a verdict", "stamp", ("ask",), argv=("parse",), by="BIN"),
    Claim("the corpus list", "rung1", roster="corpus", raw=False),
    Claim("the held-out list", "breadth", roster="breadth", raw=False),
    Claim("the scanner include walk", "differential", ("beside", "lay"), regexes=True),
    Claim("the oracle sandbox", "differential", ("oracle_home", "oracle_root", "named")),
    Claim("the oracle build", "differential", ("oracle_build",),
          argv=("generate",), by="TS"),
    Claim("running the oracle", "differential", ("oracle_run",), argv=("parse",), by="TS"),
    Claim("our own tree reader", "differential", ("ours_tree", "head", "unquote")),
)

# A name is a name; a grammar list typed out is a second copy. One or two
# grammars named in a probe or a skip is ordinary, so the floor is the point
# where a collection is plainly standing in for the roster.
ENOUGH = 6


class Copy(NamedTuple):
    what: str
    owner: str
    file: str
    line: int
    why: str
    excused: str = ""  # the `# sole:` reason written beside it, if there is one


# An exception has to be written down where it lives, the way a MONOLITHIC
# marker is. Two exist and both are real distinctions rather than fatigue:
# `bench` shells the parse because the run *is* the measurement, and `rung1`
# reads the word `accepted` out of a different verb's report entirely.
EXCUSE = "# sole:"
LOOK_BACK = 4  # lines above the finding a reason may sit on


def tree_of(name: str) -> ast.Module:
    return ast.parse((TOOL / f"{name}.py").read_text(), filename=f"{name}.py")


def bodies(tree: ast.Module, names: tuple[str, ...]) -> list[ast.AST]:
    """The named functions with their docstrings dropped."""
    out: list[ast.AST] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef) and node.name in names:
            body = node.body[1:] if ast.get_docstring(node) else node.body
            out.extend(body)
    return out


def tested(nodes: list[ast.AST]) -> set[str]:
    """Strings a piece of code *decides* with, as opposed to prints.

    The distinction is the whole reason this gate is usable: `census` says the
    word `mended` in three table headings and owns none of them, while one
    `said.startswith("mended")` anywhere outside `stamp` is a second rule.
    """
    out: set[str] = set()

    def literal(node: ast.AST) -> None:
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            if len(node.value) >= 4:
                out.add(node.value)

    for root in nodes:
        for node in ast.walk(root):
            if isinstance(node, ast.Compare):  # ==, !=, in, not in
                literal(node.left)
                for side in node.comparators:
                    literal(side)
            elif isinstance(node, ast.Call):
                name = (node.func.attr if isinstance(node.func, ast.Attribute)
                        else node.func.id if isinstance(node.func, ast.Name) else "")
                if name in ("startswith", "endswith", "compile", "search", "match",
                            "findall", "fullmatch", "split", "count", "index"):
                    for arg in node.args:
                        literal(arg)
    return out


def patterns(tree: ast.Module) -> set[str]:
    """Module-level `re.compile("...")` pattern strings."""
    out = set()
    for node in tree.body:
        if isinstance(node, ast.Assign | ast.AnnAssign):
            value = node.value
            if (isinstance(value, ast.Call) and isinstance(value.func, ast.Attribute)
                    and value.func.attr == "compile" and value.args):
                arg = value.args[0]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    out.add(arg.value)
                elif isinstance(arg, ast.Constant) and isinstance(arg.value, bytes):
                    out.add(arg.value.decode("utf-8", "replace"))
    return out


def roster(which: str) -> set[str]:
    """The live list, asked of the thing that derives it."""
    if which == "corpus":
        from rung1 import pairs
        return {name for name, _ in pairs()}
    from grammars import load
    return {p.name for p in load("breadth")}


def witnesses() -> dict[str, tuple[Claim, set[str]]]:
    out: dict[str, tuple[Claim, set[str]]] = {}
    for claim in CLAIMS:
        tree = tree_of(claim.owner)
        seen = tested(bodies(tree, claim.where)) if claim.where else set()
        if claim.regexes:
            seen |= patterns(tree)
        if claim.roster:
            seen |= roster(claim.roster)
        out[claim.what] = (claim, seen)
    return out


def collections(tree: ast.Module) -> list[tuple[int, set[str]]]:
    """Every literal collection of strings, with its line."""
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.List | ast.Tuple | ast.Set):
            words = {e.value for e in node.elts
                     if isinstance(e, ast.Constant) and isinstance(e.value, str)}
        elif isinstance(node, ast.Dict):
            words = {k.value for k in node.keys
                     if isinstance(k, ast.Constant) and isinstance(k.value, str)}
        else:
            continue
        if words:
            out.append((node.lineno, words))
    return out


def shells(tree: ast.Module, verbs: tuple[str, ...], by: str) -> list[tuple[int, str]]:
    """Lines where a file shells one of the subcommands somebody else owns.

    Sharing the *rule* did not stop a fifth reader from being written; sharing
    the whole exchange does, and this is the line that would announce one. It
    is a shape rather than a fact, which is why it catches a copy that shares
    no literal with the original.
    """
    out = []
    for node in ast.walk(tree):
        # Any call taking a literal argv, not just `subprocess.run` - every
        # instrument here wraps the subprocess in a helper of its own, and a
        # gate that only knew the one spelling would have missed `bench.say`.
        if not (isinstance(node, ast.Call) and node.args):
            continue
        elts = getattr(node.args[0], "elts", [])
        words = {e.value for e in elts
                 if isinstance(e, ast.Constant) and isinstance(e.value, str)}
        # `parse` is a verb of both binaries, so the argv's head is what says
        # whose exchange this is. Without it, every oracle call reads as a
        # second copy of the parse rule and the gate is noise.
        if by and not (elts and by in ast.unparse(elts[0])):
            continue
        out += [(node.lineno, verb) for verb in verbs if verb in words]
    return out


def excuse(path: Path, line: int) -> str:
    """The `# sole:` reason written at or just above a finding, if any."""
    lines = path.read_text().splitlines()
    for n in range(max(0, line - LOOK_BACK), min(line, len(lines))):
        if EXCUSE in lines[n]:
            return lines[n].split(EXCUSE, 1)[1].strip()
    return ""


def audit(where: Path = TOOL) -> list[Copy]:
    owned = witnesses()
    found: list[Copy] = []
    for path in sorted(where.glob("*.py")):
        name = path.stem
        if path.name == Path(__file__).name:
            continue
        tree = ast.parse(path.read_text(), filename=path.name)
        here = tested([n for n in tree.body])
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
                here |= tested(node.body[1:] if ast.get_docstring(node) else node.body)
        mine = patterns(tree)
        raw = handles_raw(tree)
        for what, (claim, seen) in owned.items():
            if claim.owner == name or (claim.raw and not raw):
                continue
            if claim.roster:
                for line, words in collections(tree):
                    if len(words & seen) >= ENOUGH:
                        # Excused like every other rule. This branch used to be
                        # the one that could not be answered, which made it the
                        # one rule where a real distinction had no way to be
                        # written down - and an inarguable finding is a finding
                        # people learn to scroll past.
                        found.append(Copy(what, claim.owner, name, line,
                                          f"{len(words & seen)} of the roster typed out",
                                          excuse(path, line)))
                continue
            for word in sorted((here | mine) & seen):
                at = whereabouts(tree, word)
                found.append(Copy(what, claim.owner, name, at, f"decides on {word!r}",
                                  excuse(path, at)))
            found += [Copy(what, claim.owner, name, line, f"shells `{verb}` itself",
                           excuse(path, line))
                      for line, verb in shells(tree, claim.argv, claim.by)]
    return found


def blind() -> list[Claim]:
    """Claims this gate cannot witness, which it has to say out loud.

    A rule whose owner decides with one-character strings and slicing - the
    tree readers - leaves nothing for a literal match to find, so the gate
    would pass a second copy of it in silence. That is exactly the failure this
    file exists to stop happening again, so it is reported rather than hidden
    behind a green line.
    """
    return [c for c, seen in witnesses().values() if not seen and not c.argv]


def handles_raw(tree: ast.Module) -> bool:
    """Does this file hold a process's raw output at all?

    The line between a second copy and an ordinary consumer is not visible in
    a string comparison: `census` asks `wall == "mended"` to lay out a column,
    and `rung1` asks `"accepted" in line` over the bytes a parse printed. Both
    are `==` against a word `stamp` owns; only the second one is re-deriving
    the verdict. What separates them is the input, so a file that never touches
    `.stderr` or `.stdout` is not audited for the rules read out of them - it
    has nothing to read.
    """
    return any(isinstance(n, ast.Attribute) and n.attr in ("stderr", "stdout")
               # `print(..., file=sys.stderr)` is every instrument's own voice,
               # not a process's output; counting it would put every file here.
               and not (isinstance(n.value, ast.Name) and n.value.id == "sys")
               for n in ast.walk(tree))


def whereabouts(tree: ast.Module, word: str) -> int:
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and node.value == word:
            return node.lineno
    return 0


def report(found: list[Copy]) -> int:
    bad = [c for c in found if not c.excused]
    if bad:
        print(f"{'what':<34}{'owner':<14}{'second copy':<28}why")
        print("-" * 100)
        for c in bad:
            print(f"{c.what:<34}{c.owner:<14}{f'{c.file}.py:{c.line}':<28}{c.why}")
        print(f"\n{len(bad)} second cop{'y' if len(bad) == 1 else 'ies'}; "
              "the owner already answers this - call it")
    else:
        print(f"{len(CLAIMS)} rules, one copy each")
    for c in found:
        if c.excused:
            print(f"  said out loud   {f'{c.file}.py:{c.line}':<24}{c.excused}")
    if unseen := blind():
        print(f"\n{len(unseen)} rule(s) this gate cannot witness, and a second "
              "copy of one would pass it:")
        for c in unseen:
            print(f"  {c.what:<32} {c.owner}.{'/'.join(c.where)} decides with "
                  "punctuation and slicing, not with strings a match can find")
    # The corpus, said out loud on every run for the same reason `blind` is: a
    # gate that reports only what it looked at reads as a gate that looked
    # everywhere. This one has never opened a `.zig` file, and a rule the parser
    # implements twice is exactly as much a second copy as one an instrument does.
    zig = sum(1 for _ in (TOOL.parent / "src").rglob("*.zig"))
    print(f"\ncorpus: {len(list(TOOL.glob('*.py'))) - 1} files, every one of them "
          f"`tool/*.py`. The {zig} `.zig` files under `src/` are outside it, so a "
          f"rule the product spells twice is not something this gate can fail on.")
    # The Zig half now exists and is a *different question*, so it is named here
    # rather than folded in. This gate polices a rule with an owner; that one asks
    # whether an exported function already has one. The second is a similarity
    # ranking and cannot be a pass/fail line beside these, which is exactly why
    # merging them would have made this summary less true rather than more.
    print("      `tool/incumbent.py` is the pass over `src/**/*.zig`: it ranks "
          "exported functions that share a signature shape by how much body they "
          "share, and `--probe` plants a copy of `press.retrace.back` to show the "
          "ranking has power. It reports; it does not fail a build.")
    return 1 if bad else 0


def guard(claim: Claim, seen: set[str]) -> str:
    """How a second copy of this rule would be caught, and how firmly.

    Worth printing because the two are not equally strong. A **shape** guard
    catches a copy that shares no text with the original - it is the call
    itself that gives it away. A **literal** guard only fires if the copy spells
    something the way the owner spells it, so a copy that invents its own
    vocabulary walks past. Saying which is which is the difference between a
    gate you can rely on and one you merely hope covers you.
    """
    if claim.argv:
        return f"shape: any file shelling `{'`/`'.join(claim.argv)}` on {claim.by}"
    if claim.roster:
        return f"shape: any literal list holding {ENOUGH}+ of the roster"
    if not seen:
        return "NOTHING - no literal to match, no shape to see"
    return f"literal: {len(seen)} word(s), and only if a copy reuses one"


def listing() -> int:
    print(f"{'what':<32}{'owner':<13}{'seen':>5}  caught by")
    print("-" * 104)
    for what, (claim, seen) in witnesses().items():
        print(f"{what:<32}{claim.owner:<13}{len(seen):>5}  {guard(claim, seen)}")
    firm = sum(g.startswith("shape") for g in
               (guard(c, s) for c, s in witnesses().values()))
    print(f"\n{firm} of {len(CLAIMS)} rules are caught by shape; the rest need a "
          "copy to reuse one of the owner's own words")
    return 0


# One file per shape the gate claims to catch, written the way somebody
# actually writes a second copy: not by copying the owner, but by needing a
# fact and reaching for the nearest way to get it.
ADVERSE: tuple[tuple[str, str], ...] = (
    ("a restated verdict", '''
import subprocess
def look(p):
    got = subprocess.run(["x"], capture_output=True)
    return got.stderr.strip().endswith("accepted")
'''),
    ("a restated exchange", '''
import subprocess
BIN = "joints"
def look(g, s):
    got = subprocess.run([str(BIN), "parse", str(g), str(s)], capture_output=True)
    return got.stdout
'''),
    ("a restated roster", '''
CORPUS = ["c", "cpp", "go", "java", "javascript", "json", "python"]
'''),
    ("a wrapper hiding the exchange", '''
BIN = "joints"
def say(cmd): return cmd
def look(g, s):
    out = say([str(BIN), "parse", str(g), str(s)]).stdout
    return out
'''),
)


def probe() -> int:
    """Show the gate biting, on a tree built to make it bite.

    A gate nobody has watched fail is decoration. Written into a scratch copy
    of `tool/` rather than into the real one, because nine other agents are
    editing this checkout and a staged defect in a tracked file is somebody
    else's confusing afternoon.
    """
    import shutil
    import tempfile
    bad = 0
    print(f"{'a second copy shaped like':<34}{'caught':<10}why")
    print("-" * 92)
    with tempfile.TemporaryDirectory() as tmp:
        yard = Path(tmp) / "tool"
        yard.mkdir()
        for what, body in ADVERSE:
            for p in TOOL.glob("*.py"):
                shutil.copy2(p, yard / p.name)
            (yard / "copycat.py").write_text(body)
            found = [c for c in audit(yard) if c.file == "copycat" and not c.excused]
            bad += not found
            print(f"{what:<34}{'yes' if found else 'NO':<10}"
                  f"{found[0].why if found else 'the gate would have passed it'}")
    print(f"\n{len(ADVERSE) - bad}/{len(ADVERSE)} adverse shapes caught")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--list" in sys.argv:
        raise SystemExit(listing())
    raise SystemExit(probe() if "--probe" in sys.argv else report(audit()))
