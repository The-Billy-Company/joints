#!/usr/bin/env python3
"""The 943 bytes the finding lane declined to check, checked.

`judge.py` re-priced verilog's `veiled` population by innermost cover and freed
4,373 of 4,644 bytes to `slack`. Its own caution was that `slack` is a claim
about BOTH trees - "under no leaf on either" - and it verified only that
tree-sitter's cover is healthy. On the 3,430 bytes where the two trees name that
cover identically the agreement is its own evidence. On the remaining **943 it
was trusting tree-sitter without checking**, and a healthy node built in the
wrong place is indistinguishable from a healthy node built in the right one if
tree-sitter is the only parser you ask.

So ask a third. Verible lexes SystemVerilog **as written** - no preprocessor,
byte offsets on every token - which is the same text both trees read, and it is
the only judge here that can answer either question:

  DOES A TOKEN STAND HERE?  `slack` says no leaf on either tree. If a real
      SystemVerilog lexer stands a token on the byte, "no token here" is a
      claim two parsers agree on and a third contradicts, and the byte is not
      adjudicated - it is two-against-one.

  IS THE COVER IN THE RIGHT PLACE?  the sharper question, and the one the
      caution is actually about. A node built in the wrong place cuts across
      real lexical structure. Verible's token boundaries are that structure, so
      a cover whose [start, end) lands on two token boundaries is a cover
      Verible corroborates the extent of, and one that slices a token in half
      is a node demonstrably in the wrong place, whatever it is named.

The second test is the falsifier. It can come back saying tree-sitter is wrong,
and if it does the 271 bound is not a bound.

    python3 research/joinery/cover/residue.py [--json]

Exit 0 checked, 1 the residue is not clean, 2 Verible is not on disk (the check
is not run and does not pretend to have been).
"""
import collections
import json
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import plumb  # noqa: E402

JUDGE = ROOT / ".local" / "judgelane" / "judge"
# Verible's own tags for bytes carrying no language token. Everything else in
# the raw stream is something a real SystemVerilog lexer named.
BLANK = {"TK_SPACE", "TK_NEWLINE", "end of file"}
# ...and the one tag that is neither. `MacroArg` is the argument of a macro
# CALL, which Verible does not lex: it captures the text verbatim and hands the
# whole thing back as a single token, spaces and semicolons and all. On
# `picorv32.v` that matters, because the file is full of
# `` `debug($display("...", a, b);) `` and every one of those arguments comes
# back as one 40-to-104-byte blob.
#
# Reading that blob as "a token stands on these bytes" is EXACTLY the mistake
# this lane exists to repair, with the parsers swapped: a refusal to answer,
# counted as an answer. The first draft of this file made it, and charged 38
# single spaces inside `$display` arguments as tokens outliner owed. So
# `MacroArg` is carved out and REPORTED rather than folded either way — Verible
# has no opinion about those bytes and this file does not invent one for it.
DEFERRED = {"MacroArg"}


def _runs(offsets: list[int]) -> list[tuple[int, int]]:
    """Consecutive byte offsets, coalesced — a report of 38 spans is not 38 facts."""
    out: list[list[int]] = []
    for p in sorted(offsets):
        if out and out[-1][1] == p:
            out[-1][1] = p + 1
        else:
            out.append([p, p + 1])
    return [(a, b) for a, b in out]


class Lexed(NamedTuple):
    """What Verible said, in three states rather than two.

    `token` and `blank` are its two verdicts. `mute` is the third state a
    two-state reading has no room for and is the whole reason this class
    exists: the bytes it declined to lex.
    """

    token: bytearray  # a real SystemVerilog token stands here
    mute: bytearray  # Verible deferred — no verdict either way
    edge: set[int]  # every offset it says one thing stops and the next begins


def verible(src: Path, size: int) -> Lexed | None:
    """Verible's raw token stream, as three masks and a boundary set.

    The boundary set is the load-bearing half. A mask can only say whether a
    byte is inside some token; the boundaries say where the lexer thinks one
    thing stops and the next begins, which is what an extent has to agree with
    to be in the right place.
    """
    exe = next(JUDGE.glob("verible-*/bin/verible-verilog-syntax"), None)
    if exe is None:
        return None
    got = subprocess.run([str(exe), "--export_json", "--printrawtokens", str(src)],
                         capture_output=True, text=True, check=False)
    if got.returncode not in (0, 1) or not got.stdout.strip():
        return None
    token, mute, edge = bytearray(size), bytearray(size), {0, size}
    for t in next(iter(json.loads(got.stdout).values()))["rawtokens"]:
        a, b = max(t["start"], 0), min(t["end"], size)
        if b <= a or t["tag"] in BLANK:
            continue
        where = mute if t["tag"] in DEFERRED else token
        where[a:b] = b"\1" * (b - a)
        # A deferred blob's own two ends ARE boundaries — Verible knows where
        # the macro argument starts and stops, it just will not look inside.
        edge |= {a, b}
    return Lexed(token, mute, edge)


def main(argv: list[str]) -> int:
    as_json = "--json" in argv
    case = next(c for c in plumb.slate() if c.name == "verilog")
    saw = plumb.read(case)
    if saw is None or saw.why:
        print(f"residue: no measurement — {saw.why if saw else 'no folio'}", file=sys.stderr)
        return 2
    size = len(saw.blob)
    o_who, t_who = plumb.paint(saw.mine, size), plumb.paint(saw.theirs, size)
    bad = plumb.hurt(saw.theirs, size, t_who)

    # The stretch population, exactly as `rack.survey` builds it: bytes of
    # `built` under no leaf of ours. Rebuilt rather than imported so this does
    # not silently follow a sibling's edit to the column it is auditing.
    stood = bytearray(size)
    for n in saw.mine:
        if n.leaf:
            stood[max(n.start, 0):min(n.end, size)] = b"\1" * (
                min(n.end, size) - max(n.start, 0))
    t_ok = bytearray(size)
    for n in saw.theirs:
        a, b = max(n.start, 0), min(n.end, size)
        if n.leaf and b > a and not n.name.startswith(plumb.HURT):
            t_ok[a:b] = b"\1" * (b - a)

    agree, differ, bound = [], [], []
    for a, b in saw.scope:
        for p in range(a, b):
            if stood[p] or t_ok[p]:
                continue  # ours, or `warp` — a different column's argument
            if t_who[p] < 0 or bad[p]:
                bound.append(p)  # the 271: refused by the cover's own verdict
                continue
            them = saw.theirs[t_who[p]]
            us = saw.mine[o_who[p]] if o_who[p] >= 0 else None
            (agree if us is not None and us.name == them.name else differ).append(p)

    saw_v = verible(case.source, size)
    if saw_v is None:
        print("residue: Verible is not on disk — see research/joinery/judge/README.md."
              "\nresidue: the residue CANNOT be checked without it and this prints no verdict.",
              file=sys.stderr)
        return 2
    mask, mute, edge = saw_v

    # Question 1 — does a token stand on a byte two trees left bare? Asked only
    # where Verible actually looked.
    deferred = [p for p in differ if mute[p]]
    charged = [p for p in differ if mask[p]]
    # Question 2 — is the cover Verible corroborates the extent of? Asked of the
    # covering NODE, once each, not of the byte: a 300-byte node is one claim
    # about placement and counting it 300 times prices confidence by width.
    #
    # A boundary is only WRONG if it cuts a token in half. A boundary landing in
    # whitespace slices nothing, and a first draft that demanded every extent
    # sit on a token boundary flagged 28 nodes for the crime of ending before a
    # newline. Over-firing is the same failure as under-firing wearing the
    # opposite sign: a falsifier nobody believes gets turned off.
    def splits(b: int) -> bool:
        return 0 < b < size and bool(mask[b - 1]) and bool(mask[b]) and b not in edge

    def inside_mute(b: int) -> bool:
        """A cut Verible has no opinion about, because it did not lex there."""
        return 0 < b < size and bool(mute[b - 1]) and bool(mute[b])

    covers = {t_who[p] for p in differ}
    ends = {i: (max(saw.theirs[i].start, 0), min(saw.theirs[i].end, size)) for i in covers}
    deferred_cut = {i for i, (a, b) in ends.items() if inside_mute(a) or inside_mute(b)}
    misplaced = {i for i, (a, b) in ends.items()
                 if i not in deferred_cut and (splits(a) or splits(b))}
    hurtbytes = [p for p in differ if t_who[p] in misplaced]
    by_name = collections.Counter(
        (saw.theirs[t_who[p]].name,
         saw.mine[o_who[p]].name if o_who[p] >= 0 else "—") for p in differ)
    charged_by = collections.Counter(
        (saw.theirs[t_who[p]].name,
         saw.mine[o_who[p]].name if o_who[p] >= 0 else "—") for p in charged)

    print(f"\nverilog {case.source.name} · {size} bytes · scope {saw.built}")
    print(f"  freed to `slack` by innermost cover     {len(agree) + len(differ):>6}")
    print(f"    both trees name the cover identically {len(agree):>6}  — agreement, self-evident")
    print(f"    the two trees name it differently     {len(differ):>6}  — THE RESIDUE")
    print(f"  refused by the cover's own verdict      {len(bound):>6}  — the bound")

    print("\nthe residue, by what each tree calls the cover")
    print(f"  {'tree-sitter':<34}{'outliner':<30}{'bytes':>7}{'Verible':>9}")
    for (t, o), n in by_name.most_common(12):
        print(f"  {t:<34}{o:<30}{n:>7}{charged_by[(t, o)]:>9}")

    out = [
        (not charged,
         f"BARE     Verible stands a token on {len(charged)} of the"
         f" {len(differ) - len(deferred)} residue byte(s) it lexed — `slack` says no leaf"
         f" stands here and a third lexer agrees"),
        (not misplaced,
         f"PLACED   none of the {len(covers) - len(deferred_cut)} covering node(s) Verible"
         f" lexed the ends of cuts a token in half"
         + (f" — {len(misplaced)} DOES, over {len(hurtbytes)} byte(s):"
            f" {', '.join(sorted({saw.theirs[i].name for i in misplaced}))}"
            if misplaced else "")),
        (len(differ) - len(deferred) > 0,
         f"LIVE     {len(differ) - len(deferred)} residue byte(s) were actually lexed by"
         f" a third parser — a check whose whole population is deferred is not a check"),
    ]
    print(f"\nVerible declined {len(deferred)} of the {len(differ)} residue byte(s) and the"
          f" ends of {len(deferred_cut)} of the {len(covers)} cover(s):"
          f" `{'`, `'.join(sorted(DEFERRED))}`, which it captures whole rather than lexes."
          f"\nThat is a REFUSAL and this file counts it as one. `picorv32.v` is full of"
          f" `` `debug($display(…);) ``\nand reading those blobs as tokens charged 38 single"
          f" spaces before this line existed.")
    for spans, why in ((charged, "a token stands here and neither tree leafs it"),
                       (hurtbytes, "the cover's own extent cuts a token in half")):
        if not spans:
            continue
        print(f"\n{why}:")
        for a, b in _runs(spans)[:8]:
            print(f"  [{a}, {b})  {b - a:>3}  {saw.blob[a:b].decode('utf-8', 'replace')!r}"
                  f"  tree-sitter {saw.theirs[t_who[a]].name}")
    for held, said in out:
        print(f"{'ok  ' if held else 'FAIL':<8}{said}")
    bad_n = sum(not held for held, _ in out)
    print(f"\n{len(out) - bad_n} of {len(out)} held")
    # And the number the caution was actually about. `271` counted bytes the
    # cover's own verdict refuses; it was called a floor because a healthy node
    # in the WRONG PLACE reads exactly like a healthy node in the right one.
    # This is the part of that gap a third parser can close, so the bound stops
    # being a floor over the population it was a floor over.
    print(f"\nthe bound, with the residue checked rather than trusted:"
          f"\n  {len(bound)} refused by the cover's own verdict"
          f"\n  + {len(hurtbytes)} whose cover Verible contradicts the EXTENT of"
          f"\n  = {len(bound) + len(hurtbytes)} — over a residue of {len(differ)}, of which"
          f" {len(differ) - len(deferred) - len(hurtbytes)} are corroborated"
          f" and {len(deferred)} are bytes Verible declined to lex.")
    if as_json:
        print(json.dumps({"agree": len(agree), "differ": len(differ), "bound": len(bound),
                          "charged": len(charged), "covers": len(covers), "deferred": len(deferred),
                          "deferred_covers": len(deferred_cut),
                          "misplaced": len(misplaced), "misplaced_bytes": len(hurtbytes),
                          "by_name": [{"theirs": t, "ours": o, "bytes": n}
                                      for (t, o), n in by_name.most_common()]}, indent=2))
    return 1 if bad_n else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
